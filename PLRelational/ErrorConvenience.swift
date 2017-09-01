//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension Error {
    var isFileNotFound: Bool {
        // NSData throws NSFileReadNoSuchFileError when the file doesn't exist. It doesn't seem to be documented
        // but given that it's an official Cocoa constant it seems safe enough.
        let codes = [NSFileNoSuchFileError, NSFileReadNoSuchFileError]
        return (self as NSError).domain == NSCocoaErrorDomain && codes.contains((self as NSError).code)
    }
}

extension NSError {
    static var fileNotFound: NSError {
        return NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: nil)
    }
}
