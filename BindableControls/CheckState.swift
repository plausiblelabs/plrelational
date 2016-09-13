//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa

public enum CheckState: String { case
    On = "On",
    Off = "Off",
    Mixed = "Mixed"
    
    public init(_ boolValue: Bool?) {
        switch boolValue {
        case nil:
            self = .Mixed
        case .some(false):
            self = .Off
        case .some(true):
            self = .On
        }
    }
    
    init(_ nsValue: Int) {
        switch nsValue {
        case NSMixedState:
            self = .Mixed
        case NSOffState:
            self = .Off
        case NSOnState:
            self = .On
        default:
            preconditionFailure("Must be one of {NSMixedState, NSOnState, NSOffState}")
        }
    }
    
    public var boolValue: Bool {
        switch self {
        case .On:
            return true
        case .Off:
            return false
        case .Mixed:
            preconditionFailure("Cannot represent mixed state as a boolean")
        }
    }
    
    // Int value is used to set NSButton.state
    var nsValue: Int {
        switch self {
        case .On:
            return NSOnState
        case .Off:
            return NSOffState
        case .Mixed:
            return NSMixedState
        }
    }
}
