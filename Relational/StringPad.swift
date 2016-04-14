
extension String {
    func pad(to length: Int, with character: Character, after: Bool = true) -> String {
        var new = self
        while new.characters.count < length {
            new.insert(character, atIndex: after ? new.endIndex : new.startIndex)
        }
        return new
    }
}
