//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

private class ConstantValueProperty<T>: ReadableProperty<T> {
    private init(_ value: T) {
        // TODO: Use a no-op signal here
        let (signal, notify) = Signal<T>.pipe()
        super.init(initialValue: value, signal: signal, notify: notify, changing: { _ in false })
    }
}

/// Returns a ValueProperty whose value never changes.  Note that since the value cannot change,
/// observers will never be notified of changes.
public func constantValueProperty<T>(value: T) -> ReadableProperty<T> {
    return ConstantValueProperty(value)
}

public class MutableValueProperty<T>: ReadWriteProperty<T> {

    public let change: (T, transient: Bool) -> Void

    private init(_ initialValue: T, valueChanging: (T, T) -> Bool, didSet: Setter?) {
        let (signal, notify) = Signal<T>.pipe()

        var value = initialValue

        change = { (newValue: T, transient: Bool) in
            if valueChanging(value, newValue) {
                value = newValue
                notify(newValue: newValue, metadata: ChangeMetadata(transient: transient))
            }
        }

        super.init(
            get: {
                value
            },
            set: { newValue, metadata in
                if valueChanging(value, newValue) {
                    value = newValue
                    didSet?(newValue, metadata)
                    notify(newValue: newValue, metadata: metadata)
                }
            },
            signal: signal,
            notify: notify
        )
    }
}

public func mutableValueProperty<T>(initialValue: T, valueChanging: (T, T) -> Bool) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, valueChanging: valueChanging, didSet: nil)
}

public func mutableValueProperty<T: Equatable>(initialValue: T) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, valueChanging: valueChanging, didSet: nil)
}

public func mutableValueProperty<T: Equatable>(initialValue: T?) -> MutableValueProperty<T?> {
    return MutableValueProperty(initialValue, valueChanging: valueChanging, didSet: nil)
}

extension ReadablePropertyType {
    /// Returns a ReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U>(transform: Self.Value -> U) -> ReadableProperty<U> {
        return MappedValueProperty(property: self, transform: transform, valueChanging: valueChanging)
    }
    
    /// Returns a ValueProperty whose value is derived from this ValueProperty's `value`.
    /// The given `transform` will be applied whenever this ValueProperty`s value changes.
    public func map<U: Equatable>(transform: Self.Value -> U) -> ReadableProperty<U> {
        return MappedValueProperty(property: self, transform: transform, valueChanging: valueChanging)
    }
}

private class MappedValueProperty<T>: ReadableProperty<T> {
    private var removal: ObserverRemoval!
    
    init<P: ReadablePropertyType>(property: P, transform: (P.Value) -> T, valueChanging: (T, T) -> Bool) {
        let (signal, notify) = Signal<T>.pipe()
        super.init(initialValue: transform(property.value), signal: signal, notify: notify, changing: valueChanging)
        self.removal = property.signal.observe({ [weak self] _, metadata in
            self?.setValue(transform(property.value), metadata)
        })
    }
    
    deinit {
        removal()
    }
}
