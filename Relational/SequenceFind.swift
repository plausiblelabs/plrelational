
extension SequenceType {
    func find(predicate: Generator.Element -> Bool) -> Generator.Element? {
        for element in self {
            if predicate(element) {
                return element
            }
        }
        return nil
    }
}
