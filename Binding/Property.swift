//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public class Property<T> {

    private let onValue: T -> Void
    private var removal: ObserverRemoval?
    
    public init(_ onValue: T -> Void) {
        self.onValue = onValue
    }

    deinit {
        removal?()
    }
    
    public func bind(observable: ObservableValue<T>) {
        unbind()
        
        self.onValue(observable.value)
    
        self.removal = observable.addChangeObserver({ [weak self] metadata in
            guard let weakSelf = self else { return }
            //if weakSelf.selfInitiatedChange.contains(changeKey) { return }
            weakSelf.onValue(observable.value)
        })
    }
    
    public func unbind() {
        removal?()
        removal = nil
    }
}

// This syntax is borrowed from ReactiveCocoa.
infix operator <~ {
    associativity right
    precedence 93
}

public func <~ <T>(property: Property<T>, observable: ObservableValue<T>?) {
    if let observable = observable {
        property.bind(observable)
    } else {
        property.unbind()
    }
}
