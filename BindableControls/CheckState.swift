//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa

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
    
    // Int value is used to set NSButton.state
    var nsValue: Int {
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
