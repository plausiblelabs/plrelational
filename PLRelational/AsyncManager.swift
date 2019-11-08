//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

/// TODO: Docs
public typealias InitiatorTag = String

/// TODO: Docs
public typealias InitiatorTagSet = Set<InitiatorTag?>

/// :nodoc: Implementation detail (will be made non-public eventually)
/// A class which manages asynchronous operations on `Relation`s. `Relation` provides
/// primitive synchronous operations such as queries, updates, and deletions. `AsyncManager`
/// then wraps those operations up and executes them in the background.
///
/// Normally you do not deal with this class directly, but use the various `async` methods
/// available on `Relation` and similar. Those are wrappers around this class in more
/// convenient form.
///
/// This class is tied to the thread where it is created, which must run a runloop. There
/// is a common instance available by calling `currentInstance`. It is possible to create
/// your own instance separate from this, but there is usually no reason to do so.
///
/// `Relation`s used for async operations must not also be used for synchronous operations
/// at the same time.
public final class AsyncManager: PerThreadInstance {
    public typealias ObservationRemover = () -> Void
    
    fileprivate var pendingActions: [Action] = []
    fileprivate var observedInfo: ObjectDictionary<AnyObject, ObservedRelationInfo> = [:]
    fileprivate var variableInfo: ObjectDictionary<AnyObject, [VariableEntry]> = [:]
    
    private let runloop: CFRunLoop
    
    /// The runloop modes this manager is currently scheduled in. By default, `AsyncManager`
    /// is scheduled in the common runloop modes.
    public private(set) var runloopModes: [CFRunLoopMode] = [.commonModes]
    
    private var executionTimer: CFRunLoopTimer?
    
    /// Initialize an `AsyncManager`. The resulting instance is tied to the thread it's
    /// created on.
    public init() {
        self.runloop = CFRunLoopGetCurrent()
    }
    
    /// A type describing the current state of an `AsyncManager.`
    public enum State {
        /// Nothing is happening, no actions have been registered.
        case idle
        
        /// Actions have been registered but are not yet running.
        case pending
        
        /// Actions are actively running.
        case running
        
        /// Actions have been run and didChange observers are being notified before returning back to idle.
        case stopping
    }
    
    private var stateObservers: [UInt64: (State) -> Void] = [:]
    private var stateObserversNextID: UInt64 = 0
    
    /// The current state of this instance.
    public var state: State = .idle {
        didSet {
            for (_, observer) in stateObservers {
                observer(state)
            }
        }
    }
    
    /// Add a runloop mode where this AsyncManager will run its non-async code.
    /// By default, it runs on the common runloop modes.
    public func addRunloopMode(_ mode: CFRunLoopMode) {
        runloopModes.append(mode)
    }
    
    /// Set the runloop modes where this AsyncManager will run its non-async code.
    /// This wipes out any existing modes and so should be used with care.
    /// (Probably just in tests.)
    public func setRunloopModes(_ modes: [CFRunLoopMode]) -> [CFRunLoopMode] {
        let old = runloopModes
        runloopModes = modes
        return old
    }
    
    /// Add an observer which is called whenever `state` changes.
    ///
    /// - parameter observer: The observer function to call, which is passed in the new state.
    /// - returns: A remover function. Call this to remove the observer.
    public func addStateObserver(_ observer: @escaping (State) -> Void) -> ObservationRemover {
        let id = stateObserversNextID
        stateObserversNextID += 1
        
        stateObservers[id] = observer
        return { self.stateObservers.removeValue(forKey: id) }
    }
    
    /// Register an update operation with the manager.
    public func registerUpdate(_ relation: Relation, query: SelectExpression, newValues: Row, initiator: InitiatorTag?) {
        register(action: .update(relation, query, newValues, initiator))
    }
    
    /// Register an add operation with the manager.
    public func registerAdd(_ relation: MutableRelation, row: Row, initiator: InitiatorTag?) {
        register(action: .add(relation, row, initiator))
    }
    
    /// Register a delete operation with the manager.
    public func registerDelete(_ relation: MutableRelation, query: SelectExpression, initiator: InitiatorTag?) {
        register(action: .delete(relation, query, initiator))
    }
    
