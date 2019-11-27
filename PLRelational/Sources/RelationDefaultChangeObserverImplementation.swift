//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc: Implementation detail (will be made non-public eventually)
/// A mixin protocol which provides a default implementation to manage change
/// observers. Types which conform must provide the one stored property in
/// the protocol, then get the implementation provided.
public protocol RelationDefaultChangeObserverImplementation: class, Relation {
    var changeObserverData: RelationDefaultChangeObserverImplementationData { get set }
    
    /// This function is called when an observer is added where there were previously none.
    /// This allows implementors to lazily set up any necessay infrastructure for providing
    /// observation calls. The default implementation does nothing.
    func onAddFirstObserver()
    
    /// This function is called when the last observer is removed, leaving the Relation free
    /// of observers. This allows implementors to clean up observation-related stuff. Note:
    /// Once this is called, onAddFirstObserver will be called again if another observation
    /// is added.
    func onRemoveLastObserver()
}

/// :nodoc: Implementation detail (will be made non-public eventually)
public struct RelationDefaultChangeObserverImplementationData {
    fileprivate var didAddFirstObserver = false
    fileprivate var observers: [UInt64: (observer: RelationObserver, kinds: [RelationObservationKind])]?
    fileprivate var nextID: UInt64 = 0
}

/// :nodoc: Implementation detail (will be made non-public eventually)
extension RelationDefaultChangeObserverImplementation {
    public func addChangeObserver(_ observer: RelationObserver, kinds: [RelationObservationKind]) -> (() -> Void) {
        let id = changeObserverData.nextID
        changeObserverData.nextID += 1
        
        if changeObserverData.observers == nil {
            changeObserverData.observers = [:]
        }
        
        changeObserverData.observers![id] = (observer, kinds)
        
        if !changeObserverData.didAddFirstObserver {
            changeObserverData.didAddFirstObserver = true
            self.onAddFirstObserver()
        }
        
        return {
            self.changeObserverData.observers!.removeValue(forKey: id)
            if self.changeObserverData.observers!.count == 0 {
                self.changeObserverData.didAddFirstObserver = false
                self.onRemoveLastObserver()
            }
        }
    }
    
    public func onAddFirstObserver() {}
    public func onRemoveLastObserver() {}
    
    func notifyObserversTransactionBegan(_ kind: RelationObservationKind) {
        if let observers = changeObserverData.observers {
            for (_, entry) in observers where entry.kinds.contains(kind) {
                entry.observer.transactionBegan()
            }
        }
    }
    
    func notifyChangeObservers(_ change: RelationChange, kind: RelationObservationKind) {
        func isEmpty(_ r: Relation?) -> Bool {
            return r == nil || r?.isEmpty.ok == true
        }
        
        if let observers = changeObserverData.observers {
            // Don't bother notifying if there aren't actually any changes.
            if isEmpty(change.added) && isEmpty(change.removed) {
                return
            }
        
            for (_, entry) in observers where entry.kinds.contains(kind) {
                entry.observer.relationChanged(self, change: change)
            }
        }
    }
    
    func notifyObserversTransactionEnded(_ kind: RelationObservationKind) {
        if let observers = changeObserverData.observers {
            for (_, entry) in observers where entry.kinds.contains(kind) {
                entry.observer.transactionEnded()
            }
        }
    }
}
