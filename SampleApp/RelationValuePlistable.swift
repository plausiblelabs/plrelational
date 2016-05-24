//
//  RelationValuePlistable.swift
//  Relational
//
//  Created by Chris Campbell on 5/23/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational

public protocol Plistable {
    func toPlist() -> AnyObject
    static func fromPlist(obj: AnyObject) -> Self?
}

extension RelationValue: Plistable {
    public func toPlist() -> AnyObject {
        switch self {
        case let Integer(value):
            return ["type": "integer", "value": value.description]
        case let Text(value):
            return ["type": "text", "value": value]
        default:
            // TODO: Support other types
            return [:]
        }
    }
    
    public static func fromPlist(obj: AnyObject) -> RelationValue? {
        if let plist = obj as? [String: String] {
            if let type = plist["type"], stringValue = plist["value"] {
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