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

    public init() {
    }
    
    private func register<T>(binding: ValueBinding<T>?, removalKey: String, updateOnAttach: Bool, _ onValue: (T, ChangeMetadata) -> Void, onDetach: () -> Void = {}) {
        if let removal = removals.removeValueForKey(removalKey) {
            removal()
        }
        
        if let binding = binding {
            if updateOnAttach {
                onValue(binding.value, ChangeMetadata(transient: false))
            }
            
            let removal = binding.addChangeObserver({ metadata in
                // TODO: selfInitiatedChange guard
                onValue(binding.value, metadata)
            })
            
            removals[removalKey] = removal
        } else {
            onDetach()
        }
    }
    
    public func register<T>(key: String, _ binding: ValueBinding<T>?, _ onValue: (T) -> Void, onDetach: () -> Void = {}) {
        register(binding, removalKey: key, updateOnAttach: true, { value, _ in onValue(value) }, onDetach: onDetach)
    }
    
    public func update<T>(binding: BidiValueBinding<T>?, newValue: T, transient: Bool = false) {
        guard let binding = binding else { return }
        
        // TODO: selfInitiatedChange guard
        binding.update(newValue, ChangeMetadata(transient: transient))
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
        // primary binding provides its value to the secondary binding upon registration.
        // TODO: Should we make this configurable?
        
        // Register the forward connection
        register(binding1, removalKey: forwardKey, updateOnAttach: true, { value, metadata in
            switch forward(value) {
            case .Change(let newValue):
                binding2.update(newValue, metadata)
            case .NoChange:
                break
            }
        })
        
        // Register the reverse connection
        register(binding2, removalKey: reverseKey, updateOnAttach: false, { value, metadata in
            switch reverse(value) {
            case .Change(let newValue):
                binding1.update(newValue, metadata)
            case .NoChange:
                break
            }
        })
    }
    
    deinit {
        removals.values.forEach{ $0() }
    }
}
