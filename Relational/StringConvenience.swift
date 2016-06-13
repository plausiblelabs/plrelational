//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension String {
    func numericLessThan(other: String) -> Bool {
        return compare(other, options: .NumericSearch, range: nil, locale: nil) == .OrderedAscending
    }
}
