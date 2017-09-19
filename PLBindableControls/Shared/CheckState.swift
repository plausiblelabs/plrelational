//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

#if os(macOS)
import Cocoa
#endif
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
    
#if os(macOS)
    public init(_ nsValue: Int) {
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
#endif
    
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
    
#if os(macOS)
    /// The Cocoa-defined integer value that corresponds to this CheckState (NSOnState, NSOffState, or NSMixedState).
    public var nsValue: Int {
        switch self {
        case .on:
            return NSOnState.rawValue
        case .off:
            return NSOffState.rawValue
        case .mixed:
            return NSMixedState.rawValue
        }
    }
#endif
}
