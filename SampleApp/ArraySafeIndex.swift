//
// Copyright (c) 2015 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

extension Array {
    subscript(safe index: Int) -> Element? {
        return (index >= 0 && index < self.count)
            ? self[index]
            : nil
    }
}
