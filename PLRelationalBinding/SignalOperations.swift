//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension SignalType {
    /// Returns a Signal that applies the given `transform` to each new value.
    public func map<U>(_ transform: @escaping (Self.Value) -> U) -> Signal<U> {
        return MappedSignal(underlying: self, transform: transform)
    }
}

// TODO: BinaryOpSignal captures the latest value delivered by each underlying signal and doesn't deliver
// a pair until it sees a change from *both* signals.  This can lead to surprising behavior if the BinaryOpSignal
// is created after one or both of the underlying signals have already delivered their initial value.  For the
// time being we will comment out the affected operations, and hopefully we can re-expose them once we have
// a more refined system.

/// Returns a Signal whose value is the negation of the given boolean signal.
public func not(_ signal: Signal<Bool>) -> Signal<Bool> {
    return signal.map{ !$0 }
}

extension SignalType where Value == Bool {
    
    /// Returns a Signal that invokes the given function whenever this signal's value resolves to `true`.
    public func then(_ f: @escaping () -> Void) -> Signal<()> {
        return self.map{ if $0 { f() } }
    }
}

private class MappedSignal<T>: Signal<T> {
    private let observeFunc: (Observer) -> ObserverRemoval
    private let countFunc: () -> Int
    
    init<S: SignalType>(underlying: S, transform: @escaping (S.Value) -> T) {
        self.observeFunc = { observer in
            // Observe the underlying signal
            return underlying.observe(SignalObserver(
                valueWillChange: {
                    observer.valueWillChange()
                },
                valueChanging: { change, metadata in
                    observer.valueChanging(transform(change), metadata)
                },
                valueDidChange: {
                    observer.valueDidChange()
                }
            ))
        }
        
        self.countFunc = {
            return underlying.observerCount
        }
        
        super.init()
    }

    override func observe(_ observer: Observer) -> ObserverRemoval {
        return observeFunc(observer)
    }
    
    override var observerCount: Int {
        return countFunc()
    }
}
