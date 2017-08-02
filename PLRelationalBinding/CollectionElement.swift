//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public protocol CollectionElement: class {
    associatedtype ID: Hashable, Plistable
    associatedtype Data
    
    var id: ID { get }
    var data: Data { get set }
}
