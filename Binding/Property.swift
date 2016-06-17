//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public class Property<T> {

    private let onValue: T -> Void
    private var removal: ObserverRemoval?
    
    public init(_ onValue: T -> Void) {
        self.onValue = onValue
    }

    deinit {
        removal?()
    }
    
    public func bind(signal: Signal<T>, initialValue: T) {
        // Unbind if already bound to something
        unbind()
        
        // Make this property take on the given initial value
        self.onValue(initialValue)
        
        // Observe the given signal for changes
        self.removal = signal.observe({ [weak self] value, metadata in
            guard let weakSelf = self else { return }
            //if weakSelf.selfInitiatedChange.contains(changeKey) { return }
            weakSelf.onValue(value)
        })
    }
    
    public func unbind() {
        removal?()
        removal = nil
    }
}

public class BidiProperty<T>: Property<T> {

    private let internalValue: MutableObservableValue<T>
    private var bidiRemoval: ObserverRemoval?
    
    public init(initialValue: T, _ onValue: T -> Void, valueChanging: (T, T) -> Bool = valueChanging) {
        self.internalValue = mutableObservableValue(initialValue, valueChanging: valueChanging)
        super.init(onValue)
    }
    
    deinit {
        bidiRemoval?()
    }

    public func bindBidi(other: BidiProperty<T>) {
        // TODO
    }

    public override func unbind() {
        super.unbind()
        
        bidiRemoval?()
        bidiRemoval = nil
    }
}
    
public class MutableBidiProperty<T>: BidiProperty<T> {
    public override init(initialValue: T, _ onValue: T -> Void, valueChanging: (T, T) -> Bool = valueChanging) {
        super.init(initialValue: initialValue, onValue, valueChanging: valueChanging)
    }

    public func update(newValue: T, transient: Bool) {
        //selfInitiatedChange.insert(changeKey)
        internalValue.update(newValue, ChangeMetadata(transient: transient))
        //selfInitiatedChange.remove(changeKey)
    }
}

// This syntax is borrowed from ReactiveCocoa.
infix operator <~ {
    associativity right
    precedence 93
}

public func <~ <T>(property: Property<T>, observable: ObservableValue<T>?) {
    if let observable = observable {
        property.bind(observable.signal, initialValue: observable.value)
    } else {
        property.unbind()
    }
}

infix operator <~> {
    associativity right
    precedence 93
}

public func <~> <T>(lhs: BidiProperty<T>, rhs: BidiProperty<T>?) {
    if let rhs = rhs {
        lhs.bindBidi(rhs)
    } else {
        lhs.unbind()
    }
}
