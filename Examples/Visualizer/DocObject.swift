//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// Represents an item that exists in the document outline.
struct DocObject {
    let docItemID: DocItemID
    let objectID: ObjectID
    let type: ItemType
    
    /// Create a DocObject whose docItemID and objectID have the same underlying value.
    init(_ type: ItemType) {
        self.docItemID = DocItemID()
        self.objectID = ObjectID(docItemID.stringValue)
        self.type = type
    }
    
    /// Create a DocObject that uses the given identifiers.
    init(docItemID: DocItemID, objectID: ObjectID, type: ItemType) {
        self.docItemID = docItemID
        self.objectID = objectID
        self.type = type
    }
}

extension DocObject: Equatable {}
func ==(a: DocObject, b: DocObject) -> Bool {
    return a.docItemID == b.docItemID
}
