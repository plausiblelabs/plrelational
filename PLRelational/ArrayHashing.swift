//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

extension Array where Element: Hashable {
    /// Generate a hash value from the hash values of the array elements.
    var hashValueFromElements: Int {
        var hash = DJBHash()
        for element in self {
            hash.combine(element.hashValue)
        }
        return hash.value
    }
}
