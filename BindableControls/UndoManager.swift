//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

open class UndoManager {
    
    private let nsmanager: SPUndoManager
    
    public init() {
        self.nsmanager = SPUndoManager()
    }
    
    public init(nsmanager: SPUndoManager) {
        self.nsmanager = nsmanager
    }
    
    open func registerChange(name: String, perform: Bool, forward: @escaping () -> Void, backward: @escaping () -> Void) {
        // First register the change
        let f = nsmanager.registerChange(name, forwards: forward, backwards: backward)
        
        if perform {
            // Then invoke the `forward` function if requested
            f()
        }
    }
    
    open func undo() {
        nsmanager.undo()
    }
    
    open func redo() {
        nsmanager.redo()
    }
}

// The following is pulled from:
//   https://github.com/andrewshand/SPUndoManager

extension Array {
    func atIndex(_ index: Int) -> Element? {
        if index >= 0 && index < count {
            return self[index]
        }
        return nil
    }
    
    func each(_ function: (_ element: Element) -> Void) {
        for e in self {
            function(e)
        }
    }
    
    func eachForwards(_ function: (_ element: Element) -> Void) {
        for i in 0 ..< self.count {
            function(self[i])
        }
    }
    
    func eachBackwards(_ function: (_ element: Element) -> Void) {
        for i in (0..<self.count).reversed() {
            function(self[i])
        }
    }
}

public func undoableFrom<T>(_ undoable: (T, Undoable)) -> Undoable {
    return undoable.1
}

/// Only use when you're sure the action should definitely be undoable, possibly
/// good way of testing things
public func undoableForceFrom<T>(_ undoable: (T, Undoable?)) -> Undoable {
    return undoable.1!
}

public func ignoreUndo<T>(_ undoable: (T, Undoable)) -> T {
    return undoable.0
}

//public func registerUndo<T>(undoable: (T, Undoable)) -> T {
//
//    SPUndoManagerGet()?.registerChange(undoable.1)
//    return undoable.0
//}
//
//public func registerUndo<T>(undoable: (T, Undoable?)) -> T {
//
//    if let undoable = undoable.1 {
//        SPUndoManagerGet()?.registerChange(undoable)
//    }
//    return undoable.0
//}
//
//public func beginUndoGrouping(description: String) {
//    SPUndoManagerGet()?.beginUndoGrouping(description)
//}
//
//public func endUndoGrouping() {
//    SPUndoManagerGet()?.endUndoGrouping()
//}
//
//public func cancelUndoGrouping() {
//    SPUndoManagerGet()?.cancelUndoGrouping()
//}
//
//public func groupUndoActions(description: String, closure: () -> ()) {
//    beginUndoGrouping(description)
//    closure()
//    endUndoGrouping()
//}
//
//public func groupUndoActions(description: String, closure: () -> Bool) {
//    beginUndoGrouping(description)
//
//    if (closure()) {
//        endUndoGrouping()
//    }
//    else {
//        cancelUndoGrouping()
//    }
//}

protocol SPUndoManagerAction {
    
    var done: Bool { get }
    func undo()
    func redo()
    var description: String { get }
}

class SPUndoManagerStandardAction : SPUndoManagerAction {
    
    /// Assumes action already performed
    init(description: String, forwards: @escaping Closure, backwards: @escaping Closure) {
        
        self.forwards = forwards
        self.backwards = backwards
        self.description = description
        self.done = true
    }
    
    var done: Bool
    var backwards: Closure
    var forwards: Closure
    var description: String
    
    func undo() {
        assert(done)
        backwards()
        done = false
    }
    
    func redo() {
        assert(!done)
        forwards()
        done = true
    }
}


class SPUndoManagerSuperDynamicAction : SPUndoManagerAction {
    
    var undoable: Undoable
    var description: String
    
    /// Assumes action performed, in 'done' state by default
    init(undoable: Undoable) {
        self.undoable = undoable
        self.description = undoable.description
        self.done = true
    }
    
    var done: Bool
    func undo() {
        assert(done)
        self.undoable = undoable.undo()
        done = false
    }
    func redo() {
        assert(!done)
        self.undoable = undoable.undo()
        done = true
    }
}

class SPUndoManagerGroupAction : SPUndoManagerAction {
    
    init(description: String) {
        self.description = description
    }
    
    var done: Bool = false
    var nestedActions = [SPUndoManagerAction]()
    
    func undo() {
        assert(done)
        self.nestedActions.eachBackwards { $0.undo() }
        done = false
    }
    
    func redo() {
        assert(!done)
        self.nestedActions.eachForwards { $0.redo() }
        done = true
    }
    
    var description: String
}

public typealias Closure = () -> Void

open class SPUndoManager : Foundation.UndoManager {
    
    public override init() {
        super.init()
    }
    
    var changes: [SPUndoManagerAction] = []
    var pendingGroups: [SPUndoManagerGroupAction] = []
    var stateIndex = -1
    
    // MARK: Registering changes
    
    /// Add a change to be undone with separate forwards and backwards transformers.
    ///
    /// If an undo grouping has been started, the action will be added to that group.
    open func registerChange(_ description: String, forwards: @escaping Closure, backwards: @escaping Closure) -> Closure {
        
        let standardAction = SPUndoManagerStandardAction(description: description, forwards: forwards, backwards: backwards)
        
        addAction(standardAction)
        
        return forwards
    }
    
