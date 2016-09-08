//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

enum ChangeLoggingRelationChange {
    case union(Relation)
    case select(SelectExpression)
    case update(SelectExpression, Row)
}

struct ChangeLoggingRelationLogEntry {
    var forward: ChangeLoggingRelationChange
    var backward: [ChangeLoggingRelationChange]
}

private struct ChangeLoggingRelationCurrentChange {
    var added: MemoryTableRelation
    var removed: MemoryTableRelation
    
    func copy() -> ChangeLoggingRelationCurrentChange {
        return ChangeLoggingRelationCurrentChange(added: added.copy(), removed: removed.copy())
    }
}

public struct ChangeLoggingRelationSnapshot {
    var savedLog: [ChangeLoggingRelationLogEntry]
}

open class ChangeLoggingRelation<BaseRelation: Relation> {
    let baseRelation: BaseRelation
    
    var log: [ChangeLoggingRelationLogEntry] = []
    
    open var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    fileprivate var currentChange: ChangeLoggingRelationCurrentChange {
        didSet {
            fullUnderlyingRelation = type(of: self).computeFullUnderlyingRelation(baseRelation, currentChange)
        }
    }
    
    var fullUnderlyingRelation: Relation
    
    public init(baseRelation: BaseRelation) {
        self.baseRelation = baseRelation
        currentChange = ChangeLoggingRelationCurrentChange(
            added: MemoryTableRelation(scheme: baseRelation.scheme),
            removed: MemoryTableRelation(scheme: baseRelation.scheme))
        fullUnderlyingRelation = type(of: self).computeFullUnderlyingRelation(baseRelation, currentChange)
        LogRelationCreation(self)
    }
    
    fileprivate static func computeFullUnderlyingRelation(_ baseRelation: BaseRelation, _ currentChange: ChangeLoggingRelationCurrentChange) -> Relation {
        return baseRelation.difference(currentChange.removed).union(currentChange.added)
    }
    
    open func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let change = ChangeLoggingRelationChange.update(query, newValues)
        let result = applyLogToCurrentRelationAndGetChanges([change])
        return result.then({
            var reverse: [ChangeLoggingRelationChange] = []
            if let added = $0.added , added.isEmpty.ok != true {
                for row in added.rows() {
                    switch row {
                    case .Ok(let row):
                        reverse.append(.select(*!SelectExpressionFromRow(row)))
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            }
            if let removed = $0.removed , removed.isEmpty.ok != true {
                reverse.append(.union(removed))
            }
            log.append(ChangeLoggingRelationLogEntry(forward: change, backward: reverse))
            
            notifyChangeObservers($0, kind: .directChange)
            
            return .Ok()
        })
    }
}

extension ChangeLoggingRelation: MutableRelation, RelationDefaultChangeObserverImplementation {
    public var scheme: Scheme {
        return baseRelation.scheme
    }
    
    public var contentProvider: RelationContentProvider {
        return .underlying(fullUnderlyingRelation)
    }

    public func contains(_ row: Row) -> Result<Bool, RelationError> {
        return fullUnderlyingRelation.contains(row)
    }
    
    public func add(_ row: Row) -> Result<Int64, RelationError> {
        switch self.contains(row) {
        case .Ok(let contains):
            if !contains {
                let change = ChangeLoggingRelationChange.union(ConcreteRelation(row))
                let logEntry = ChangeLoggingRelationLogEntry(
                    forward: change,
                    backward: [.select(*!SelectExpressionFromRow(row))])
                log.append(logEntry)
                let result = self.applyLogToCurrentRelationAndGetChanges([change])
                return result.map({
                    notifyChangeObservers($0, kind: .directChange)
                    return 0
                })
            } else {
                return .Ok(0)
            }
        case .Err(let err):
            return .Err(err)
        }
    }
    
    public func delete(_ query: SelectExpression) -> Result<Void, RelationError> {
        return ConcreteRelation.copyRelation(self.select(query)).then({ rowsToDelete in
            let change = ChangeLoggingRelationChange.select(*!query)
            let logEntry = ChangeLoggingRelationLogEntry(
                forward: change,
                backward: [.union(rowsToDelete)])
            log.append(logEntry)
            let result = self.applyLogToCurrentRelationAndGetChanges([change])
            return result.map({
                notifyChangeObservers($0, kind: .directChange)
            })
        })
    }
    
