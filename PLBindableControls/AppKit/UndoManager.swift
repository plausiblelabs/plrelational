//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public protocol UndoManagerDelegate: class {
    func safeToUndo() -> Bool
    func safeToRedo() -> Bool
}

public class UndoManager {
    
    private let nsmanager: SPUndoManager
    
    public var delegate: UndoManagerDelegate? {
        get {
            return nsmanager.delegate
        }
        set {
            nsmanager.delegate = newValue
        }
    }
    
    public var systemUndoManager: Foundation.UndoManager {
        return nsmanager
    }
    
    public init() {
        self.nsmanager = SPUndoManager()
    }
    
    public init(nsmanager: SPUndoManager) {
        self.nsmanager = nsmanager
    }
    
    public func registerChange(name: String, perform: Bool, forward: @escaping () -> Void, backward: @escaping () -> Void) {
        // First register the change
        nsmanager.registerChange(name, forwards: forward, backwards: backward)
        
        if perform {
            // Then invoke the `forward` function if requested
            forward()
        }
    }
    
    public func undo() {
        nsmanager.undo()
    }
    
    public func redo() {
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

class SPUndoManagerStandardAction : SPUndoManagerAction, CustomStringConvertible {
    
    /// Assumes action already performed
    init(undoManager: SPUndoManager, description: String, forwards: @escaping Closure, backwards: @escaping Closure) {
        self.undoManager = undoManager
        self.forwards = forwards
        self.backwards = backwards
        self.description = description
        self.done = true
    }
    
    weak var undoManager: SPUndoManager?
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
    
    func perform() {
        if undoManager?.isUndoing == true {
            self.undo()
        } else if undoManager?.isRedoing == true {
            self.redo()
        }
        
        undoManager?.register(action: self)
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
    weak var delegate: UndoManagerDelegate?
    
    /// Add a change to be undone with separate forwards and backwards transformers.
    open func registerChange(_ description: String, forwards: @escaping Closure, backwards: @escaping Closure) {
        let action = SPUndoManagerStandardAction(undoManager: self, description: description, forwards: forwards, backwards: backwards)
        register(action: action)
    }
    
    fileprivate func register(action: SPUndoManagerStandardAction) {
        registerUndo(withTarget: self, selector: #selector(performStandardAction), object: action)
    }
    
    @objc func performStandardAction(_ action: Any?) {
        (action as? SPUndoManagerStandardAction)?.perform()
    }
    
    open override var canUndo: Bool {
        let safeToUndo = delegate?.safeToUndo() ?? true
        return safeToUndo && super.canUndo
    }

    open override var canRedo: Bool {
        let safeToRedo = delegate?.safeToRedo() ?? true
        return safeToRedo && super.canRedo
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
