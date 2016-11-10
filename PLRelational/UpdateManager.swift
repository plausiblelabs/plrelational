//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public final class UpdateManager: PerThreadInstance {
    public typealias ObservationRemover = (Void) -> Void
    
    private var pendingActions: [Action] = []
    private var observedInfo: ObjectDictionary<AnyObject, ObservedRelationInfo> = [:]
    
    private let runloop: CFRunLoop
    
    private var executionTimer: CFRunLoopTimer?
    
    public init() {
        self.runloop = CFRunLoopGetCurrent()
    }
    
    public enum State {
        /// Nothing is happening, no updates have been registered.
        case idle
        
        /// Updates have been registered but are not yet running.
        case pending
        
        /// Updates are actively running.
        case running
    }
    
    private var stateObservers: [UInt64: (State) -> Void] = [:]
    private var stateObserversNextID: UInt64 = 0
    
    public var state: State = .idle {
        didSet {
            for (_, observer) in stateObservers {
                observer(state)
            }
        }
    }
    
    public func addStateObserver(_ observer: @escaping (State) -> Void) -> ObservationRemover {
        let id = stateObserversNextID
        stateObserversNextID += 1
        
        stateObservers[id] = observer
        return { self.stateObservers.removeValue(forKey: id) }
    }
    
    public func registerUpdate(_ relation: Relation, query: SelectExpression, newValues: Row) {
        pendingActions.append(.update(relation, query, newValues))
        registerChange(relation)
    }
    
    public func registerAdd(_ relation: MutableRelation, row: Row) {
        pendingActions.append(.add(relation, row))
        registerChange(relation)
    }
    
    public func registerDelete(_ relation: MutableRelation, query: SelectExpression) {
        pendingActions.append(.delete(relation, query))
        registerChange(relation)
    }
    
    public func registerRestoreSnapshot(_ database: TransactionalDatabase, snapshot: ChangeLoggingDatabaseSnapshot) {
        pendingActions.append(.restoreSnapshot(database, snapshot))
        for (_, relation) in database.relations {
            registerChange(relation)
        }
    }
    
    public func registerQuery(_ relation: Relation, callback: DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>) {
        pendingActions.append(.query(relation, callback))
        if state != .running {
            scheduleExecutionIfNeeded()
        }
    }
    
    /// Register an observer for a Relation. The observer will receive all changes made to the relation
    /// through the UpdateManager.
    public func observe(_ relation: Relation, observer: AsyncRelationChangeObserver, context: DispatchContext? = nil) -> ObservationRemover {
        guard let obj = asObject(relation) else { return {} }
        
        let info = observedInfo.getOrCreate(obj, defaultValue: ObservedRelationInfo(derivative: RelationDifferentiator(relation: relation).computeDerivative()))
        let id = info.addObserver(observer, context: context ?? defaultObserverDispatchContext())
        
        return {
            info.observers[id] = nil
            if info.observers.isEmpty {
                self.observedInfo[obj] = nil
            }
        }
    }
    
    /// Register an observer for a Relation. When the Relation is changed through the UpdateManager,
    /// the observer receives the Relation's new contents.
    public func observe(_ relation: Relation, observer: AsyncRelationContentObserver, context: DispatchContext? = nil) -> ObservationRemover {
        guard let obj = asObject(relation) else { return {} }
        
        let info = observedInfo.getOrCreate(obj, defaultValue: ObservedRelationInfo(derivative: RelationDifferentiator(relation: relation).computeDerivative()))
        let id = info.addObserver(observer, context: context ?? defaultObserverDispatchContext())
        
        return {
            info.observers[id] = nil
            if info.observers.isEmpty {
                self.observedInfo[obj] = nil
            }
        }
    }
    
    fileprivate func registerChange(_ relation: Relation) {
        if state != .running {
            sendWillChange(relation)
            scheduleExecutionIfNeeded()
        }
    }
    
    fileprivate func sendWillChange(_ relation: Relation) {
        QueryPlanner.visitRelationTree([(relation, ())], { relation, _, _ in
            guard let relationObject = asObject(relation), !(relation is IntermediateRelation) else { return }
            
            for (observedRelation, info) in observedInfo {
                for variable in info.derivative.allVariables {
                    if relationObject === variable {
                        var willChangeRelationObservers: [DispatchContextWrapped<AsyncRelationChangeObserver>] = []
                        var willChangeUpdateObservers: [DispatchContextWrapped<AsyncRelationContentObserver>] = []
                        info.observers.mutatingForEach({
                            if !$0.didSendWillChange {
                                $0.didSendWillChange = true
                                willChangeRelationObservers.appendNonNil($0.relationObserver)
                                willChangeUpdateObservers.appendNonNil($0.updateObserver)
                            }
                        })
                        for observer in willChangeRelationObservers {
                            observer.withWrapped({ $0.relationWillChange(observedRelation as! Relation) })
                        }
                        for observer in willChangeUpdateObservers {
                            observer.withWrapped({ $0.relationWillChange(observedRelation as! Relation) })
                        }
                    }
                }
            }
        })
    }
    
    fileprivate func sendWillChangeForAllPendingActions() {
        for action in pendingActions {
            switch action {
            case .add(let relation, _):
                sendWillChange(relation)
            case .delete(let relation, _):
                sendWillChange(relation)
            case .update(let relation, _, _):
                sendWillChange(relation)
            case .restoreSnapshot(let database, _):
                for (_, relation) in database.relations {
                    registerChange(relation)
                }
            case .query:
                break
            }
        }
    }
    
    fileprivate func scheduleExecutionIfNeeded() {
        if executionTimer == nil {
            executionTimer = CFRunLoopTimerCreateWithHandler(nil, 0, 0, 0, 0, { _ in
                self.execute()
            })
            CFRunLoopAddTimer(runloop, executionTimer, CFRunLoopMode.commonModes)
            state = .pending
        }
    }
    
    fileprivate func execute() {
        CFRunLoopTimerInvalidate(executionTimer)
        executionTimer = nil
        state = .running
        executeBody()
    }
    
    fileprivate func executeBody() {
        // Apply all pending updates asynchronously. Update work is done in the background, with callbacks onto
        // this runloop for synchronization and notifying observers.
        let updates = pendingActions
        pendingActions = []
        
        let observedInfo = self.observedInfo
        
        // Run updates in the background.
        DispatchQueue.global().async(execute: {
            // Walk through all the observers. Observe changes on all relevant variables and update
            // observer derivatives with those changes as they come in. Also locate all
            // TransactionalDatabases referenced within so we can begin and end transactions.
            var databases: ObjectSet<TransactionalDatabase> = []
            var removals: [(Void) -> Void] = []
            for (_, info) in observedInfo {
                let derivative = info.derivative
                derivative.clearVariables()
                for variable in derivative.allVariables {
                    let removal = variable.addChangeObserver({
                        let copiedAddResult = $0.added.map(ConcreteRelation.copyRelation)
                        let copiedRemoveResult = $0.removed.map(ConcreteRelation.copyRelation)
                        
                        if let err = copiedAddResult?.err ?? copiedRemoveResult?.err {
                            fatalError("Error copying changes, don't know how to handle that yet: \(err)")
                        }
                        
                        let copiedChange = RelationChange(added: copiedAddResult?.ok, removed: copiedRemoveResult?.ok)
                        derivative.addChange(copiedChange, toVariable: variable)
                    })
                    removals.append(removal)
                    
                    if let transactionalRelation = variable as? TransactionalRelation,
                           let db = transactionalRelation.db {
                        databases.insert(db)
                    }
                }
            }
            
            // Wrap everything up in a transaction.
            // TODO: this doesn't really work when there's more than one database, even though we sort of
            // pretend like it does. Fix that? Explicitly limit it to one database?
            for db in databases {
                db.beginTransaction()
            }
            
            // Apply the actual updates to the relations.
            for update in updates {
                let error: RelationError?
                switch update {
                case .update(let relation, let query, let newValues):
                    var mutableRelation = relation
                    let result = mutableRelation.update(query, newValues: newValues)
                    error = result.err
                case .add(let relation, let row):
                    let result = relation.add(row)
                    error = result.err
                case .delete(let relation, let query):
                    let result = relation.delete(query)
                    error = result.err
                case .restoreSnapshot(let database, let snapshot):
                    if databases.contains(database) {
                        // TODO: check for errors?
                        _ = database.endTransaction()
                        database.restoreSnapshot(snapshot)
                        database.beginTransaction()
                    } else {
                        database.restoreSnapshot(snapshot)
                    }
                    error = nil
                case .query:
                    error = nil
                }
                
                if let error = error {
                    fatalError("Don't know how to deal with update errors yet, got error \(error)")
                }
            }
            
            // And end the transaction.
            for db in databases {
                // TODO: check for errors?
                _ = db.endTransaction()
            }
            
            // All changes are done, so remove the observations registered above.
            for removal in removals {
                removal()
            }
            
            // Set up a QueryManager to run all the queries together.
            let queryManager = QueryManager()
            
            // We'll be doing a bunch of async work to notify observers. Use a dispatch group to figure out when it's all done.
            let doneGroup = DispatchGroup()
            
            // Go through all the observers and notify them.
            for (observedRelationObj, info) in observedInfo {
                let relation = observedRelationObj as! Relation
                let change = info.derivative.change
                
                let observersWithWillChange = info.observers.values.filter({ $0.didSendWillChange == true })
                let relationObservers = observersWithWillChange.flatMap({ $0.relationObserver })
                let updateObservers = observersWithWillChange.flatMap({ $0.updateObserver })
                
                if !relationObservers.isEmpty {
                    // If there are additions, then iterate over them and send them to the observer. Iteration is started in the
                    // original runloop, which ensures that the callbacks happen there too.
                    if let added = change.added {
                        doneGroup.enter()
                        queryManager.registerQuery(added, callback: DirectDispatchContext().wrap({ result in
                            switch result {
                            case .Ok(let rows) where rows.isEmpty:
                                doneGroup.leave()
                            case .Ok(let rows):
                                for observer in relationObservers {
                                    observer.withWrapped({ $0.relationAddedRows(relation, rows: rows) })
                                }
                            case .Err(let err):
                                for observer in relationObservers {
                                    observer.withWrapped({ $0.relationError(relation, error: err) })
                                }
                                doneGroup.leave()
                            }
                        }))
                    }
                    // Do the same if there are removals.
                    if let removed = change.removed {
                        doneGroup.enter()
                        queryManager.registerQuery(removed, callback: DirectDispatchContext().wrap({ result in
                            switch result {
                            case .Ok(let rows) where rows.isEmpty:
                                doneGroup.leave()
                            case .Ok(let rows):
                                for observer in relationObservers {
                                    observer.withWrapped({ $0.relationRemovedRows(relation, rows: rows) })
                                }
                            case .Err(let err):
                                for observer in relationObservers {
                                    observer.withWrapped({ $0.relationError(relation, error: err) })
                                }
                                doneGroup.leave()
                            }
                        }))
                    }
                }
                
                if !updateObservers.isEmpty {
                    doneGroup.enter()
                    queryManager.registerQuery(relation, callback: DirectDispatchContext().wrap({ result in
                        switch result {
                        case .Ok(let rows) where rows.isEmpty:
                            doneGroup.leave()
                        case .Ok(let rows):
                            for observer in updateObservers {
                                observer.withWrapped({ $0.relationNewContents(relation, rows: rows) })
                            }
                        case .Err(let err):
                            for observer in updateObservers {
                                observer.withWrapped({ $0.relationError(relation, error: err) })
                            }
                            doneGroup.leave()
                        }
                    }))
                }
            }
            
            // Make any requested queries.
            for update in updates {
                if case .query(let relation, let callback) = update {
                    doneGroup.enter()
                    queryManager.registerQuery(relation, callback: DirectDispatchContext().wrap({ result in
                        callback.withWrapped({
                            $0(result)
                            switch result {
                            case .Ok(let rows) where rows.isEmpty:
                                doneGroup.leave()
                            case .Err:
                                doneGroup.leave()
                            default:
                                break
                            }
                        })
                    }))
                }
            }
            
            queryManager.execute()
            
            // Wait until done. If there are no changes then this will execute immediately. Otherwise it will execute
            // when all the iteration above is complete.
            doneGroup.notify(queue: DispatchQueue.global(), execute: {
                self.runloop.async({
                    // If new pending updates came in while we were doing our thing, then go back to the top
                    // and start over, applying those updates too.
                    if !self.pendingActions.isEmpty {
                        // All content observers currently being worked on need a didChange followed by a willChange
                        // so that they know they're getting new content, not additional content.
                        for (observedRelationObj, info) in observedInfo {
                            for (_, observer) in info.observers {
                                if observer.didSendWillChange {
                                    observer.updateObserver?.withWrapped({
                                        $0.relationDidChange(observedRelationObj as! Relation)
                                        $0.relationWillChange(observedRelationObj as! Relation)
                                    })
                                }
                            }
                        }
                        self.sendWillChangeForAllPendingActions()
                        self.executeBody()
                    } else {
                        // Otherwise, terminate the execution. Reset observers and send didChange to them.
                        for (observedRelationObj, info) in observedInfo {
                            info.derivative.clearVariables()
                            
                            let relation = observedRelationObj as! Relation
                            var entriesWithWillChange: [ObservedRelationInfo.ObserverEntry] = []
                            info.observers.mutatingForEach({
                                if $0.didSendWillChange {
                                    $0.didSendWillChange = false
                                    entriesWithWillChange.append($0)
                                }
                            })
                            for entry in entriesWithWillChange {
                                entry.relationObserver?.withWrapped({ $0.relationDidChange(relation) })
                                entry.updateObserver?.withWrapped({ $0.relationDidChange(relation) })
                            }
                        }
                        self.state = .idle
                    }
                })
            })
        })
    }
    
    func defaultObserverDispatchContext() -> DispatchContext {
        return RunLoopDispatchContext(runloop: self.runloop, executeReentrantImmediately: true)
    }
}