    fileprivate func applyLogToCurrentRelation<Log: Sequence>(_ log: Log) -> Result<(didAdd: Bool, didRemove: Bool), RelationError> where Log.Iterator.Element == ChangeLoggingRelationChange {
        var didAdd = false
        var didRemove = false
        for change in log {
            switch change {
            case .union(let relation):
                for row in relation.rows() {
                    switch row {
                    case .Ok(let row):
                        currentChange.added.add(row)
                        currentChange.removed.delete(row)
                        didAdd = true
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            case .select(let query):
                didRemove = true
                currentChange.added.delete(*!query)
                for row in baseRelation.select(*!query).rows() {
                    switch row {
                    case .Ok(let row):
                        currentChange.removed.add(row)
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            case .update(let query, let newValues):
                didAdd = true
                didRemove = true
                currentChange.added.update(query, newValues: newValues)
                for toUpdate in baseRelation.select(query).difference(currentChange.removed).rows() {
                    switch toUpdate {
                    case .Ok(let row):
                        currentChange.added.add(row + newValues)
                        currentChange.removed.add(row)
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            }
        }
        let ret = (didAdd: didAdd, didRemove: didRemove)
        return .Ok(ret)
    }

    fileprivate func applyLogToCurrentRelationAndGetChanges<Log: Sequence>(_ log: Log) -> Result<RelationChange, RelationError> where Log.Iterator.Element == ChangeLoggingRelationChange {
        let before = currentChange.copy()
        let result = applyLogToCurrentRelation(log)
        return result.map({ didAdd, didRemove in
            let after = currentChange
            let added: Relation? = didAdd ? after.added.difference(before.added).union(before.removed.difference(after.removed)) : nil
            let removed: Relation? = didRemove ? before.added.difference(after.added).union(after.removed.difference(before.removed)) : nil
            
            return RelationChange(added: added, removed: removed)
        })
    }
    
    static func computeChangeFromLog<Log: Sequence>(_ log: Log, baseRelation: Relation) -> RelationChange where Log.Iterator.Element == ChangeLoggingRelationChange {
        var currentAdd: Relation = ConcreteRelation(scheme: baseRelation.scheme)
        var currentRemove: Relation = ConcreteRelation(scheme: baseRelation.scheme)
        
        for change in log {
            switch change {
            case .union(let relation):
                currentAdd = currentAdd.union(relation.difference(currentRemove))
                currentRemove = currentRemove.difference(relation)
            case .select(let query):
                currentAdd = currentAdd.select(query)
                currentRemove = currentRemove.union(baseRelation.select(*!query))
            case .update(let query, let newValues):
                currentAdd = currentAdd.withUpdate(query, newValues: newValues)
                currentAdd = currentAdd.union(baseRelation.select(query).difference(currentRemove).withUpdate(newValues))
                currentRemove = currentRemove.union(baseRelation.select(query))
            }
        }
        
        return RelationChange(added: currentAdd, removed: currentRemove)
    }
}

extension ChangeLoggingRelation where BaseRelation: SQLiteTableRelation {
    /// Save changes into the underlying database. Note that this does *not* use a transaction.
    /// Since we're likely to be saving multiple tables at once, the transaction takes place
    /// in that code to ensure everything is done together.
    public func save() -> Result<Void, RelationError> {
        let change = ChangeLoggingRelation.computeChangeFromLog(self.log.lazy.map({ $0.forward }), baseRelation: self.baseRelation)
        if let removed = change.removed {
            for row in removed.rows() {
                switch row {
                case .Ok(let row):
                    if let err = baseRelation.delete(SelectExpressionFromRow(row)).err {
                        return .Err(err)
                    }
                case .Err(let err):
                    return .Err(err)
                }
            }
        }
        
        if let added = change.added {
            for row in added.rows() {
                switch row {
                case .Ok(let row):
                    if let err = baseRelation.add(row).err {
                        return .Err(err)
                    }
                case .Err(let err):
                    return .Err(err)
                }
                
            }
        }
        
        return .Ok()
    }
}

extension ChangeLoggingRelation {
    public func takeSnapshot() -> ChangeLoggingRelationSnapshot {
        return ChangeLoggingRelationSnapshot(savedLog: self.log)
    }
    
    public func restoreSnapshot(_ snapshot: ChangeLoggingRelationSnapshot) -> Result<Void, RelationError> {
        let change = rawRestoreSnapshot(snapshot)
        return change.map({
            notifyChangeObservers($0, kind: .directChange)
        })
    }
    
    /// Restore a snapshot and compute the changes that this causes. Does not notify observers.
    func rawRestoreSnapshot(_ snapshot: ChangeLoggingRelationSnapshot) -> Result<RelationChange, RelationError> {
        // Note: right now we assume that the snapshot's log is a prefix of ours, or vice versa. We don't support
        // tree snapshots (yet?).
        if snapshot.savedLog.count > self.log.count {
            // The snapshot is ahead. Advance our state by the snapshot's log.
            let log = snapshot.savedLog.suffix(from: self.log.count)
            self.log = snapshot.savedLog
            return applyLogToCurrentRelationAndGetChanges(log.lazy.map({ $0.forward }))
        } else {
            // The snapshot is behind. Reverse our state by our backwards log.
            let log = self.log.suffix(from: snapshot.savedLog.count)
            self.log = snapshot.savedLog
            let backwardsLog = log.flatMap({ $0.backward }).reversed()
            return applyLogToCurrentRelationAndGetChanges(backwardsLog)
        }
    }
    
    func deriveChangeLoggingRelation() -> ChangeLoggingRelation<BaseRelation> {
        let relation = ChangeLoggingRelation(baseRelation: self.baseRelation)
        relation.log = self.log
        relation.currentChange = self.currentChange.copy()
        return relation
    }
    
    func restoreFromChangeLoggingRelation(_ relation: ChangeLoggingRelation<BaseRelation>) -> Result<RelationChange, RelationError> {
        // This snapshot thing is kind of elegant and ugly at the same time. It gets the job done
        // of applying the new state and retrieving the changes, anyway.
        let pretendSnapshot = relation.takeSnapshot()
        return rawRestoreSnapshot(pretendSnapshot)
    }
}
