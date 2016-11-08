//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

// TODO: Return Result instead of Optional for fromPlist() funcs

enum SharedRelationSource {
    case previous
    case reference(ObjectID)
    
    func toPlist() -> Any {
        let dict = NSMutableDictionary()
        switch self {
        case .previous:
            dict["previous"] = true
        case .reference(let objectID):
            dict["reference"] = objectID.stringValue
        }
        return dict
    }
    
    static func fromPlist(_ plist: Any) -> SharedRelationSource? {
        guard let dict = plist as? NSDictionary else { return nil }
        
        if dict["previous"] != nil {
            return .previous
        } else if let refID = dict["reference"] as? String {
            return .reference(ObjectID(refID))
        } else {
            return nil
        }
    }
}

struct SharedRelationAtom {
    let source: SharedRelationSource
    let projection: [Attribute]?
    
    func toPlist() -> Any {
        let dict = NSMutableDictionary()
        dict["source"] = source.toPlist()
        if let projectedAttrs = projection {
            let attrNames = projectedAttrs.map{ $0.name }
            dict["projectedAttrs"] = attrNames
        }
        return dict
    }
    
    static func fromPlist(_ plist: Any) -> SharedRelationAtom? {
        guard let dict = plist as? NSDictionary else { return nil }
        
        guard let sourceDict = dict["source"] as? NSDictionary else { return nil }
        guard let source = SharedRelationSource.fromPlist(sourceDict) else { return nil }
        
        let projection: [Attribute]?
        if let attrNames = dict["projectedAttrs"] as? [String] {
            projection = attrNames.map{ Attribute($0) }
        } else {
            projection = nil
        }
        
        return SharedRelationAtom(
            source: source,
            projection: projection
        )
    }
}

enum SharedRelationUnaryOp {
    // TODO: Generalize this (different comparison ops, different value types)
    case selectEq(Attribute, String)
    case count

    func toPlist() -> Any {
        let dict = NSMutableDictionary()
        switch self {
        case let .selectEq(attr, value):
            dict["selectEq"] = [
                "attribute": attr.name,
                "value": value
            ]
        case .count:
            dict["count"] = true
        }
        return dict
    }
    
    static func fromPlist(_ plist: Any) -> SharedRelationUnaryOp? {
        guard let dict = plist as? NSDictionary else { return nil }
        
        if let selectEqDict = dict["selectEq"] as? NSDictionary {
            guard let attrName = selectEqDict["attribute"] as? String else { return nil }
            guard let value = selectEqDict["value"] as? String else { return nil }
            return .selectEq(Attribute(attrName), value)
        } else if dict["count"] != nil {
            return .count
        } else {
            return nil
        }
    }
}

enum SharedRelationBinaryOp {
    case join(SharedRelationAtom)
    case union(SharedRelationAtom)
    
    var atom: SharedRelationAtom {
        switch self {
        case .join(let a): return a
        case .union(let a): return a
        }
    }
    
    func toPlist() -> Any {
        let dict = NSMutableDictionary()
        switch self {
        case .join(let atom):
            dict["join"] = atom.toPlist()
        case .union(let atom):
            dict["union"] = atom.toPlist()
        }
        return dict
    }
    
    static func fromPlist(_ plist: Any) -> SharedRelationBinaryOp? {
        guard let dict = plist as? NSDictionary else { return nil }
        
        if let atomDict = dict["join"] as? NSDictionary {
            return SharedRelationAtom.fromPlist(atomDict).map{ .join($0) }
        } else if let atomDict = dict["union"] as? NSDictionary {
            return SharedRelationAtom.fromPlist(atomDict).map{ .union($0) }
        } else {
            return nil
        }
    }
}

enum SharedRelationOp {
    case filter(SharedRelationUnaryOp)
    case combine(SharedRelationBinaryOp)
    
    func toPlist() -> Any {
        let dict = NSMutableDictionary()
        switch self {
        case .filter(let op):
            dict["filter"] = op.toPlist()
        case .combine(let op):
            dict["combine"] = op.toPlist()
        }
        return dict
    }
    
    static func fromPlist(_ plist: Any) -> SharedRelationOp? {
        guard let dict = plist as? NSDictionary else { return nil }
        
        if let unaryDict = dict["filter"] as? NSDictionary {
            return SharedRelationUnaryOp.fromPlist(unaryDict).map{ .filter($0) }
        } else if let binaryDict = dict["combine"] as? NSDictionary {
            return SharedRelationBinaryOp.fromPlist(binaryDict).map{ .combine($0) }
        } else {
            return nil
        }
    }
}

struct SharedRelationElement {
    let atom: SharedRelationAtom
    let op: SharedRelationOp?
    
    func toPlist() -> Any {
        let dict = NSMutableDictionary()
        dict["atom"] = atom.toPlist()
        if let op = op {
            dict["op"] = op.toPlist()
        }
        return dict
    }
    
    static func fromPlist(_ plist: Any) -> SharedRelationElement? {
        guard let dict = plist as? NSDictionary else { return nil }
        
        guard let atomDict = dict["atom"] as? NSDictionary else { return nil }
        guard let atom = SharedRelationAtom.fromPlist(atomDict) else { return nil }
        
        let op: SharedRelationOp?
        if let opDict = dict["op"] as? NSDictionary {
            op = SharedRelationOp.fromPlist(opDict)
        } else {
            op = nil
        }
        
        return SharedRelationElement(
            atom: atom,
            op: op
        )
    }
}

struct SharedRelationModel {
    let elements: [SharedRelationElement]
    
    func toPlist() -> Any {
        let elementPlists = self.elements.map{ $0.toPlist() }
        return [
            "elements": elementPlists
        ]
    }
    
    func toPlistData() -> Data? {
        do {
            return try? PropertyListSerialization.data(fromPropertyList: toPlist(), format: .xml, options: 0)
        }
    }
    
    static func fromPlist(_ plist: Any) -> SharedRelationModel? {
        guard let dict = plist as? NSDictionary else { return nil }
        guard let elementPlists = dict["elements"] as? [Any] else { return nil }
        return SharedRelationModel(
            elements: elementPlists.flatMap{ SharedRelationElement.fromPlist($0) }
        )
    }
    
    static func fromPlistData(_ data: Data) -> SharedRelationModel? {
        do {
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
            return fromPlist(plist)
        } catch {
            return nil
        }
    }
}
