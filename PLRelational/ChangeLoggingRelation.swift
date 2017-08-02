//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
enum ChangeLoggingRelationChange {
    case union(Relation)
    case select(SelectExpression)
    case update(SelectExpression, Row)
}

private struct ChangeLoggingRelationCurrentChange {
    var added: MemoryTableRelation
    var removed: MemoryTableRelation
    
    func copy() -> ChangeLoggingRelationCurrentChange {
        return ChangeLoggingRelationCurrentChange(added: added.copy(), removed: removed.copy())
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public struct ChangeLoggingRelationSnapshot {
    var bookmark: ChangeLoggingRelation.Graph.Bookmark
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public struct ChangeLoggingRelationDelta {
    var forward: [ChangeLoggingRelationChange]
    var reverse: [ChangeLoggingRelationChange]
    
    public var reversed: ChangeLoggingRelationDelta {
        return ChangeLoggingRelationDelta(forward: reverse, reverse: forward)
    }
}

public class ChangeLoggingRelation {
    typealias Graph = BookmarkableGraph<[ChangeLoggingRelationChange]>
    
    public var debugName: String?
    
    fileprivate var baseRelation: MutableRelation
    
    fileprivate let changeGraph: Graph
    let zeroBookmark: Graph.Bookmark
    var baseBookmark: Graph.Bookmark
    var currentBookmark: Graph.Bookmark
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    fileprivate var currentChange: ChangeLoggingRelationCurrentChange {
        didSet {
            fullUnderlyingRelation = type(of: self).computeFullUnderlyingRelation(baseRelation, currentChange)
        }
    }
    
    fileprivate var fullUnderlyingRelation: Relation
    
    public convenience init(baseRelation: MutableRelation) {
        self.init(baseRelation: baseRelation, changeGraph: Graph())
    }
    
    fileprivate init(baseRelation: MutableRelation, changeGraph: Graph) {
        self.baseRelation = baseRelation
        self.changeGraph = changeGraph
        self.zeroBookmark = changeGraph.addEmptyNode()
        self.baseBookmark = zeroBookmark
        self.currentBookmark = baseBookmark
        currentChange = ChangeLoggingRelationCurrentChange(
            added: MemoryTableRelation(scheme: baseRelation.scheme),
            removed: MemoryTableRelation(scheme: baseRelation.scheme))
        fullUnderlyingRelation = type(of: self).computeFullUnderlyingRelation(baseRelation, currentChange)
        LogRelationCreation(self)
    }
    
    fileprivate static func computeFullUnderlyingRelation(_ baseRelation: MutableRelation, _ currentChange: ChangeLoggingRelationCurrentChange) -> Relation {
        return baseRelation.difference(currentChange.removed).union(currentChange.added)
    }
    
    public func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let change = ChangeLoggingRelationChange.update(query, newValues)
        let result = applyLogToCurrentRelationAndGetChanges([change])
        return result.then({
            var reverse: [ChangeLoggingRelationChange] = []
            if let added = $0.added, added.isEmpty.ok != true {
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
            currentBookmark = changeGraph.addNode(fromBookmark: currentBookmark, outboundData: [change], inboundData: reverse)
            
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
                let reverse = ChangeLoggingRelationChange.select(*!SelectExpressionFromRow(row))
                currentBookmark = changeGraph.addNode(fromBookmark: currentBookmark, outboundData: [change], inboundData: [reverse])
                
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
            let reverse = ChangeLoggingRelationChange.union(rowsToDelete)
            currentBookmark = changeGraph.addNode(fromBookmark: currentBookmark, outboundData: [change], inboundData: [reverse])
            
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
                        _ = currentChange.added.add(row)
                        currentChange.removed.delete(row)
                        didAdd = true
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            case .select(let query):
                didRemove = true
                _ = currentChange.added.delete(*!query)
                for row in baseRelation.select(*!query).rows() {
                    switch row {
                    case .Ok(let row):
                        _ = currentChange.removed.add(row)
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            case .update(let query, let newValues):
                didAdd = true
                didRemove = true
                _ = currentChange.added.update(query, newValues: newValues)
                for toUpdate in baseRelation.select(query).difference(currentChange.removed).rows() {
                    switch toUpdate {
                    case .Ok(let row):
                        _ = currentChange.added.add(row + newValues)
                        _ = currentChange.removed.add(row)
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

extension ChangeLoggingRelation {
    /// Save changes into the underlying database. Note that this does *not* use a transaction.
    /// Since we're likely to be saving multiple tables at once, the transaction takes place
    /// in that code to ensure everything is done together.
    public func save() -> Result<Void, RelationError> {
        let log = changeGraph.computePath(from: baseBookmark, to: currentBookmark).joined()
        let change = ChangeLoggingRelation.computeChangeFromLog(log, baseRelation: self.baseRelation)
        
        return change.copy().then({ change in
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
            
            baseBookmark = currentBookmark
            return .Ok()
        })
    }
}

extension ChangeLoggingRelation {
    public func takeSnapshot() -> ChangeLoggingRelationSnapshot {
        return ChangeLoggingRelationSnapshot(bookmark: currentBookmark)
    }
    
    public func restoreSnapshot(_ snapshot: ChangeLoggingRelationSnapshot) -> Result<Void, RelationError> {
        let change = rawRestoreSnapshot(snapshot)
        return change.map({
            notifyChangeObservers($0, kind: .directChange)
        })
    }
    
    public func computeDelta(from: ChangeLoggingRelationSnapshot, to: ChangeLoggingRelationSnapshot) -> ChangeLoggingRelationDelta {
        let forward = changeGraph.computePath(from: from.bookmark, to: to.bookmark).joined()
        let reverse = changeGraph.computePath(from: to.bookmark, to: from.bookmark).joined()
        return ChangeLoggingRelationDelta(forward: Array(forward), reverse: Array(reverse))
    }
    
    public func apply(delta: ChangeLoggingRelationDelta) -> Result<Void, RelationError> {
        let changes = applyLogToCurrentRelationAndGetChanges(delta.forward)
        return changes.map({
            currentBookmark = changeGraph.addNode(fromBookmark: currentBookmark, outboundData: delta.forward, inboundData: delta.reverse)
            notifyChangeObservers($0, kind: .directChange)
        })
    }
    
    /// Restore a snapshot and compute the changes that this causes. Does not notify observers.
    func rawRestoreSnapshot(_ snapshot: ChangeLoggingRelationSnapshot) -> Result<RelationChange, RelationError> {
        let log = changeGraph.computePath(from: currentBookmark, to: snapshot.bookmark).joined()
        currentBookmark = snapshot.bookmark
        return applyLogToCurrentRelationAndGetChanges(log)
    }
    
    func deriveChangeLoggingRelation() -> ChangeLoggingRelation {
        let relation = ChangeLoggingRelation(baseRelation: self.baseRelation, changeGraph: changeGraph)
        relation.baseBookmark = baseBookmark
        relation.currentBookmark = currentBookmark
        relation.currentChange = self.currentChange.copy()
        return relation
    }
    
    func restoreFromChangeLoggingRelation(_ relation: ChangeLoggingRelation) -> Result<RelationChange, RelationError> {
        // This snapshot thing is kind of elegant and ugly at the same time. It gets the job done
        // of applying the new state and retrieving the changes, anyway.
        let pretendSnapshot = relation.takeSnapshot()
        return rawRestoreSnapshot(pretendSnapshot)
    }
}
