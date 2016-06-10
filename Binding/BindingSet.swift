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
    
    private func register<T>(binding: ValueBinding<T>?, removalKey: String, changeKey: String, _ onValue: (T) -> Void, onDetach: () -> Void = {}) {
        if let removal = removals.removeValueForKey(removalKey) {
            removal()
        }
        
        if let binding = binding {
            onValue(binding.value)
            
            let removal = binding.addChangeObserver({ [weak self] in
                guard let weakSelf = self else { return }
                if weakSelf.selfInitiatedChange.contains(changeKey) { return }

                weakSelf.selfInitiatedChange.insert(changeKey)
                onValue(binding.value)
                weakSelf.selfInitiatedChange.remove(changeKey)
            })
            
            removals[removalKey] = removal
        } else {
            onDetach()
        }
    }
    
    public func register<T>(key: String, _ binding: ValueBinding<T>?, _ onValue: (T) -> Void, onDetach: () -> Void = {}) {
        // TODO: changeKey is fairly useless in this non-bidi case
        register(binding, removalKey: key, changeKey: key, onValue, onDetach: onDetach)
    }
    
    public func connect<T1, T2>(key1: String, _ binding1: BidiValueBinding<T1>?, _ key2: String, _ binding2: BidiValueBinding<T2>?, forward: T1 -> Void, reverse: T2 -> Void) {
        let changeKey = "\(key1)<->\(key2)"
        
        // Register the forward connection
        let forwardKey = "\(key1)->\(key2)"
        register(binding1, removalKey: forwardKey, changeKey: changeKey, { value in
            forward(value)
        })
        
        // Register the reverse connection
        let reverseKey = "\(key2)->\(key1)"
        register(binding2, removalKey: reverseKey, changeKey: changeKey, { value in
            reverse(value)
        })
    }
    
    deinit {
        removals.values.forEach{ $0() }
    }
}