    /// Add a super cool undoable action which always returns an undoable version
    /// of itself upon undoing or redoing (both are classed as undo)
    open func registerChange(_ undoable: Undoable) {
        
        addAction(SPUndoManagerSuperDynamicAction(undoable: undoable))
    }
    
    // MARK: Grouping
    
    open override var groupingLevel: Int {
        return pendingGroups.count
    }
    
    open func beginUndoGrouping(_ description: String) {
        let newGroup = SPUndoManagerGroupAction(description: description)
        
        addAction(newGroup)
        
        pendingGroups += [newGroup]
        
        NotificationCenter.default.post(name: NSNotification.Name.NSUndoManagerCheckpoint, object: self)
        NotificationCenter.default.post(name: NSNotification.Name.NSUndoManagerDidOpenUndoGroup, object: self)
    }
    
    open override func beginUndoGrouping() {
        beginUndoGrouping("Multiple Changes")
    }
    
    open func cancelUndoGrouping() {
        assert(!pendingGroups.isEmpty && pendingGroups.last!.done == false, "Attempting to cancel an undo grouping that was never started")
        
        let cancelled = pendingGroups.removeLast()
        cancelled.done = true
        cancelled.undo()
        
        removeLastAction()
    }
    
    open override func endUndoGrouping() {
        assert(!pendingGroups.isEmpty, "Attempting to end an undo grouping that was never started")
        
        let grouping = pendingGroups.removeLast()
        grouping.done = true
        
        NotificationCenter.default.post(name: NSNotification.Name.NSUndoManagerCheckpoint, object: self)
        NotificationCenter.default.post(name: NSNotification.Name.NSUndoManagerDidCloseUndoGroup, object: self)
    }
    
    open override func undoNestedGroup() {
        fatalError("Unimplemented")
    }
    
    // MARK: Removing changes
    
    open override func removeAllActions() {
        stateIndex = -1
        changes = []
        pendingGroups = []
    }
    
    open override func removeAllActions(withTarget target: Any) {
        fatalError("Not implemented")
    }
    
    // MARK: Undo/redo
    
    open override func undo() {
        while !pendingGroups.isEmpty {
            endUndoGrouping()
        }
        
        NotificationCenter.default.post(name: NSNotification.Name.NSUndoManagerWillUndoChange, object: self)
        
        _undoing = true
        
        let change = changes[stateIndex]
        change.undo()
        stateIndex -= 1
        
        _undoing = false
        
        NotificationCenter.default.post(name: NSNotification.Name.NSUndoManagerDidUndoChange, object: self)
        
    }
    
    open override func redo() {
        NotificationCenter.default.post(name: NSNotification.Name.NSUndoManagerWillRedoChange, object: self)
        
        _redoing = true
        
        let change = changes[stateIndex + 1]
        change.redo()
        stateIndex += 1
        
        _redoing = false
        
        NotificationCenter.default.post(name: NSNotification.Name.NSUndoManagerDidRedoChange, object: self)
    }
    
    open override var undoActionName: String {
        return changes.atIndex(stateIndex)?.description ?? ""
    }
    
    open override var redoActionName: String {
        return changes.atIndex(stateIndex + 1)?.description ?? ""
    }
    
    open override var canUndo: Bool {
        return changes.count > 0 && stateIndex >= 0
    }
    
    open override var canRedo: Bool {
        return changes.count > 0 && stateIndex < changes.count - 1
    }
    
    var _undoing: Bool = false
    var _redoing: Bool = false
    
    open override var isUndoing: Bool {
        return _undoing
    }
    
    open override var isRedoing: Bool {
        return _redoing
    }
    
    // MARK: Private
    
    func addAction(_ action: SPUndoManagerAction) {
        if isUndoing || isRedoing || !isUndoRegistrationEnabled {
            return
        }
        
        if pendingGroups.isEmpty {
            
            clearRedoAfterState()
            
            while levelsOfUndo > 0 && changes.count >= levelsOfUndo {
                changes.remove(at: 0)
                stateIndex -= 1
            }
            
            changes += [action]
            stateIndex += 1
            
            NotificationCenter.default.post(name: NSNotification.Name.NSUndoManagerDidCloseUndoGroup, object: self)
        }
        else {
            pendingGroups.last!.nestedActions += [action]
        }
    }
    
    func clearRedoAfterState() {
        changes.removeSubrange(min(stateIndex + 1, changes.count) ..< changes.count)
    }
    
    func removeLastAction() {
        if pendingGroups.isEmpty {
            changes.removeLast()
        }
        else {
            pendingGroups.last!.nestedActions.removeLast()
        }
    }
}

/// A forever undoable struct, should always return the inverse operation of itself
public struct Undoable {
    public init(description: String, undo: @escaping () -> Undoable) {
        self.description = description
        self.undo = undo
    }
    
    var description: String
    var undo: () -> Undoable
    
    /// Will register with document's SPUndoManager if available
    //    public func registerUndo() {
    //        SPUndoManagerGet()?.registerChange(self)
    //    }
}
