//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

extension String {
    func pad(to length: Int, with character: Character, after: Bool = true) -> String {
        var new = self
        while new.characters.count < length {
            new.insert(character, at: after ? new.endIndex : new.startIndex)
        }
        return new
    }
}