extension UpdateManager {
    fileprivate enum Action {
        case update(Relation, SelectExpression, Row)
        case add(MutableRelation, Row)
        case delete(MutableRelation, SelectExpression)
        case restoreSnapshot(TransactionalDatabase, ChangeLoggingDatabaseSnapshot)
        case query(Relation, DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>)
    }
    
    fileprivate class ObservedRelationInfo {
        struct ObserverEntry {
            var relationObserver: DispatchContextWrapped<AsyncRelationChangeObserver>?
            var updateObserver: DispatchContextWrapped<AsyncRelationContentObserver>?
            var didSendWillChange: Bool
        }
        
        let derivative: RelationDerivative
        var observers: [UInt64: ObserverEntry] = [:]
        var currentObserverID: UInt64 = 0
        
        init(derivative: RelationDerivative) {
            self.derivative = derivative
        }
        
        func addObserver(_ observer: AsyncRelationChangeObserver, context: DispatchContext) -> UInt64 {
            currentObserverID += 1
            observers[currentObserverID] = ObserverEntry(relationObserver: DispatchContextWrapped(context: context, wrapped: observer), updateObserver: nil, didSendWillChange: false)
            return currentObserverID
        }
        
        func addObserver(_ observer: AsyncRelationContentObserver, context: DispatchContext) -> UInt64 {
            currentObserverID += 1
            observers[currentObserverID] = ObserverEntry(relationObserver: nil, updateObserver: DispatchContextWrapped(context: context, wrapped: observer), didSendWillChange: false)
            return currentObserverID
        }
    }
}

public extension MutableRelation {
    func asyncAdd(_ row: Row) {
        UpdateManager.currentInstance.registerAdd(self, row: row)
    }
    
    func asyncDelete(_ query: SelectExpression) {
        UpdateManager.currentInstance.registerDelete(self, query: query)
    }
}