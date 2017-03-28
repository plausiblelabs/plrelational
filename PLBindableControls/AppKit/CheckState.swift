//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

public enum CheckState: String { case
    on = "On",
    off = "Off",
    mixed = "Mixed"
    
    public init(_ boolValue: Bool?) {
        switch boolValue {
        case nil:
            self = .mixed
        case .some(false):
            self = .off
        case .some(true):
            self = .on
        }
    }

    public init(commonValue: CommonValue<Bool>) {
        switch commonValue {
        case .none:
            self = .off
        case .one(let b):
            self = b ? .on : .off
        case .multi:
            self = .mixed
        }
    }
    
    init(_ nsValue: Int) {
        switch nsValue {
        case NSMixedState:
            self = .mixed
        case NSOffState:
            self = .off
        case NSOnState:
            self = .on
        default:
            preconditionFailure("Must be one of {NSMixedState, NSOnState, NSOffState}")
        }
    }
    
    public var boolValue: Bool {
        switch self {
        case .on:
            return true
        case .off:
            return false
        case .mixed:
            preconditionFailure("Cannot represent mixed state as a boolean")
        }
    }
    
    public var commonValue: CommonValue<Bool> {
        switch self {
        case .on:
            return .one(true)
        case .off:
            return .one(false)
        case .mixed:
            return .multi
        }
    }
    
    /// The Cocoa-defined integer value that corresponds to this CheckState (NSOnState, NSOffState, or NSMixedState).
    public var nsValue: Int {
        switch self {
        case .on:
            return NSOnState
        case .off:
            return NSOffState
        case .mixed:
            return NSMixedState
        }
    }
}