    /// Register a restore snapshot operation with the manager.
    public func registerRestoreSnapshot(_ database: TransactionalDatabase, snapshot: TransactionalDatabaseSnapshot) {
        register(action: .restoreSnapshot(database, snapshot))
    }
    
    /// Register a apply delta operation with the manager.
    public func registerApplyDelta(_ database: TransactionalDatabase, delta: TransactionalDatabaseDelta) {
        register(action: .applyDelta(database, delta))
    }
    
    /// Register a query operation with the manager.
    public func registerQuery(_ relation: Relation, callback: DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>) {
        register(action: .query(relation, callback))
    }
    
    /// Register a function to be called as part of the sequence of performing enqueued async actions.
    /// This allows the sequence of execution to be monitored for e.g. computing deltas for operations.
    public func registerCheckpoint(_ checkpoint: @escaping () -> Void, initiator: InitiatorTag? = nil) {
        registerCustomAction(affectedRelations: [], { checkpoint(); return nil }, initiator: initiator)
    }
    
    /// Register a custom action. This allows asyncifying more complex operations than just update/add/delete/whatever.
    /// In order for notifications to work, any relations that might be affected in the custom action must be passed in
    /// to `affectedRelations`. It's acceptable to pass in a relation that ends up not being affected. This will generate
    /// a spurious but harmless empty change notification.
    public func registerCustomAction(affectedRelations: [MutableRelation], _ action: @escaping () -> RelationError?, initiator: InitiatorTag?) {
        register(action: .customAction(action: action, affectedRelations: affectedRelations, initiator: initiator))
    }
    
    private func register(action: Action, atBeginning: Bool = false) {
        if atBeginning {
            pendingActions.insert(action, at: 0)
        } else {
            pendingActions.append(action)
        }
        
        switch action {
        case .add(let relation, let row, let initiator):
            registerChange(relation, predicate: SelectExpressionFromRow(row), newValues: row, initiator: initiator)
        case .delete(let relation, let query, let initiator):
            registerChange(relation, predicate: query, newValues: nil, initiator: initiator)
        case .update(let relation, let query, let newValues, let initiator):
            registerChange(relation, predicate: query, newValues: newValues, initiator: initiator)
        case .restoreSnapshot(let database, _), .applyDelta(let database, _):
            for (_, relation) in database.relations {
                registerChange(relation, predicate: true, newValues: nil, initiator: nil /* TODO(initiator) */)
            }
        case .query:
            break
        case .customAction(_, let affectedRelations, let initiator):
            for relation in affectedRelations {
                registerChange(relation, predicate: true, newValues: nil, initiator: initiator)
            }
        }
        
        if state == .idle {
            scheduleExecutionIfNeeded()
        }
    }
    
    /// Register an observer for a Relation. The observer will receive all changes made to the relation
    /// through the AsyncManager.
    public func observe(_ relation: Relation, observer: AsyncRelationChangeObserver, context: DispatchContext? = nil) -> ObservationRemover {
        guard let obj = asObject(relation) else { return {} }
        
        let info = infoForObservee(obj)
        let id = info.addObserver(observer, context: context ?? runloopDispatchContext())
        
        return {
            info.observers[id] = nil
            if info.observers.isEmpty {
                self.observedInfo[obj] = nil
            }
        }
    }
    
    /// Register an observer for a Relation. When the Relation is changed through the AsyncManager,
    /// the observer receives the Relation's new contents.
    public func observe(_ relation: Relation, observer: AsyncRelationContentObserver, context: DispatchContext? = nil) -> ObservationRemover {
        guard let obj = asObject(relation) else { return {} }
        
        let info = infoForObservee(obj)
        let id = info.addObserver(observer, context: context ?? runloopDispatchContext())
        
        return {
            info.observers[id] = nil
            if info.observers.isEmpty {
                self.observedInfo[obj] = nil
            }
        }
    }
    
    fileprivate func registerChange(_ relation: Relation, predicate: SelectExpression, newValues: Row?, initiator: String?) {
        if state != .running {
            sendWillChange(relation, predicate: predicate, newValues: newValues, initiator: initiator)
            scheduleExecutionIfNeeded()
        }
    }
    
