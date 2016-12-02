//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public enum CommonValue<T: Equatable>: Equatable { case
    /// The value is not defined for any item.
    none,
    
    /// The value is the same for all items.
    one(T),
    
    /// There is a mixed set of values across all items.
    multi
    
    /// Returns the single value if there is one, or the given default value in the .None or .Multi cases.
    public func orDefault(_ defaultValue: T) -> T {
        switch self {
        case .none, .multi:
            return defaultValue
        case .one(let value):
            return value
        }
    }
    
    /// Returns the single value if there is one, or nil in the .None or .Multi cases.
    public func orNil() -> T? {
        switch self {
        case .none, .multi:
            return nil
        case .one(let value):
            return value
        }
    }
    
    /// Returns the given value in the .Multi case, otherwise returns nil.
    public func whenMulti<U>(_ value: U) -> U? {
        switch self {
        case .none, .one:
            return nil
        case .multi:
            return value
        }
    }
    
    /// Returns the given value in the .Multi case, otherwise returns the alternate value.
    public func whenMulti<U>(_ value: U, otherwise: U) -> U {
        switch self {
        case .none, .one:
            return otherwise
        case .multi:
            return value
        }
    }
}

public func ==<T>(a: CommonValue<T>, b: CommonValue<T>) -> Bool {
    switch (a, b) {
    case (.none, .none):
        return true
    case let (.one(avalue), .one(bvalue)):
        return avalue == bvalue
    case (.multi, .multi):
        return true
    default:
        return false
    }
}

extension CommonValue { // where T: Equatable {
    /// Returns true if all items share the given value.
    public func all(_ value: T) -> Bool {
        switch self {
        case let .one(v):
            return v == value
        default:
            return false
        }
    }
}

extension CommonValue {
    /// Returns the CommonValue that would result if the given value was added to the current one.
    public func adding(_ value: T) -> CommonValue<T> {
        switch self {
        case .none:
            return .one(value)
        case .one(let v):
            if v == value {
                return self
            } else {
                return .multi
            }
        case .multi:
            return self
        }
    }
}
