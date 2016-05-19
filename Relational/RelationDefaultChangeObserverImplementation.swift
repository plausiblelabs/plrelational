
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
    private var observers: [UInt64: RelationChange -> Void] = [:]
    private var nextID: UInt64 = 0
}

extension RelationDefaultChangeObserverImplementation {
    public func addChangeObserver(f: RelationChange -> Void) -> (Void -> Void) {
        let id = changeObserverData.nextID
        changeObserverData.nextID += 1
        
        changeObserverData.observers[id] = f
        
        if !changeObserverData.didAddFirstObserver {
            changeObserverData.didAddFirstObserver = true
            self.onAddFirstObserver()
        }
        
        return { self.changeObserverData.observers.removeValueForKey(id) }
    }
    
    public func onAddFirstObserver() {}
    
    func notifyChangeObservers(changes: RelationChange) {
        func isEmpty(r: Relation?) -> Bool {
            return r == nil || r?.isEmpty.ok == true
        }
        
        // Don't bother notifying if there aren't actually any changes.
        if isEmpty(changes.added) && isEmpty(changes.removed) {
            return
        }
        
        for (_, f) in changeObserverData.observers {
            f(changes)
        }
    }
}