    fileprivate func sendWillChange(_ relation: Relation, predicate: SelectExpression, newValues: Row?, initiator: String?) {
        for (variable, predicate) in getUpdatePredicates(forRelation: relation, predicate: predicate, newValues: newValues) {
            if variable is IntermediateRelation { continue }
            
            if let entries = variableInfo[variable] {
                for entry in entries {
                    if let filter = entry.filter, let predicate = predicate, canProveInconsistent(predicate, filter) {
                        continue
                    }

                    // Add the initator to the set; note that we allow `nil` tags in the set,
                    // which can be used to indicate that the initiator is unnamed/unknown
                    entry.observedRelationInfo.initiators.insert(initiator)
                    
                    // Send willChange for any observers that haven't been sent one yet
                    var willChangeRelationObservers: [DispatchContextWrapped<AsyncRelationChangeObserver>] = []
                    var willChangeUpdateObservers: [DispatchContextWrapped<AsyncRelationContentObserver>] = []
                    entry.observedRelationInfo.observers.mutatingForEach({
                        if !$0.didSendWillChange {
                            $0.didSendWillChange = true
                            willChangeRelationObservers.appendNonNil($0.relationObserver)
                            willChangeUpdateObservers.appendNonNil($0.updateObserver)
                        }
                    })
                    for observer in willChangeRelationObservers {
                        observer.withWrapped({ $0.relationWillChange(entry.observedRelation) })
                    }
                    for observer in willChangeUpdateObservers {
                        observer.withWrapped({ $0.relationWillChange(entry.observedRelation) })
                    }
                }
            }
        }
    }
    
    fileprivate func sendWillChangeForAllPendingActions() {
        for action in pendingActions {
            switch action {
            case .add(let relation, let row, let initiator):
                sendWillChange(relation, predicate: SelectExpressionFromRow(row), newValues: row, initiator: initiator)
            case .delete(let relation, let query, let initiator):
                sendWillChange(relation, predicate: query, newValues: nil, initiator: initiator)
            case .update(let relation, let query, let newValues, let initiator):
                sendWillChange(relation, predicate: query, newValues: newValues, initiator: initiator)
            case .restoreSnapshot(let database, _), .applyDelta(let database, _):
                for (_, relation) in database.relations {
                    sendWillChange(relation, predicate: true, newValues: nil, initiator: nil /* TODO(initiator) */)
                }
            case .query:
                break
            case .customAction(_, let affectedRelations, let initiator):
                for relation in affectedRelations {
                    sendWillChange(relation, predicate: true, newValues: nil, initiator: initiator)
                }
            }
        }
    }
    
