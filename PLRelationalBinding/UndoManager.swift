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

protocol SPUndoManagerAction {
    
    var done: Bool { get }
    func undo()
    func redo()
    var description: String { get }
}

class SPUndoManagerStandardAction : SPUndoManagerAction, CustomStringConvertible {
    
    /// Assumes action already performed
    init(undoManager: SPUndoManager, description: String, forwards: @escaping () -> Void, backwards: @escaping () -> Void) {
        self.undoManager = undoManager
        self.forwards = forwards
        self.backwards = backwards
        self.description = description
        self.done = true
    }
    
    weak var undoManager: SPUndoManager?
    var done: Bool
    var backwards: () -> Void
    var forwards: () -> Void
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

open class SPUndoManager : Foundation.UndoManager {
    weak var delegate: UndoManagerDelegate?
    
    /// Add a change to be undone with separate forwards and backwards transformers.
    open func registerChange(_ description: String, forwards: @escaping () -> Void, backwards: @escaping () -> Void) {
        let action = SPUndoManagerStandardAction(undoManager: self, description: description, forwards: forwards, backwards: backwards)
        register(action: action)
    }
    
    fileprivate func register(action: SPUndoManagerStandardAction) {
        registerUndo(withTarget: self, selector: #selector(performStandardAction), object: action)
        setActionName(action.description)
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
