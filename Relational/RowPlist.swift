//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


extension Row {
    static func fromPlist(_ plist: Any) -> Result<Row, RelationError> {
        guard let dict = plist as? NSDictionary else { return .Err(RowPlistError.unknownRowObject(unknownObject: plist)) }
        
        var values: [Attribute: RelationValue] = [:]
        for (attributeName, valuePlist) in dict {
            switch RelationValue.fromPlist(valuePlist) {
            case .Ok(let value): values[Attribute(attributeName as! String)] = value
            case .Err(let err): return .Err(err)
            }
        }
        return .Ok(Row(values: values))
    }
    
    func toPlist() -> Any {
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
    static func fromPlist(_ plist: Any) -> Result<RelationValue, RelationError> {
        switch plist {
            
        case let array as NSArray where array.count == 0: return .Ok(.null)
            
        case let array as NSArray where array.count == 2:
            switch array[0] as? NSString {
            case .some("integer"): return .Ok(.integer((array[1] as AnyObject).int64Value))
            case .some("real"): return .Ok(.real((array[1] as AnyObject).doubleValue))
            default: return .Err(RowPlistError.unknownNumericTag(unknownTag: array[0]))
            }
            
        case let string as NSString:
            return .Ok(.text(string as String))
        
        case let data as Data:
            let buffer = UnsafeBufferPointer(start: (data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count), count: data.count)
            return .Ok(.blob(Array(buffer)))
            
        default:
            return .Err(RowPlistError.unknownValueObject(unknownObject: plist))
        }
    }
    
    func toPlist() -> Any {
        switch self {
        case .null: return [] as NSArray
        case .integer(let value): return ["integer", NSNumber(value: value as Int64)] as NSArray
        case .real(let value): return ["real", NSNumber(value: value as Double)] as NSArray
        case .text(let value): return value as NSString
        case .blob(let value): return Data(bytes: UnsafePointer<UInt8>(value), count: value.count)
            
        case .notFound: preconditionFailure("Can't convert RelationValue.NotFound to a plist value")
        }
    }
}

enum RowPlistError: Error {
    case unknownRowObject(unknownObject: Any)
    
    case unknownNumericTag(unknownTag: Any)
    case unknownValueObject(unknownObject: Any)
}
