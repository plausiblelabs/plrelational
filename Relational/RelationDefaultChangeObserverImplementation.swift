//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// A mixin protocol which provides a default implementation to manage change
/// observers. Types which conform must provide the one stored property in
/// the protocol, then get the implementation provided.
public protocol RelationDefaultChangeObserverImplementation: class, Relation {
    var changeObserverData: RelationDefaultChangeObserverImplementationData { get set }
    
    /// This function is called the first time an observer is added. This allows
    /// implementors to lazily set up any necessay infrastructure for providing
    /// observation calls. The default implementation does nothing.
    func onAddFirstObserver()
}

public struct RelationDefaultChangeObserverImplementationData {
    private var didAddFirstObserver = false
    private var observers: [UInt64: (observer: RelationObserver, kinds: [RelationObservationKind])]?
    private var nextID: UInt64 = 0
}

extension RelationDefaultChangeObserverImplementation {
    public func addChangeObserver(observer: RelationObserver, kinds: [RelationObservationKind]) -> (Void -> Void) {
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
        
        return { self.changeObserverData.observers!.removeValueForKey(id) }
    }
    
    public func onAddFirstObserver() {}
    
    func notifyObserversTransactionBegan(kind: RelationObservationKind) {
        if let observers = changeObserverData.observers {
            for (_, entry) in observers where entry.kinds.contains(kind) {
                entry.observer.transactionBegan()
            }
        }
    }
    
    func notifyChangeObservers(change: RelationChange, kind: RelationObservationKind) {
        func isEmpty(r: Relation?) -> Bool {
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
    
    func notifyObserversTransactionEnded(kind: RelationObservationKind) {
        if let observers = changeObserverData.observers {
            for (_, entry) in observers where entry.kinds.contains(kind) {
                entry.observer.transactionEnded()
            }
        }
    }
}
