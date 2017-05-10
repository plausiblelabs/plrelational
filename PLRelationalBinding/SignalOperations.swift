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
    
    /// Returns a Signal whose values are derived from the given signal.  The given `transform`
    /// will be applied whenever this signal's value changes, and in turn the signal returned by
    /// `transform` becomes the new source of values.
    public func flatMap<S: SignalType>(_ transform: @escaping (Self.Value) -> S) -> Signal<S.Value> {
        return FlatMappedSignal(underlying: self, transform: transform)
    }
}

/// Returns a Signal that creates a fresh tuple (pair) any time there is a new value in either input.
public func zip<LHS: SignalType, RHS: SignalType>(_ lhs: LHS, _ rhs: RHS) -> Signal<(LHS.Value, RHS.Value)> {
    return BinaryOpSignal(lhs, rhs, { ($0, $1) })
}

/// Returns a Signal whose value is the negation of the given boolean signal.
public func not(_ signal: Signal<Bool>) -> Signal<Bool> {
    return signal.map{ !$0 }
}

extension SignalType where Value == Bool {
    /// Returns a Signal whose value resolves to the logical OR of this signal and the other input signal.
    public func or(_ other: Self) -> Signal<Bool> {
        return BinaryOpSignal(self, other, { $0 || $1 })
    }

    /// Returns a Signal whose value resolves to the logical AND of the values delivered on this signal
    /// and the other input signal.
    public func and(_ other: Self) -> Signal<Bool> {
        return BinaryOpSignal(self, other, { $0 && $1 })
    }
    
    /// Returns a Signal that invokes the given function whenever this signal's value resolves to `true`.
    public func then(_ f: @escaping () -> Void) -> Signal<()> {
        return self.map{ if $0 { f() } }
    }
}

// TODO: This syntax is same as SelectExpression operators; maybe we should use something different
infix operator *|| : LogicalDisjunctionPrecedence

infix operator *&& : LogicalConjunctionPrecedence

public func *||(lhs: Signal<Bool>, rhs: Signal<Bool>) -> Signal<Bool> {
    return lhs.or(rhs)
}

public func *&&(lhs: Signal<Bool>, rhs: Signal<Bool>) -> Signal<Bool> {
    return lhs.and(rhs)
}

infix operator *== : ComparisonPrecedence

public func *==<S: SignalType>(lhs: S, rhs: S) -> Signal<Bool> where S.Value: Equatable {
    return BinaryOpSignal(lhs, rhs, { $0 == $1 })
}

private class MappedSignal<T>: Signal<T> {
    private let observeFunc: (Observer) -> ObserverRemoval
    private let countFunc: () -> Int
    
    init<S: SignalType>(underlying: S, transform: @escaping (S.Value) -> T) {
        self.observeFunc = { observer in
            // Observe the underlying signal
            return underlying.observe{ event in
                switch event {
                case .beginPossibleAsyncChange:
                    observer.notifyBeginPossibleAsyncChange()
                    
                case let .valueChanging(newValue, metadata):
                    observer.notifyValueChanging(transform(newValue), metadata)
                    
                case .endPossibleAsyncChange:
                    observer.notifyEndPossibleAsyncChange()
                }
            }
        }
        
        self.countFunc = {
            return underlying.observerCount
        }
        
        super.init()
    }

    override func addObserver(_ observer: Observer) -> ObserverRemoval {
        return observeFunc(observer)
    }
    
    override var observerCount: Int {
        return countFunc()
    }
}

private class FlatMappedSignal<S: SignalType, T: SignalType>: SourceSignal<T.Value> {
    private let underlying: Signal<S.Value>
    private let transform: (S.Value) -> T
    private var mappedValue: T.Value?
    private var underlyingSignalObserverRemoval: ObserverRemoval?
    private var mappedSignalObserverRemoval: ObserverRemoval?
    
    init(underlying: S, transform: @escaping (S.Value) -> T) {
        self.underlying = underlying.signal
        self.transform = transform
        
        super.init()
    }

    deinit {
        underlyingSignalObserverRemoval?()
        mappedSignalObserverRemoval?()
    }
    
    override func observeImpl(_ observer: Observer) {
        if self.underlyingSignalObserverRemoval == nil {
            // Observe the underlying signal when the first observer is attached
            self.underlyingSignalObserverRemoval = underlying.observe{ event in
                switch event {
                case .beginPossibleAsyncChange:
                    self.notifyBeginPossibleAsyncChange()
                    
                case let .valueChanging(newValue, _):
                    // When the underlying signal produces a new value, create and observe the signal
                    // produced by `transform`
                    self.mappedValue = nil
                    self.mappedSignalObserverRemoval?()
                    let newSignal = self.transform(newValue)
                    self.mappedSignalObserverRemoval = newSignal.observe{ event in
                        switch event {
                        case .beginPossibleAsyncChange:
                            self.notifyBeginPossibleAsyncChange()
                            
                        case let .valueChanging(newValue, metadata):
                            self.mappedValue = newValue
                            self.notifyValueChanging(newValue, metadata)
                            
                        case .endPossibleAsyncChange:
                            self.notifyEndPossibleAsyncChange()
                        }
                    }
                    
                case .endPossibleAsyncChange:
                    self.notifyEndPossibleAsyncChange()
                }
            }
        } else {
            // When other observers are attached, just deliver the latest mapped value
            // TODO: Take Begin/EndPossibleAsync into account
            if let mappedValue = mappedValue {
                observer.notifyValueChanging(mappedValue)
            }
        }
    }
    
    override var observerCount: Int {
        // TODO: Does this need to take the mapped signal into account too?  (Not too important, since observerCount is for
        // debugging purposes only.)
        return underlying.observerCount
    }
}

private class BinaryOpSignal<T>: Signal<T> {
    
    private let observeFunc: (Observer) -> ObserverRemoval
    private let countFunc: () -> Int
    
    init<LHS: SignalType, RHS: SignalType>(_ lhs: LHS, _ rhs: RHS, _ f: @escaping (LHS.Value, RHS.Value) -> T) {
        self.observeFunc = { observer in
            var lhsValue: LHS.Value?
            var rhsValue: RHS.Value?
            
            func notify(_ metadata: ChangeMetadata) {
                if let lv = lhsValue, let rv = rhsValue {
                    observer.notifyValueChanging(f(lv, rv), metadata)
                }
            }
            
            // Observe the lhs signal
            let lhsRemoval = lhs.observe{ event in
                switch event {
                case .beginPossibleAsyncChange:
                    observer.notifyBeginPossibleAsyncChange()
                    
                case let .valueChanging(newValue, metadata):
                    lhsValue = newValue
                    notify(metadata)

                case .endPossibleAsyncChange:
                    observer.notifyEndPossibleAsyncChange()
                }
            }
            
            // Observe the rhs signal
            let rhsRemoval = rhs.observe{ event in
                switch event {
                case .beginPossibleAsyncChange:
                    observer.notifyBeginPossibleAsyncChange()
                    
                case let .valueChanging(newValue, metadata):
                    rhsValue = newValue
                    notify(metadata)
                    
                case .endPossibleAsyncChange:
                    observer.notifyEndPossibleAsyncChange()
                }
            }
            
            return {
                lhsRemoval()
                rhsRemoval()
            }
        }
        
        self.countFunc = {
            return lhs.observerCount + rhs.observerCount
        }
        
        super.init()
    }
    
    override func addObserver(_ observer: Observer) -> ObserverRemoval {
        return observeFunc(observer)
    }
    
    override var observerCount: Int {
        return countFunc()
    }
}
