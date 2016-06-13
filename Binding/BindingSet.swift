//
//  BindingSet.swift
//  Relational
//
//  Created by Chris Campbell on 6/8/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation

public enum ChangeResult<T> { case
    Change(T),
    NoChange
}

public class BindingSet {
    
    private var removals: [String: ObserverRemoval] = [:]
    private var selfInitiatedChange = Set<String>()

    public init() {
    }

    /// Returns a key that can be used to identify the given observable for the purposes of detecting
    /// self-initiated changes.  A self-initiated change is detected when an observable's value is updated
    /// via the `BindingSet.update` function and that change is witnessed by the observer that was
    /// added when the observable was registered via `BindingSet.observe`.
    private func changeKey<T>(observable: ObservableValue<T>) -> String {
        // TODO: We can do better than this
        return "\(unsafeAddressOf(observable))"
    }
    
    private func observe<T>(observable: ObservableValue<T>, removalKey: String, changeKey: String, updateOnAttach: Bool, _ onValue: (T, ChangeMetadata) -> Void) {
        if updateOnAttach {
            onValue(observable.value, ChangeMetadata(transient: false))
        }
        
        let removal = observable.addChangeObserver({ [weak self] metadata in
            guard let weakSelf = self else { return }
            if weakSelf.selfInitiatedChange.contains(changeKey) { return }
            
            onValue(observable.value, metadata)
        })
        
        removals[removalKey] = removal
    }
    
    public func observe<T>(observable: ObservableValue<T>?, _ key: String, _ onValue: (T) -> Void, onDetach: () -> Void = {}) {
        if let removal = removals.removeValueForKey(key) {
            removal()
        }
        
        if let observable = observable {
            observe(observable, removalKey: key, changeKey: changeKey(observable), updateOnAttach: true, { value, _ in onValue(value) })
        } else {
            onDetach()
        }
    }
    
    private func update<T>(observable: MutableObservableValue<T>, newValue: T, metadata: ChangeMetadata, changeKey: String) {
        selfInitiatedChange.insert(changeKey)
        observable.update(newValue, metadata)
        selfInitiatedChange.remove(changeKey)
    }
    
    public func update<T>(observable: MutableObservableValue<T>?, newValue: T, transient: Bool = false) {
        guard let observable = observable else { return }
        
        let metadata = ChangeMetadata(transient: transient)
        update(observable, newValue: newValue, metadata: metadata, changeKey: changeKey(observable))
    }

    /// Sets up a bidirectional connection between the two observables.  When `observable1` changes, that change
    /// is safely propagated to `observable2`, and vice versa.
    public func connect<T1, T2>(observable1: MutableObservableValue<T1>?, _ key1: String, _ observable2: MutableObservableValue<T2>?, _ key2: String, forward: T1 -> ChangeResult<T2>, reverse: T2 -> ChangeResult<T1>) {
        // Disconnect any existing connection
        let forwardKey = "\(key1)->\(key2)"
        let reverseKey = "\(key2)->\(key1)"
        if let removal = removals.removeValueForKey(forwardKey) { removal() }
        if let removal = removals.removeValueForKey(reverseKey) { removal() }

        // No connection is possible if either observable is nil
        guard let observable1 = observable1 else { return }
        guard let observable2 = observable2 else { return }
        
        // Note that we use `updateOnAttach: true` for the forward connection only to ensure that the
        // primary observable provides its value to the secondary observable upon registration
        // TODO: Should we make this configurable?
        let changeKey = "\(self.changeKey(observable1))<->\(self.changeKey(observable2))"
        
        // Register the forward connection
        observe(observable1, removalKey: forwardKey, changeKey: changeKey, updateOnAttach: true, { [weak self] value, metadata in
            guard let weakSelf = self else { return }
            switch forward(value) {
            case .Change(let newValue):
                weakSelf.update(observable2, newValue: newValue, metadata: metadata, changeKey: changeKey)
            case .NoChange:
                break
            }
        })
        
        // Register the reverse connection
        observe(observable2, removalKey: reverseKey, changeKey: changeKey, updateOnAttach: false, { [weak self] value, metadata in
            guard let weakSelf = self else { return }
            switch reverse(value) {
            case .Change(let newValue):
                weakSelf.update(observable1, newValue: newValue, metadata: metadata, changeKey: changeKey)
            case .NoChange:
                break
            }
        })
    }
    
    deinit {
        removals.values.forEach{ $0() }
    }
}
