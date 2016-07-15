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

/// Returns a Signal whose value is the negation of the given boolean signal.
public func not<S: SignalType where S.Value: BooleanType>(signal: S) -> Signal<Bool> {
    return signal.map{ !$0.boolValue }
}

extension SignalType where Value: BooleanType {
    /// Returns a Signal whose value resolves to the logical OR of this signal and the other input signal.
    public func or(other: Self) -> Signal<Bool> {
        return BinaryOpSignal(self, other, { $0.boolValue || $1.boolValue })
    }
    
    /// Returns a Signal whose value resolves to the logical AND of the values delivered on this signal
    /// and the other input signal.
    public func and(other: Self) -> Signal<Bool> {
        return BinaryOpSignal(self, other, { $0.boolValue && $1.boolValue })
    }
    
    /// Returns a Signal that invokes the given function whenever this signal's value resolves to `true`.
    public func then(f: () -> Void) -> Signal<()> {
        return self.map{ if $0.boolValue { f() } }
    }
}

// TODO: This syntax is same as SelectExpression operators; maybe we should use something different
infix operator *|| {
associativity left
precedence 110
}

infix operator *&& {
associativity left
precedence 120
}

public func *||<S: SignalType where S.Value: BooleanType>(lhs: S, rhs: S) -> Signal<Bool> {
    return lhs.or(rhs)
}

public func *&&<S: SignalType where S.Value: BooleanType>(lhs: S, rhs: S) -> Signal<Bool> {
    return lhs.and(rhs)
}

infix operator *== {
associativity none
precedence 130
}

public func *==<S: SignalType where S.Value: Equatable>(lhs: S, rhs: S) -> Signal<Bool> {
    return BinaryOpSignal(lhs, rhs, { $0 == $1 })
}

extension SequenceType where Generator.Element: SignalType, Generator.Element.Value: BooleanType {
    /// Returns a Signal whose value resolves to `true` if *any* of the signals
    /// in this sequence resolve to `true`.
    public func anyTrue() -> Signal<Bool> {
        // TODO: Currently we require all captured values to be non-nil before we make the any-true
        // determination; should we instead resolve to true as soon as we see any signal go to true?
        return BoolSeqSignal(signals: self, { values in
            var anyTrue = false
            for value in values {
                if let v = value {
                    if v {
                        anyTrue = true
                    }
                } else {
                    return nil
                }
            }
            return anyTrue
        })
    }
    
    /// Returns a Signal whose value resolves to `true` if *all* of the signals
    /// in this sequence resolve to `true`.
    public func allTrue() -> Signal<Bool> {
        return BoolSeqSignal(signals: self, { values in
            var allTrue = true
            for value in values {
                if let v = value {
                    if !v {
                        allTrue = false
                    }
                } else {
                    return nil
                }
            }
            return allTrue
        })
    }
    
    /// Returns a Signal whose value resolves to `true` if *none* of the signals
    /// in this sequence resolve to `true`.
    public func noneTrue() -> Signal<Bool> {
        return BoolSeqSignal(signals: self, { values in
            var noneTrue = true
            for value in values {
                if let v = value {
                    if v {
                        noneTrue = false
                    }
                } else {
                    return nil
                }
            }
            return noneTrue
        })
    }
}

private class MappedSignal<T>: Signal<T> {
    private var removal: ObserverRemoval!
    
    init<S: SignalType>(underlying: S, transform: (S.Value) -> T) {
        super.init(changeCount: underlying.changeCount, startFunc: {
            underlying.start()
        })
        
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
    }
    
    deinit {
        removal()
    }
}

private class BinaryOpSignal<T>: Signal<T> {
    private var removal1: ObserverRemoval!
    private var removal2: ObserverRemoval!
    
    init<LHS: SignalType, RHS: SignalType>(_ lhs: LHS, _ rhs: RHS, _ f: (LHS.Value, RHS.Value) -> T) {
        super.init(changeCount: lhs.changeCount + rhs.changeCount, startFunc: {
            lhs.start()
            rhs.start()
        })
        
        var lhsValue: LHS.Value?
        var rhsValue: RHS.Value?
        func notify(s: Signal<T>?, _ metadata: ChangeMetadata) {
            if let lv = lhsValue, rv = rhsValue {
                s?.notifyChanging(f(lv, rv), metadata: metadata)
            }
        }
        
        self.removal1 = lhs.observe(SignalObserver(
            valueWillChange: { [weak self] in
                self?.notifyWillChange()
            },
            valueChanging: { [weak self] change, metadata in
                lhsValue = change
                notify(self, metadata)
            },
            valueDidChange: { [weak self] in
                self?.notifyDidChange()
            }
        ))
        self.removal2 = rhs.observe(SignalObserver(
            valueWillChange: { [weak self] in
                self?.notifyWillChange()
            },
            valueChanging: { [weak self] change, metadata in
                rhsValue = change
                notify(self, metadata)
            },
            valueDidChange: { [weak self] in
                self?.notifyDidChange()
            }
        ))
    }
    
    deinit {
        removal1()
        removal2()
    }
}

// TODO: Merge this with BinaryOpSignal?
private class BoolSeqSignal: Signal<Bool> {
    private var removals: [ObserverRemoval] = []
    
    init<S: SequenceType where S.Generator.Element: SignalType, S.Generator.Element.Value: BooleanType>(signals: S, _ f: [Bool?] -> Bool?) {
        var count = 0
        signals.forEach({ _ in count += 1 })
        var values = [Bool?](count: count, repeatedValue: nil)
        
        let changeCount = signals.map{ $0.changeCount }.reduce(0, combine: +)
        super.init(changeCount: changeCount, startFunc: {
            signals.forEach{ $0.start() }
        })
        
        for (index, signal) in signals.enumerate() {
            let removal = signal.observe(SignalObserver(
                valueWillChange: { [weak self] in
                    self?.notifyWillChange()
                },
                valueChanging: { [weak self] newValue, metadata in
                    values[index] = newValue.boolValue
                    if let boolValue = f(values) {
                        self?.notifyChanging(boolValue, metadata: metadata)
                    }
                },
                valueDidChange: { [weak self] in
                    self?.notifyDidChange()
                }
            ))
            removals.append(removal)
        }
    }
    
    deinit {
        removals.forEach{ $0() }
    }
}
