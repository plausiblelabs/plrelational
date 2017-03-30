//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

// The following is based on ReactiveSwift's ReactiveExtensionProvider protocol and Reactive proxy concepts.

/// A provider of binding extensions.
public protocol BindingExtensionsProvider: class {
}

/// A proxy that hosts binding extensions of `Base`.
public struct Bindable<Base> {
    /// The `Base` instance used to invoke the extensions.
    public let base: Base
    
    fileprivate init(_ base: Base) {
        self.base = base
    }
}

extension BindingExtensionsProvider {
    /// A proxy that hosts binding extensions for `self`.
    public var bindable: Bindable<Self> {
        return Bindable(self)
    }
    
    /// A proxy that hosts static binding extensions for the type of `self`.
    public static var bindable: Bindable<Self>.Type {
        return Bindable<Self>.self
    }
}

// TODO: Eventually we should move Bindable and BindingExtensionsProvider to PLRelationalBinding, and then define
// this NSObject extension in PLBindableControls.
extension NSObject: BindingExtensionsProvider {
}
