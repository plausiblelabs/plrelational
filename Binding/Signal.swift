//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public class Signal<T> {
    public typealias Observer = (T, ChangeMetadata) -> Void
    public typealias Notify = (newValue: T, metadata: ChangeMetadata) -> Void

    private var observers: [UInt64: Observer] = [:]
    private var nextObserverID: UInt64 = 0
    
    private init() {
    }
    
    public static func pipe() -> (Signal, Notify) {
        let signal = Signal()
        let notify = signal.notifyObservers
        return (signal, notify)
    }
    
    public func observe(observer: Observer) -> ObserverRemoval {
        let id = nextObserverID
        nextObserverID += 1
        observers[id] = observer
        return { self.observers.removeValueForKey(id) }
    }
    
    private func notifyObservers(newValue: T, metadata: ChangeMetadata) {
        for (_, f) in observers {
            f(newValue, metadata)
        }
    }
    
    // For testing purposes only.
    internal var observerCount: Int { return observers.count }
}
