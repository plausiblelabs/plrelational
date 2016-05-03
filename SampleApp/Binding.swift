//
//  Binding.swift
//  Relational
//
//  Created by Chris Campbell on 5/3/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational

public struct Change<T> {
    let f: (newValue: T, oldValue: T, commit: Bool) -> Void
}

public class Binding {
    
    public enum Error: ErrorType {
        case NoRows
    }

    let relation: Relation
    let attribute: Attribute
    
    init(relation: Relation, attribute: Attribute) {
        self.relation = relation
        self.attribute = attribute
    }
}

public class BidiBinding<T>: Binding {
    private let change: Change<T>
    
    init(relation: Relation, attribute: Attribute, change: Change<T>) {
        self.change = change
        super.init(relation: relation, attribute: attribute)
    }
    
    public func get() -> Result<RelationValue, RelationError> {
        return relation.rows().generate().next()?.map({ $0[attribute] }) ?? .Err(Error.NoRows)
    }
    
    public func change(newValue newValue: T, oldValue: T) {
        change.f(newValue: newValue, oldValue: oldValue, commit: false)
    }
    
    public func commit(newValue newValue: T, oldValue: T) {
        change.f(newValue: newValue, oldValue: oldValue, commit: true)
    }
}
