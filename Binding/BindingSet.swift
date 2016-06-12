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

    /// Returns a key that can be used to identify the given binding for the purposes of detecting
    /// self-initiated changes.  A self-initiated change is detected when a binding's value is updated
    /// via the `BindingSet.update` function and that change is witnessed by the observer that was
    /// added when the binding was `register`ed.
    private func changeKey<T>(binding: ValueBinding<T>) -> String {
        // TODO: We can do better than this
        return "\(unsafeAddressOf(binding))"
    }
    
    private func register<T>(binding: ValueBinding<T>, removalKey: String, changeKey: String, updateOnAttach: Bool, _ onValue: (T, ChangeMetadata) -> Void) {
        if updateOnAttach {
            onValue(binding.value, ChangeMetadata(transient: false))
        }
        
        let removal = binding.addChangeObserver({ [weak self] metadata in
            guard let weakSelf = self else { return }
            if weakSelf.selfInitiatedChange.contains(changeKey) { return }
            
            onValue(binding.value, metadata)
        })
        
        removals[removalKey] = removal
    }
    
    public func register<T>(key: String, _ binding: ValueBinding<T>?, _ onValue: (T) -> Void, onDetach: () -> Void = {}) {
        if let removal = removals.removeValueForKey(key) {
            removal()
        }
        
        if let binding = binding {
            register(binding, removalKey: key, changeKey: changeKey(binding), updateOnAttach: true, { value, _ in onValue(value) })
        } else {
            onDetach()
        }
    }
    
    private func update<T>(binding: BidiValueBinding<T>, newValue: T, metadata: ChangeMetadata, changeKey: String) {
        selfInitiatedChange.insert(changeKey)
        binding.update(newValue, metadata)
        selfInitiatedChange.remove(changeKey)
    }
    
    public func update<T>(binding: BidiValueBinding<T>?, newValue: T, transient: Bool = false) {
        guard let binding = binding else { return }
        
        let metadata = ChangeMetadata(transient: transient)
        update(binding, newValue: newValue, metadata: metadata, changeKey: changeKey(binding))
    }
    
    public func connect<T1, T2>(key1: String, _ binding1: BidiValueBinding<T1>?, _ key2: String, _ binding2: BidiValueBinding<T2>?, forward: T1 -> ChangeResult<T2>, reverse: T2 -> ChangeResult<T1>) {
        // Disconnect any existing bindings
        let forwardKey = "\(key1)->\(key2)"
        let reverseKey = "\(key2)->\(key1)"
        if let removal = removals.removeValueForKey(forwardKey) { removal() }
        if let removal = removals.removeValueForKey(reverseKey) { removal() }

        // No connection is possible if either binding is nil
        guard let binding1 = binding1 else { return }
        guard let binding2 = binding2 else { return }
        
        // Note that we use `updateOnAttach: true` for the forward connection only to ensure that the
        // primary binding provides its value to the secondary binding upon registration
        // TODO: Should we make this configurable?
        let changeKey = "\(self.changeKey(binding1))<->\(self.changeKey(binding2))"
        
        // Register the forward connection
        register(binding1, removalKey: forwardKey, changeKey: changeKey, updateOnAttach: true, { [weak self] value, metadata in
            guard let weakSelf = self else { return }
            switch forward(value) {
            case .Change(let newValue):
                weakSelf.update(binding2, newValue: newValue, metadata: metadata, changeKey: changeKey)
            case .NoChange:
                break
            }
        })
        
        // Register the reverse connection
        register(binding2, removalKey: reverseKey, changeKey: changeKey, updateOnAttach: false, { [weak self] value, metadata in
            guard let weakSelf = self else { return }
            switch reverse(value) {
            case .Change(let newValue):
                weakSelf.update(binding1, newValue: newValue, metadata: metadata, changeKey: changeKey)
            case .NoChange:
                break
            }
        })
    }
    
    deinit {
        removals.values.forEach{ $0() }
    }
}
