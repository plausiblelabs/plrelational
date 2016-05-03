//
//  Transaction.swift
//  Relational
//
//  Created by Chris Campbell on 5/3/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation

class Transaction {
    
    let name: String
    private let forward: () -> Void
    private let backward: () -> Void
    
    init(name: String, forward: () -> Void, backward: () -> Void) {
        self.name = name
        self.forward = forward
        self.backward = backward
    }
    
    func apply() {
        forward()
    }
    
    func unapply() {
        backward()
    }
}
