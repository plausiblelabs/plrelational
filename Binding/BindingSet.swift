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
    
    deinit {
        removals.values.forEach{ $0() }
    }
}
