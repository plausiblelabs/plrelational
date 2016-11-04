//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public protocol PerThreadInstance: class {
    static var currentInstance: Self { get }
    
    init()
}

extension PerThreadInstance {
    public static var currentInstance: Self {
        let key = NSValue(nonretainedObject: self)
        if let instance = Thread.current.threadDictionary[key] as? Self {
            return instance
        } else {
            let instance = self.init()
            Thread.current.threadDictionary[key] = instance
            return instance
        }
    }
}
