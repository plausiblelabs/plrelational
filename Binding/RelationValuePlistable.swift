//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

public protocol Plistable {
    func toPlist() -> AnyObject
    static func fromPlist(_ obj: AnyObject) -> Self?
}

extension RelationValue: Plistable {
    public func toPlist() -> AnyObject {
        switch self {
        case let .integer(value):
            return ["type": "integer", "value": value.description] as NSDictionary
        case let .text(value):
            return ["type": "text", "value": value] as NSDictionary
        default:
            // TODO: Support other types
            return [:] as NSDictionary
        }
    }
    
    public static func fromPlist(_ obj: AnyObject) -> RelationValue? {
        if let plist = obj as? [String: String] {
            if let type = plist["type"], let stringValue = plist["value"] {
                switch type {
                case "integer":
                    if let v = Int64(stringValue) {
                        return RelationValue(v)
                    } else {
                        return nil
                    }
                case "text":
                    return RelationValue(stringValue)
                default:
                    return nil
                }
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
}
