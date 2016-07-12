//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension SignalType {
    /// Returns a Signal that applies the given `transform` to each new value.
    public func map<U>(transform: Self.Value -> U) -> Signal<U> {
        return MappedSignal(underlying: self, transform: transform)
    }
}

/// Returns a Signal that creates a fresh tuple (pair) any time there is a new value in either input.
public func zip<LHS: SignalType, RHS: SignalType>(lhs: LHS, _ rhs: RHS) -> Signal<(LHS.Value, RHS.Value)> {
    return BinaryOpSignal(lhs, rhs, { ($0, $1) })
}

private class MappedSignal<T>: Signal<T> {
    private var removal: ObserverRemoval!
    
    init<S: SignalType>(underlying: S, transform: (S.Value) -> T) {
        super.init()
        self.removal = underlying.observe(SignalObserver(
            valueWillChange: self.notifyWillChange,
            valueChanging: { [weak self] change, metadata in
                self?.notifyChanging(transform(change), metadata: metadata)
            },
            valueDidChange: self.notifyDidChange
        ))
    }
    
    deinit {
        removal()
    }
}

private class BinaryOpSignal<T>: Signal<T> {
    private var removal1: ObserverRemoval!
    private var removal2: ObserverRemoval!
    
    init<LHS: SignalType, RHS: SignalType>(_ lhs: LHS, _ rhs: RHS, _ f: (LHS.Value, RHS.Value) -> T) {
        super.init()
        
        var lhsValue: LHS.Value?
        var rhsValue: RHS.Value?
        func notify(s: Signal<T>?, _ metadata: ChangeMetadata) {
            if let lv = lhsValue, rv = rhsValue {
                s?.notifyChanging(f(lv, rv), metadata: metadata)
            }
        }
        
        self.removal1 = lhs.observe(SignalObserver(
            valueWillChange: self.notifyWillChange,
            valueChanging: { [weak self] change, metadata in
                lhsValue = change
                notify(self, metadata)
            },
            valueDidChange: self.notifyDidChange
        ))
        self.removal2 = rhs.observe(SignalObserver(
            valueWillChange: self.notifyWillChange,
            valueChanging: { [weak self] change, metadata in
                rhsValue = change
                notify(self, metadata)
            },
            valueDidChange: self.notifyDidChange
        ))
    }
    
    deinit {
        removal1()
        removal2()
    }
}
