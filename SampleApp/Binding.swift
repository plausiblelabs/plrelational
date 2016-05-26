//
//  Binding.swift
//  Relational
//
//  Created by Chris Campbell on 5/3/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation

public typealias ObserverRemoval = Void -> Void

public protocol Binding {
    associatedtype Value
    associatedtype Changes
    
    var value: Value { get }
    
    func addChangeObserver(observer: Changes -> Void) -> ObserverRemoval
}

public protocol BidiBinding: Binding {
    func update(newValue: Value)
    func commit(newValue: Value)
}
