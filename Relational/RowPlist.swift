//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


extension Row {
    static func fromPlist(plist: AnyObject) -> Result<Row, RelationError> {
        guard let dict = plist as? NSDictionary else { return .Err(RowPlistError.UnknownRowObject(unknownObject: plist)) }
        
        var values: [Attribute: RelationValue] = [:]
        for (attributeName, valuePlist) in dict {
            switch RelationValue.fromPlist(valuePlist) {
            case .Ok(let value): values[Attribute(attributeName as! String)] = value
            case .Err(let err): return .Err(err)
            }
        }
        return .Ok(Row(values: values))
    }
    
    func toPlist() -> AnyObject {
        let result = NSMutableDictionary()
        for (attribute, value) in self {
            result[attribute.name] = value.toPlist()
        }
        return result
    }
}

extension RelationValue {
    // RelationValues don't quite match up with plist values, so there needs to be a little encoding.
    //
    // NULL is encoded as an empty array.
    // Integers and Reals are encoded as two-element arrays where the first element is "integer" or
    //     "real" and the second element is the number. (Plists support NSNumber but don't guarantee
    //     that the type will be preserved, so if we want to be sure of getting an Integer out when
    //     we put an Integer in, we have to do this.)
    // Strings are encoded as strings.
    // Blobs are encoded as data.
    static func fromPlist(plist: AnyObject) -> Result<RelationValue, RelationError> {
        switch plist {
            
        case let array as NSArray where array.count == 0: return .Ok(.NULL)
            
        case let array as NSArray where array.count == 2:
            switch array[0] as? NSString {
            case .Some("integer"): return .Ok(.Integer(array[1].longLongValue))
            case .Some("real"): return .Ok(.Real(array[1].doubleValue))
            default: return .Err(RowPlistError.UnknownNumericTag(unknownTag: array[0]))
            }
            
        case let string as NSString:
            return .Ok(.Text(string as String))
        
        case let data as NSData:
            let buffer = UnsafeBufferPointer(start: UnsafePointer<UInt8>(data.bytes), count: data.length)
            return .Ok(.Blob(Array(buffer)))
            
        default:
            return .Err(RowPlistError.UnknownValueObject(unknownObject: plist))
        }
    }
    
    func toPlist() -> AnyObject {
        switch self {
        case .NULL: return [] as NSArray
        case .Integer(let value): return ["integer", NSNumber(longLong: value)] as NSArray
        case .Real(let value): return ["real", NSNumber(double: value)] as NSArray
        case .Text(let value): return value as NSString
        case .Blob(let value): return NSData(bytes: value, length: value.count)
            
        case .NotFound: preconditionFailure("Can't convert RelationValue.NotFound to a plist value")
        }
    }
}

enum RowPlistError: ErrorType {
    case UnknownRowObject(unknownObject: AnyObject)
    
    case UnknownNumericTag(unknownTag: AnyObject)
    case UnknownValueObject(unknownObject: AnyObject)
}
