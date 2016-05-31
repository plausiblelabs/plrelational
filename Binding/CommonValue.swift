//
//  CommonValue.swift
//  Relational
//
//  Created by Chris Campbell on 5/21/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation

public enum CommonValue<T> { case
    /// The value is not defined for any item.
    None,
    
    /// The value is the same for all items.
    One(T),
    
    /// There is a mixed set of values across all items.
    Multi
    
    /// Returns the single value if there is one, or the given default value in the .None or .Multi cases.
    public func orDefault(defaultValue: T) -> T {
        switch self {
        case .None, .Multi:
            return defaultValue
        case .One(let value):
            return value
        }
    }
    
    /// Returns the single value if there is one, or nil in the .None or .Multi cases.
    public func orNil() -> T? {
        switch self {
        case .None, .Multi:
            return nil
        case .One(let value):
            return value
        }
    }
    
    /// Returns the given value in the .Multi case, otherwise returns nil.
    public func whenMulti<U>(value: U) -> U? {
        switch self {
        case .None, .One:
            return nil
        case .Multi:
            return value
        }
    }
}

extension CommonValue where T: Equatable {
    /// Returns true if all items share the given value.
    public func all(value: T) -> Bool {
        switch self {
        case let .One(v):
            return v == value
        default:
            return false
        }
    }
}
