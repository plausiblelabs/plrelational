
/// A mixin protocol which provides a default implementation to manage change
/// observers. Types which conform must provide the one stored property in
/// the protocol, then get the implementation provided.
protocol RelationDefaultChangeObserverImplementation: class, Relation {
    var changeObserverData: RelationDefaultChangeObserverImplementationData { get set }
    
    /// This function is called the first time an observer is added. This allows
    /// implementors to lazily set up any necessay infrastructure for providing
    /// observation calls. The default implementation does nothing.
    func onAddFirstObserver()
}

struct RelationDefaultChangeObserverImplementationData {
    private var didAddFirstObserver = false
    private var observers: [UInt64: Void -> Void] = [:]
    private var nextID: UInt64 = 0
}

extension RelationDefaultChangeObserverImplementation {
    func addChangeObserver(f: Void -> Void) -> (Void -> Void) {
        let id = changeObserverData.nextID
        changeObserverData.nextID += 1
        
        changeObserverData.observers[id] = f
        
        if !changeObserverData.didAddFirstObserver {
            changeObserverData.didAddFirstObserver = true
            self.onAddFirstObserver()
        }
        
        return { self.changeObserverData.observers.removeValueForKey(id) }
    }
    
    func onAddFirstObserver() {}
    
    func notifyChangeObservers() {
        for (_, f) in changeObserverData.observers {
            f()
        }
    }
}
