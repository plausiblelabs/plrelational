//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


/// :nodoc: Implementation detail (will be made non-public eventually)
extension URL {
    public var isDirectory: Result<Bool, NSError> {
        do {
            let values = try resourceValues(forKeys: [.isDirectoryKey])
            return .Ok(values.isDirectory ?? false)
        } catch let error as NSError {
            return .Err(error)
        }
    }
}
