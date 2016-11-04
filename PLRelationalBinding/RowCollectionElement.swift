//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

public class RowCollectionElement: CollectionElement {
    public typealias ID = RelationValue
    public typealias Data = Row
    
    public let id: RelationValue
    public var data: Row
    public let tag: AnyObject?
    
    init(id: RelationValue, data: Row, tag: AnyObject?) {
        self.id = id
        self.data = data
        self.tag = tag
    }
}
