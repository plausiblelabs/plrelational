//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension AsyncReadablePropertyType where Self.Value == Self.SignalChange {
    /// Returns an AsyncReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U>(_ transform: @escaping (Self.Value) -> U) -> AsyncReadableProperty<U> {
        return AsyncReadableProperty(signal: self.signal.map(transform))
    }
    
//    /// Returns an AsyncReadableProperty whose value is derived from the given property's `value`.
//    /// The given `transform` will be applied whenever this property's value changes, and in turn
//    /// the property returned by `transform` becomes the new source of values.
//    public func flatMap<P: AsyncReadablePropertyType>(_ transform: @escaping (Self.Value) -> P) -> AsyncReadableProperty<P.Value>
//        where P.Value == P.SignalChange
//    {
//        return FlatMappedValueProperty(property: self, transform: transform)
//    }
}

/// Returns an AsyncReadableProperty whose value is a tuple (pair) containing the `value` from
/// each of the given properties.  The returned property's `value` will contain a fresh tuple
/// any time the value of either input changes.
public func zip<LHS: AsyncReadablePropertyType, RHS: AsyncReadablePropertyType>(_ lhs: LHS, _ rhs: RHS) -> AsyncReadableProperty<(LHS.Value, RHS.Value)>
    where LHS.Value == LHS.SignalChange, RHS.Value == RHS.SignalChange
{
    return AsyncReadableProperty(signal: zip(lhs.signal, rhs.signal))
}

/// Returns an AsyncReadableProperty whose value is the negation of the boolean value of the given property.
public func not<P: AsyncReadablePropertyType>(_ property: P) -> AsyncReadableProperty<Bool>
    where P.Value == Bool, P.SignalChange == Bool
{
    return property.map{ !$0 }
}

prefix operator !

public prefix func !<P: AsyncReadablePropertyType>(property: P) -> AsyncReadableProperty<Bool>
    where P.Value == Bool, P.SignalChange == Bool
{
    return not(property)
}

//private class FlatMappedValueProperty<T>: AsyncReadableProperty<T> {
//    private let underlying: AsyncPropertyType
//    private var startFunc: (() -> Void)?
//    private var underlyingRemoval: ObserverRemoval?
//    private var mappedProperty: AsyncPropertyType?
//    private var mappedRemoval: ObserverRemoval?
//    
//    init<P: AsyncReadablePropertyType, Q: AsyncReadablePropertyType>(property: P, transform: @escaping (P.Value) -> Q)
//        where P.Value == P.SignalChange, Q.Value == Q.SignalChange, T == Q.Value
//    {
//        self.underlying = property
//        
//        let initialMappedProperty = property.value.map(transform)
//        let initialValue = initialMappedProperty?.value
//
//        let (signal, notify) = Signal<Q.Value>.pipe()
//        
//        super.init(signal: signal)
//
//        func observeMappedProperty(_ prop: Q) {
//            self.mappedProperty = prop
//            self.mappedRemoval = prop.signal.observe(SignalObserver(
//                valueWillChange: {
//                    notify.notifyBeginPossibleAsyncChange()
//                },
//                valueChanging: { mappedChange, mappedMetadata in
//                    notify.valueChanging(mappedChange, mappedMetadata)
//                },
//                valueDidChange: {
//                    notify.notifyEndPossibleAsyncChange()
//                }
//            ))
//        }
//        
//        self.startFunc = {
//            // Observe the underlying property
//            self.underlyingRemoval = property.signal.observe(SignalObserver(
//                valueWillChange: {
//                    notify.notifyBeginPossibleAsyncChange()
//                },
//                valueChanging: { [weak self] change, metadata in
//                    // Stop observing the previous mapped property
//                    // TODO: Should we stop observing earlier (in valueWillChange)?
//                    self?.mappedRemoval?()
//                    self?.mappedProperty = nil
//                    
//                    // Compute the new mapped property
//                    let mappedProperty = transform(change)
//                    
//                    // Observe the new property's signal
//                    observeMappedProperty(mappedProperty)
//                    
////                    // Deliver the mapped property's initial value, if needed
////                    if let initialValue = mappedProperty.value {
////                        notify.notifyBeginPossibleAsyncChange()
////                        notify.valueChanging(initialValue, transient: false)
////                        notify.notifyEndPossibleAsyncChange()
////                    }
//                    
////                    // Start the new property
////                    mappedProperty.start()
//                },
//                valueDidChange: {
//                    notify.notifyEndPossibleAsyncChange()
//                }
//            ))
//
////            // Start the underlying property
////            property.start()
//            
//            if let initialProperty = initialMappedProperty {
//                // Observe the initial mapped property's signal
//                observeMappedProperty(initialProperty)
//                
////                // Start the initial mapped property
////                initialProperty.start()
//            }
//        }
//    }
//
//    deinit {
//        underlyingRemoval?()
//        mappedRemoval?()
//    }
//    
////    fileprivate override func start() {
////        startFunc?()
////        startFunc = nil
////        super.start()
////    }
//}

