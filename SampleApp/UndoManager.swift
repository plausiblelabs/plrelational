//
//  UndoManager.swift
//  Change
//
//  Created by Chris Campbell on 4/25/16.
//  Copyright © 2016 Plausible Labs. All rights reserved.
//

import Foundation

class UndoManager {
    
    private let nsmanager: SPUndoManager
    
    init(nsmanager: SPUndoManager) {
        self.nsmanager = nsmanager
    }
    
    func registerChange(name name: String, perform: Bool, forward: () -> Void, backward: () -> Void) {
        // First register the change
        let f = nsmanager.registerChange(name, forwards: forward, backwards: backward)
        
        if perform {
            // Then invoke the `forward` function if requested
            f()
        }
    }
}

// The following is pulled from:
//   https://github.com/andrewshand/SPUndoManager

extension Array {
    func atIndex(index: Int) -> Element? {
        if index >= 0 && index < count {
            return self[index]
        }
        return nil
    }
    
    func each(function: (element: Element) -> Void) {
        for e in self {
            function(element: e)
        }
    }
    
    func eachForwards(function: (element: Element) -> Void) {
        for i in 0 ..< self.count {
            function(element: self[i])
        }
    }
    
    func eachBackwards(function: (element: Element) -> Void) {
        for i in (0..<self.count).reverse() {
            function(element: self[i])
        }
    }
}

public func undoableFrom<T>(undoable: (T, Undoable)) -> Undoable {
    return undoable.1
}

/// Only use when you're sure the action should definitely be undoable, possibly
/// good way of testing things
public func undoableForceFrom<T>(undoable: (T, Undoable?)) -> Undoable {
    return undoable.1!
}

public func ignoreUndo<T>(undoable: (T, Undoable)) -> T {
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
    init(description: String, forwards: Closure, backwards: Closure) {
        
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

public class SPUndoManager : NSUndoManager {
    
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
    public func registerChange(description: String, forwards: Closure, backwards: Closure) -> Closure {
        
        let standardAction = SPUndoManagerStandardAction(description: description, forwards: forwards, backwards: backwards)
        
        addAction(standardAction)
        
        return forwards
    }
    
    /// Add a super cool undoable action which always returns an undoable version
    /// of itself upon undoing or redoing (both are classed as undo)
    public func registerChange(undoable: Undoable) {
        
        addAction(SPUndoManagerSuperDynamicAction(undoable: undoable))
    }
    
    // MARK: Grouping
    
    public override var groupingLevel: Int {
        return pendingGroups.count
    }
    
    public func beginUndoGrouping(description: String) {
        let newGroup = SPUndoManagerGroupAction(description: description)
        
        addAction(newGroup)
        
        pendingGroups += [newGroup]
        
        NSNotificationCenter.defaultCenter().postNotificationName(NSUndoManagerCheckpointNotification, object: self)
        NSNotificationCenter.defaultCenter().postNotificationName(NSUndoManagerDidOpenUndoGroupNotification, object: self)
    }
    
    public override func beginUndoGrouping() {
        beginUndoGrouping("Multiple Changes")
    }
    
    public func cancelUndoGrouping() {
        assert(!pendingGroups.isEmpty && pendingGroups.last!.done == false, "Attempting to cancel an undo grouping that was never started")
        
        let cancelled = pendingGroups.removeLast()
        cancelled.done = true
        cancelled.undo()
        
        removeLastAction()
    }
    
    public override func endUndoGrouping() {
        assert(!pendingGroups.isEmpty, "Attempting to end an undo grouping that was never started")
        
        let grouping = pendingGroups.removeLast()
        grouping.done = true
        
        NSNotificationCenter.defaultCenter().postNotificationName(NSUndoManagerCheckpointNotification, object: self)
        NSNotificationCenter.defaultCenter().postNotificationName(NSUndoManagerDidCloseUndoGroupNotification, object: self)
    }
    
    public override func undoNestedGroup() {
        fatalError("Unimplemented")
    }
    
    // MARK: Removing changes
    
    public override func removeAllActions() {
        stateIndex = -1
        changes = []
        pendingGroups = []
    }
    
    public override func removeAllActionsWithTarget(target: AnyObject) {
        fatalError("Not implemented")
    }
    
    // MARK: Undo/redo
    
    public override func undo() {
        while !pendingGroups.isEmpty {
            endUndoGrouping()
        }
        
        NSNotificationCenter.defaultCenter().postNotificationName(NSUndoManagerWillUndoChangeNotification, object: self)
        
        _undoing = true
        
        let change = changes[stateIndex]
        change.undo()
        stateIndex -= 1
        
        _undoing = false
        
        NSNotificationCenter.defaultCenter().postNotificationName(NSUndoManagerDidUndoChangeNotification, object: self)
        
    }
    
    public override func redo() {
        NSNotificationCenter.defaultCenter().postNotificationName(NSUndoManagerWillRedoChangeNotification, object: self)
        
        _redoing = true
        
        let change = changes[stateIndex + 1]
        change.redo()
        stateIndex += 1
        
        _redoing = false
        
        NSNotificationCenter.defaultCenter().postNotificationName(NSUndoManagerDidRedoChangeNotification, object: self)
    }
    
    public override var undoActionName: String {
        return changes.atIndex(stateIndex)?.description ?? ""
    }
    
    public override var redoActionName: String {
        return changes.atIndex(stateIndex + 1)?.description ?? ""
    }
    
    public override var canUndo: Bool {
        return changes.count > 0 && stateIndex >= 0
    }
    
    public override var canRedo: Bool {
        return changes.count > 0 && stateIndex < changes.count - 1
    }
    
    var _undoing: Bool = false
    var _redoing: Bool = false
    
    public override var undoing: Bool {
        return _undoing
    }
    
    public override var redoing: Bool {
        return _redoing
    }
    
    // MARK: Private
    
    func addAction(action: SPUndoManagerAction) {
        if undoing || redoing || !undoRegistrationEnabled {
            return
        }
        
        if pendingGroups.isEmpty {
            
            clearRedoAfterState()
            
            while levelsOfUndo > 0 && changes.count >= levelsOfUndo {
                changes.removeAtIndex(0)
                stateIndex -= 1
            }
            
            changes += [action]
            stateIndex += 1
            
            NSNotificationCenter.defaultCenter().postNotificationName(NSUndoManagerDidCloseUndoGroupNotification, object: self)
        }
        else {
            pendingGroups.last!.nestedActions += [action]
        }
    }
    
    func clearRedoAfterState() {
        changes.removeRange(min(stateIndex + 1, changes.count) ..< changes.count)
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
    public init(description: String, undo: () -> Undoable) {
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
