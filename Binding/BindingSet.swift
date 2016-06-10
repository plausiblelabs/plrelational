//
//  BindingSet.swift
//  Relational
//
//  Created by Chris Campbell on 6/8/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation

public class BindingSet {
    private var removals: [String: ObserverRemoval] = [:]
    private var selfInitiatedChange = Set<String>()

    public init() {
    }
    
    public func register<T>(key: String, _ binding: ValueBinding<T>?, _ onValue: (T) -> Void, onDetach: () -> Void = {}) {
        if let removal = removals.removeValueForKey(key) {
            removal()
        }
        
        if let binding = binding {
            onValue(binding.value)
            
            let removal = binding.addChangeObserver({
                onValue(binding.value)
            })
            
            removals[key] = removal
        } else {
            onDetach()
        }
    }
    
    public func connect<T1, T2>(key1: String, _ binding1: BidiValueBinding<T1>?, _ key2: String, _ binding2: BidiValueBinding<T2>?, forward: T1 -> Void, reverse: T2 -> Void) {
        // Deregister existing connection
        let forwardKey = "\(key1)->\(key2)"
        let reverseKey = "\(key2)->\(key1)"
        let changeFlagKey = "\(key1)<->\(key2)"
        if let removal = removals.removeValueForKey(forwardKey) { removal() }
        if let removal = removals.removeValueForKey(reverseKey) { removal() }
        selfInitiatedChange.remove(changeFlagKey)
        
        // No connection possible if either binding is nil
        guard let binding1 = binding1 else { return }
        guard let binding2 = binding2 else { return }
        
        // Register the forward connection
        register(forwardKey, binding1, { [weak self] value in
            guard let weakSelf = self else { print("FOO1"); return }
            if weakSelf.selfInitiatedChange.contains(changeFlagKey) { print("WAT1"); return }
            print("CHANGE FOR \(forwardKey): \(value)")
            
            weakSelf.selfInitiatedChange.insert(changeFlagKey)
            forward(value)
            weakSelf.selfInitiatedChange.remove(changeFlagKey)
        })
        
        // Register the reverse connection
        register(reverseKey, binding2, { [weak self] value in
            guard let weakSelf = self else { print("FOO2"); return }
            if weakSelf.selfInitiatedChange.contains(changeFlagKey) { print("WAT2"); return }
            print("CHANGE FOR \(reverseKey): \(value)")
            
            weakSelf.selfInitiatedChange.insert(changeFlagKey)
            reverse(value)
            weakSelf.selfInitiatedChange.remove(changeFlagKey)
        })
    }
    
    deinit {
        removals.values.forEach{ $0() }
    }
}
