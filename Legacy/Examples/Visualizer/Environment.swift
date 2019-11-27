//
// Copyright (c) 2015 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import SystemConfiguration

final class Environment {
    
    static func computerName() -> String {
        if let cfstring = SCDynamicStoreCopyComputerName(nil, nil) {
            return (cfstring as NSString) as String
        } else {
            return "Unknown"
        }
    }
    
    static func fullUserName() -> String {
        return NSFullUserName()
    }
}
