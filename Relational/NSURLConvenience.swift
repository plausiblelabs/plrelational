//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


extension NSURL {
    public var isDirectory: Result<Bool, NSError> {
        do {
            var resourceValue: AnyObject?
            try getResourceValue(&resourceValue, forKey: NSURLIsDirectoryKey)
            return .Ok(resourceValue?.boolValue ?? false)
        } catch let error as NSError {
            return .Err(error)
        }
    }
}
