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
    private var startFunc: ((Bool) -> Void)?
    private var removal: ObserverRemoval?
    
    init<S: SignalType>(underlying: S, transform: @escaping (S.Value) -> T) {
        super.init()
        
        self.startFunc = { deliverInitial in
            // Observe the underlying signal
            self.removal = underlying.observe(SignalObserver(
                valueWillChange: { [weak self] in
                    self?.notifyWillChange()
                },
                valueChanging: { [weak self] change, metadata in
                    self?.notifyChanging(transform(change), metadata: metadata)
                },
                valueDidChange: { [weak self] in
                    self?.notifyDidChange()
                }
            ))
            
            // Start the underlying signal
            underlying.start(deliverInitial: deliverInitial)
            
            // Take on the change count of the underlying signal
            self.setChangeCount(underlying.changeCount)
        }
    }

    override func startImpl(deliverInitial: Bool) {
        startFunc?(deliverInitial)
        startFunc = nil
    }

    deinit {
        removal?()
    }
}
