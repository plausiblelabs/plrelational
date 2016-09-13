//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Binding

/// A sum type that holds either a read-only property or a read-write property, used for
/// binding a list/tree cell text property.
public enum CellTextProperty { case
    readOnly(ReadableProperty<String>),
    readWrite(ReadWriteProperty<String>),
    asyncReadOnly(AsyncReadableProperty<String>),
    asyncReadWrite(AsyncReadWriteProperty<String>)
}
