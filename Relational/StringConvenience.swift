//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension String {
    func numericLessThan(_ other: String) -> Bool {
        return compare(other, options: .numeric, range: nil, locale: nil) == .orderedAscending
    }
}
