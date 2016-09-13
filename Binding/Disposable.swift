//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//
// This is based in part on the `Disposable` API from ReactiveCocoa:
// https://github.com/ReactiveCocoa/ReactiveCocoa
// Copyright (c) 2014 GitHub. All rights reserved.
//

import Foundation
import libRelational

/// Represents something that can be “disposed,” usually associated with freeing
/// resources or canceling work.
public protocol Disposable: class {
    /// Whether this disposable has been disposed already.
    var disposed: Bool { get }
    
    func dispose()
}

/// A disposable that only flips `disposed` upon disposal, and performs no other
/// work.
public final class SimpleDisposable: Disposable {
    fileprivate var _disposed = Mutexed(false)
    
    public var disposed: Bool {
        return _disposed.get()
    }
    
    public init() {}
    
    public func dispose() {
        _disposed.withMutableValue{ $0 = true }
    }
}
