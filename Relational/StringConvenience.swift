
import Foundation

extension String {
    func numericLessThan(other: String) -> Bool {
        return compare(other, options: .NumericSearch, range: nil, locale: nil) == .OrderedAscending
    }
}
