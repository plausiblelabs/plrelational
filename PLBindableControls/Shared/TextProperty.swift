//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import PLRelationalBinding

/// A sum type that holds either a read-only or read-write String-typed property, used for
/// binding the content of a TextField or similar control.
public enum TextProperty { case
    readOnly(ReadableProperty<String>),
    readWrite(ReadWriteProperty<String>),
    asyncReadOnly(AsyncReadableProperty<String>),
    asyncReadWrite(AsyncReadWriteProperty<String>),
    readOnlyOpt(ReadableProperty<String?>),
    readWriteOpt(ReadWriteProperty<String?>),
    asyncReadOnlyOpt(AsyncReadableProperty<String?>),
    asyncReadWriteOpt(AsyncReadWriteProperty<String?>)
    
    var editable: Bool {
        switch self {
        case .readOnly, .asyncReadOnly, .readOnlyOpt, .asyncReadOnlyOpt:
            return false
        case .readWrite, .asyncReadWrite, .readWriteOpt, .asyncReadWriteOpt:
            return true
        }
    }
}

#if os(macOS)
extension TextField {
    public func bind(_ property: TextProperty?) {
        string.unbindAll()
        optString.unbindAll()
        if let property = property {
            switch property {
            case .readOnly(let text):
                string <~ text
            case .readWrite(let text):
                string <~> text
            case .asyncReadOnly(let text):
                string <~ text
            case .asyncReadWrite(let text):
                string <~> text
            case .readOnlyOpt(let text):
                optString <~ text
            case .readWriteOpt(let text):
                optString <~> text
            case .asyncReadOnlyOpt(let text):
                optString <~ text
            case .asyncReadWriteOpt(let text):
                optString <~> text
            }
            isEditable = property.editable
        } else {
            isEditable = false
        }
    }
}
#endif