    fileprivate func scheduleExecutionIfNeeded() {
        if executionTimer == nil {
            executionTimer = CFRunLoopTimerCreateWithHandler(nil, 0, 0, 0, 0, { _ in
                self.execute()
            })
            for mode in runloopModes {
                CFRunLoopAddTimer(runloop, executionTimer, mode)
            }
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
        // Apply all pending actions asynchronously. Work is done in the background, with callbacks onto
        // this runloop for synchronization and notifying observers.
        let actions = pendingActions
        pendingActions = []
        
        let observedInfo = self.observedInfo
        
        // Run actions in the background.
        DispatchQueue.global().async(execute: {
            // Walk through all the observers. Observe changes on all relevant variables and update
            // observer derivatives with those changes as they come in. Also locate all
            // TransactionalDatabases referenced within so we can begin and end transactions.
            var databases: ObjectSet<TransactionalDatabase> = []
            var removals: [() -> Void] = []
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
            
            self.getDatabases(forActions: actions, into: &databases)
            
            // Wrap everything up in a transaction.
            // TODO: this doesn't really work when there's more than one database, even though we sort of
            // pretend like it does. Fix that? Explicitly limit it to one database?
            for db in databases {
                db.beginTransaction()
            }
            
            // Apply the actual updates to the relations. Ignore queries.
            for action in actions {
                let error: RelationError?
                switch action {
                case .update(let relation, let query, let newValues, _):
                    var mutableRelation = relation
                    let result = mutableRelation.update(query, newValues: newValues)
                    error = result.err
                case .add(let relation, let row, _):
                    let result = relation.add(row)
                    error = result.err
                case .delete(let relation, let query, _):
                    let result = relation.delete(query)
                    error = result.err
                case .restoreSnapshot(let database, let snapshot):
                    if databases.contains(database) {
                        // TODO: check for errors?
                        _ = database.endTransaction()
                        _ = database.restoreSnapshot(snapshot)
                        database.beginTransaction()
                    } else {
                        _ = database.restoreSnapshot(snapshot)
                    }
                    error = nil
                case .applyDelta(let database, let delta):
                    // Do we need transaction games?
                    error = database.apply(delta: delta).err
                case .query:
                    error = nil
                case .customAction(let call, _, _):
                    error = call()
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
            var queryManager = QueryManager()
            
            // We'll be doing a bunch of async work to notify observers. Use a dispatch group to figure out when it's all done.
            let doneGroup = DispatchGroup()
            
            // Go through all the observers and notify them.
            for (observedRelationObj, info) in observedInfo {
                let relation = observedRelationObj as! Relation
                let change = info.derivative.change
                
                let observersWithWillChange = info.observers.values.filter({ $0.didSendWillChange == true })
                let relationObservers = observersWithWillChange.compactMap({ $0.relationObserver })
                let updateObservers = observersWithWillChange.compactMap({ $0.updateObserver })
                
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
            for action in actions {
                if case .query(let relation, let callback) = action {
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
                self.runloop.async(inModes: self.runloopModes, {
                    // If new pending actions came in while we were doing our thing, then go back to the top
                    // and start over, performing those actions too.
                    if !self.pendingActions.isEmpty {
                        // All content observers currently being worked on need a didChange followed by a willChange
                        // so that they know they're getting new content, not additional content.
                        for (observedRelationObj, info) in observedInfo {
                            // TODO: Hmm, we don't seem to have a good way to clear out the original initiator
                            // tags while retaining new tags for those pending actions that came in; for now
                            // I guess we will leave all tags in place and clear them out at the end
                            for (_, observer) in info.observers {
                                if observer.didSendWillChange {
                                    observer.updateObserver?.withWrapped({
                                        $0.relationDidChange(observedRelationObj as! Relation, initiators: info.initiators)
                                        $0.relationWillChange(observedRelationObj as! Relation)
                                    })
                                }
                            }
                        }
                        self.sendWillChangeForAllPendingActions()
                        self.executeBody()
                    } else {
                        // Otherwise, terminate the execution.
                        self.state = .stopping
                        
                        // Reset observers and send didChange to them.
                        var entriesWithWillChange: [(Relation, ObservedRelationInfo.ObserverEntry, InitiatorTagSet)] = []
                        for (observedRelationObj, info) in observedInfo {
                            let initiators = info.initiators
                            info.initiators.removeAll()
                            info.derivative.clearVariables()
                            
                            let relation = observedRelationObj as! Relation
                            info.observers.mutatingForEach({
                                if $0.didSendWillChange {
                                    $0.didSendWillChange = false
                                    entriesWithWillChange.append((relation, $0, initiators))
                                }
                            })
                        }
                        
                        for (relation, entry, initiators) in entriesWithWillChange {
                            entry.relationObserver?.withWrapped({ $0.relationDidChange(relation) })
                            entry.updateObserver?.withWrapped({ $0.relationDidChange(relation, initiators: initiators) })
                        }

                        // Suck out any pending actions that were queued up by didChange calls so we
                        // can add them back in after changing state.
                        let pendingActions = self.pendingActions
                        self.pendingActions.removeAll()
                        
                        self.state = .idle
                        
                        for action in pendingActions {
                            self.register(action: action, atBeginning: true)
                        }
                    }
                })
            })
        })
    }
    
    /// Pull out all the databases that need locking for our current actions.
    fileprivate func getDatabases(forActions: [Action], into databases: inout ObjectSet<TransactionalDatabase>) {
        let relations = forActions.compactMap({ action -> Relation? in
            switch action {
            case .update(let r, _, _, _):
                return r
            case .add(let r, _, _), .delete(let r, _, _):
                return r
            default:
                return nil
            }
        })
        QueryPlanner.visitRelationTree(relations, { relation, underlyingRelation in
            if let r = relation as? TransactionalRelation, let db = r.db {
                databases.insert(db)
            }
        })
    }

    /// Return a dispatch context that uses the AsyncManager's runloop and runloop modes.
    public func runloopDispatchContext() -> DispatchContext {
        return RunLoopDispatchContext(runloop: self.runloop,
                                      executeReentrantImmediately: true,
                                      modes: self.runloopModes)
    }
}

extension AsyncManager {
    fileprivate struct QueryManager {
        var pendingQueries: [(Relation, DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>)] = []
        
        mutating func registerQuery(_ relation: Relation, callback: DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>) {
            pendingQueries.append((relation, callback))
        }
        
        mutating func execute() {
            let planner = QueryPlanner(roots: pendingQueries)
            let runner = QueryRunner(planner: planner)
            
            while !runner.done {
                runner.pump()
            }
            
            if !runner.didError {
                for (_, callback) in pendingQueries {
                    callback.withWrapped({ $0(.Ok([])) })
                }
            }
        }
    }
}

extension AsyncManager {
    fileprivate enum Action {
        case update(Relation, SelectExpression, Row, InitiatorTag?)
        case add(MutableRelation, Row, InitiatorTag?)
        case delete(MutableRelation, SelectExpression, InitiatorTag?)
        case restoreSnapshot(TransactionalDatabase, TransactionalDatabaseSnapshot)
        case applyDelta(TransactionalDatabase, TransactionalDatabaseDelta)
        case query(Relation, DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>)
        case customAction(action: () -> RelationError?, affectedRelations: [MutableRelation], initiator: InitiatorTag?)
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
        var initiators: InitiatorTagSet = []
        
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
    
    fileprivate func infoForObservee(_ relationObject: AnyObject) -> ObservedRelationInfo {
        return observedInfo.getOrCreate(relationObject, defaultValue: makeInfoForObservee(relationObject as! Relation & AnyObject))
    }
    
    fileprivate func makeInfoForObservee(_ relation: Relation & AnyObject) -> ObservedRelationInfo {
        let derivative = RelationDifferentiator(relation: relation).computeDerivative()
        let info = ObservedRelationInfo(derivative: derivative)
        let filters = relationFilters(relation)
        for (variable, filter) in filters {
            let entry = VariableEntry(observedRelation: relation, observedRelationInfo: info, filter: filter)
            variableInfo[variable, defaultValue: []].append(entry)
        }
        
        let filtered = ObjectSet<AnyObject>(filters.map({ $0.0 }))
        for variable in derivative.allVariables where !filtered.contains(variable) {
            let entry = VariableEntry(observedRelation: relation, observedRelationInfo: info, filter: nil)
            variableInfo[variable, defaultValue: []].append(entry)
        }
        return info
    }
    
    fileprivate func relationFilters(_ relation: Relation & AnyObject) -> [(RelationDerivative.Variable, SelectExpression)] {
        guard let relation = relation as? IntermediateRelation else { return [] }
        
        var pending: ObjectSet<IntermediateRelation> = [relation]
        var result: ObjectDictionary<AnyObject, SelectExpression?> = [:]
        
        while !pending.isEmpty {
            let r = pending.removeFirst()
            for child in r.operands {
                switch child {
                case let child as IntermediateRelation:
                    pending.insert(child)
                case let child as RelationDerivative.Variable:
                    if case .select(let expression) = r.op {
                        if case .none = result[child] {
                            result[child] = expression
                        } else {
                            result[child] = nil
                        }
                    } else {
                        result[child] = nil
                    }
                default:
                    break
                }
            }
        }
        
        return result.filter({ $1 != nil }).map({ ($0 as! RelationDerivative.Variable, $1!) })
    }
}

extension AsyncManager {
    fileprivate struct VariableEntry {
        // TODO: weak reference?
        var observedRelation: Relation
        var observedRelationInfo: ObservedRelationInfo
        var filter: SelectExpression?
    }
    
    /// Try to (cheaply) see if a and b are inconsistent, i.e. can never both be true simultaneously.
    /// The function returns true if so. If it returns false, they may still be inconsistent, it
    /// just couldn't prove that. Right now the check is extremely basic.
    fileprivate func canProveInconsistent(_ a: SelectExpression, _ b: SelectExpression) -> Bool {
        // If one of the expressions is an AND, then inconsistency with either operand
        // results in inconsistency of the whole.
        if let (lhs, rhs) = a.binaryOperands(AndComparator.self) {
            return canProveInconsistent(lhs, b) || canProveInconsistent(rhs, b)
        }
        if let (lhs, rhs) = b.binaryOperands(AndComparator.self) {
            return canProveInconsistent(a, lhs) || canProveInconsistent(a, rhs)
        }
        
        // If one of the expressions is an OR, then inconsistency with BOTH operands
        // results in inconsistency of the whole.
        if let (lhs, rhs) = a.binaryOperands(OrComparator.self) {
            return canProveInconsistent(lhs, b) && canProveInconsistent(rhs, b)
        }
        if let (lhs, rhs) = b.binaryOperands(OrComparator.self) {
            return canProveInconsistent(a, lhs) && canProveInconsistent(a, rhs)
        }
        
        // If they both require equality between an attribute and a value, and it's the
        // same attribute and a different value, then they're inconsistent.
        if let (attributeA, valueA) = equalityAttributeAndValue(a),
            let (attributeB, valueB) = equalityAttributeAndValue(b),
            attributeA == attributeB && valueA.relationValue != valueB.relationValue
        {
            return true
        }
        
        // We tested all we could, and we couldn't prove it inconsistent.
        return false
    }
    
    private func equalityAttributeAndValue(_ expression: SelectExpression) -> (Attribute, SelectExpressionConstantValue)? {
        switch expression.binaryOperands(EqualityComparator.self) {
        case let .some(attr as Attribute, value as SelectExpressionConstantValue):
            return (attr, value)
        case let .some(value as SelectExpressionConstantValue, attr as Attribute):
            return (attr, value)
        default:
            return nil
        }
        
    }
}

extension AsyncManager {
    /// Chase down all relation children that need notifications sent for an update.
    /// The return value is an array of variable/predicate pairs. The predicate indicates
    /// how the variable may be filtered, and if no filter is computed, it will be nil.
    fileprivate func getUpdatePredicates(forRelation relation: Relation, predicate: SelectExpression, newValues: Row?) -> [(RelationDerivative.Variable, SelectExpression?)] {
        let initial = linearGetUpdatePredicates(forRelation: relation, predicate: predicate, newValues: newValues)
        
        let followingStart = initial.last!.0
        var remaining = getAllChildren(ofRelation: followingStart)
        remaining.remove(followingStart)
        
        return initial.map({ ($0, $1) }) + remaining.map({ ($0 as! RelationDerivative.Variable, nil) })
    }
    
    /// Chase down Relation children we can compute predicates for. Right now, this has to follow
    /// a single path down the tree (thus "linear") and can only work through a few Relation
    /// types. It will iterate through unions with a single child, projects, selects, renames,
    /// and it will work through equijoins when the change applies only to one side of the
    /// join, and the other side is a CachingRelation with a cache set.
    private func linearGetUpdatePredicates(forRelation relation: Relation, predicate: SelectExpression, newValues: Row?) -> [(RelationDerivative.Variable, SelectExpression)] {
        var currentRelation = asObject(relation)
        var currentPredicate = predicate
        var currentValues = newValues
        
        var result: [(RelationDerivative.Variable, SelectExpression)] = []
        
        loop: while let currentRelationNonNil = currentRelation {
            result.append((currentRelationNonNil as! RelationDerivative.Variable, currentPredicate))
            
            if let intermediate = currentRelationNonNil as? IntermediateRelation {
                switch intermediate.op {
                case .union where intermediate.operands.count == 1:
                    currentRelation = asObject(intermediate.operands[0])
                    continue
                case .project:
                    currentRelation = asObject(intermediate.operands[0])
                case .select(let expression):
                    currentRelation = asObject(intermediate.operands[0])
                    currentPredicate = currentPredicate *&& expression
                case .rename(let mapping):
                    currentRelation = asObject(intermediate.operands[0])
                    currentPredicate = currentPredicate.withRenamedAttributes(mapping.inverted)
                    currentValues = currentValues?.renameAttributes(mapping.inverted)
                case .equijoin(let matching):
                    if let result = evaluateEquijoin(lhs: intermediate.operands[0], rhs: intermediate.operands[1], matching: matching, predicate: currentPredicate, newValues: currentValues) {
                        currentRelation = result.0
                        currentPredicate = result.1
                    } else {
                        break loop
                    }
                default:
                    break loop
                }
            } else {
                break loop
            }
        }
        
        return result
    }
    
    /// Return all object children of the given relation, including the given relation.
    private func getAllChildren(ofRelation relation: Relation) -> ObjectSet<AnyObject> {
        guard let relationObj = asObject(relation) else { return [] }
        
        var visited: ObjectSet<AnyObject> = []
        var toVisit: ObjectSet<AnyObject> = [relationObj]
        
        while !toVisit.isEmpty {
            let r = toVisit.removeFirst()
            visited.insert(r)
            
            if let r = r as? IntermediateRelation {
                for child in r.operands {
                    if let obj = asObject(child), !visited.contains(obj) {
                        toVisit.insert(obj)
                    }
                }
            }
        }
        
        return visited
    }
    
    /// Check whether a predicate can be efficiently computed through an equijoin. If the predicate
    /// and new values apply to one side of the join, and if the other side of the join is a 
    /// CachingRelation with the cache set, this will return the other child and return a predicate
    /// derived from the predicate passed in and from the other side of the join.
    private func evaluateEquijoin(lhs: Relation, rhs: Relation, matching: [Attribute: Attribute], predicate: SelectExpression, newValues: Row?) -> (RelationDerivative.Variable?, SelectExpression)? {
        guard let newValues = newValues else { return nil }
        
        let predicateAttributes = predicate.allAttributes()
        let newValuesAttributes = Set(newValues.attributes)
        
        let toCheck = [(matching, lhs, rhs),
                       (matching.inverted, rhs, lhs)]
        
        for (matching, simpleCandidate, other) in toCheck {
            if let simpleRows = efficientRows(fromRelation: simpleCandidate) {
                if predicateAttributes.isSubset(of: other.scheme.attributes) && newValuesAttributes.isSubset(of: other.scheme.attributes) {
                    let cachePredicate = simpleRows.map(SelectExpressionFromRow).combined(with: *||)
                    let mappedPredicate = cachePredicate?.withRenamedAttributes(matching)
                    let combinedPredicate = mappedPredicate.map({ $0 *&& predicate }) ?? predicate
                    return (other as? RelationDerivative.Variable, combinedPredicate)
                }
            }
        }
        
        return nil
    }
    
    /// Try to efficiently get the rows of a Relation, and return nil if it can't be done.
    /// Currently checks to see if it's a MemoryTableRelation and returns the values if so,
    /// or returns the cache from a CachingRelation if it's that.
    private func efficientRows(fromRelation: Relation) -> Set<Row>? {
        switch fromRelation {
        case let r as MemoryTableRelation where !hasPendingChanges(forRelation: r):
            return r.values.allValues
        case let r as CachingRelation:
            return r.cache
        default:
            return nil
        }
    }
    
    /// Check whether the given relation (but not its children!) has any pending changes
    /// in `pendingActions`.
    private func hasPendingChanges(forRelation: Relation) -> Bool {
        guard let obj = asObject(forRelation) else { return false }
        
        for change in pendingActions {
            switch change {
            case .update(let r, _, _, _): if obj === asObject(r) { return true }
            case .add(let r, _, _): if obj === r { return true }
            case .delete(let r, _, _): if obj === r { return true }
                
            default: break
            }
        }
        
        return false
    }
}

public extension MutableRelation {
    func asyncAdd(_ row: Row, initiator: InitiatorTag? = nil) {
        AsyncManager.currentInstance.registerAdd(self, row: row, initiator: initiator)
    }
    
    func asyncDelete(_ query: SelectExpression, initiator: InitiatorTag? = nil) {
        AsyncManager.currentInstance.registerDelete(self, query: query, initiator: initiator)
    }
}
