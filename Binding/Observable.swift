//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public typealias ObserverRemoval = Void -> Void

public protocol Observable {
    associatedtype Value
    associatedtype Changes
    associatedtype ChangeObserver = Changes -> Void
    
    var value: Value { get }
    
    func addChangeObserver(observer: ChangeObserver) -> ObserverRemoval
}
