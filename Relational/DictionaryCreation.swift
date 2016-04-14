
extension Dictionary {
    init<S: SequenceType where S.Generator.Element == (Key, Value)>(_ seq: S) {
        self.init()
        for (k, v) in seq {
            self[k] = v
        }
    }
}
