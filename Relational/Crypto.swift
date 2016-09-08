//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import CommonCrypto

public func SHA256(data: [UInt8]) -> [UInt8] {
    var output: [UInt8] = Array(count: Int(CC_SHA256_DIGEST_LENGTH), repeatedValue: 0)
    CC_SHA256(data, CC_LONG(data.count), &output)
    return output
}

public func hexString(data: [UInt8], uppercase: Bool) -> String {
    struct Static {
        static let hexCharsUpper: [Character] = [ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]
        static let hexCharsLower: [Character] = [ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
    }
    
    let chars = uppercase ? Static.hexCharsUpper : Static.hexCharsLower
    
    var output = String()
    output.reserveCapacity(data.count * 2)
    
    for byte in data {
        let upperNibble = byte >> 4
        let lowerNibble = byte & 0xf
        
        for nibble in [upperNibble, lowerNibble] {
            output.append(chars[Int(nibble)])
        }
    }
    
    return output
}
