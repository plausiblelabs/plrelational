//
//  BindingSet.swift
//  Relational
//
//  Created by Chris Campbell on 6/8/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation

public class BindingSet {
    
    /// An empty class used to determine whether a change was self-initiated.
    private class ChangeKey {}
    
    private var removals: [String: ObserverRemoval] = [:]

    public init() {
    }
    
    private func register<T>(binding: ValueBinding<T>?, removalKey: String, changeKey: ChangeKey, _ onValue: (T, ChangeMetadata) -> Void, onDetach: () -> Void = {}) {
        if let removal = removals.removeValueForKey(removalKey) {
            removal()
        }
        
        if let binding = binding {
            onValue(binding.value, ChangeMetadata(transient: false))
            
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
        register(binding, removalKey: key, changeKey: ChangeKey(), { value, _ in onValue(value) }, onDetach: onDetach)
    }
    
    public func update<T>(binding: BidiValueBinding<T>?, newValue: T, transient: Bool = false) {
        guard let binding = binding else { return }
        
        // TODO: selfInitiatedChange guard
        binding.update(newValue, ChangeMetadata(transient: transient))
    }
    
    public func connect<T1, T2>(key1: String, _ binding1: BidiValueBinding<T1>?, _ key2: String, _ binding2: BidiValueBinding<T2>?, forward: (T1, ChangeMetadata) -> Void, reverse: (T2, ChangeMetadata) -> Void) {
        let changeKey = ChangeKey()
        
        // Register the forward connection
        let forwardKey = "\(key1)->\(key2)"
        register(binding1, removalKey: forwardKey, changeKey: changeKey, forward)
        
        // Register the reverse connection
        let reverseKey = "\(key2)->\(key1)"
        register(binding2, removalKey: reverseKey, changeKey: changeKey, reverse)
    }
    
    deinit {
        removals.values.forEach{ $0() }
    }
}
