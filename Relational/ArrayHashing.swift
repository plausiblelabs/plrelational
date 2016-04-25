
extension Array where Element: Hashable {
    /// Generate a hash value from the hash values of the array elements.
    /// Currently just XORs them all. Do we want something smarter?
    var hashValueFromElements: Int {
        return reduce(0, combine: { $0 ^ $1.hashValue })
    }
}
