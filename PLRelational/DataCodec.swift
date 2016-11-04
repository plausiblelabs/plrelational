//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public protocol DataCodec {
    func encode(_ data: Data) -> Result<Data, RelationError>
    func decode(_ data: Data) -> Result<Data, RelationError>
}
