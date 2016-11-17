//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

enum RelationModel {
    case stored(StoredRelationModel)
    case shared(SharedRelationModel)
    
    func toRelation() -> Relation {
        switch self {
        case .stored(let model):
            return model.toRelation()
        case .shared:
            fatalError("Not yet implemented")
        }
    }
}

// MARK: Stored relations

struct StoredRelationModel {
    let attributes: [Attribute]
    let idAttr: Attribute
    let rows: [Row]
    
    func toRelation() -> Relation {
        let r = MemoryTableRelation(scheme: Scheme(attributes: Set(attributes)))
        r.values = Set(rows)
        return r
    }
}

// MARK: Shared relations

struct SharedRelationInput {
    let objectID: ObjectID
    let projection: [Attribute]?
}

enum SharedRelationUnaryOp {
    // TODO: Generalize this (different comparison ops, different value types)
    case selectEq(Attribute, RelationValue)
    case count
}

enum SharedRelationBinaryOp {
    case join(SharedRelationInput)
    case union(SharedRelationInput)
    
    var rhs: SharedRelationInput {
        switch self {
        case .join(let input): return input
        case .union(let input): return input
        }
    }
}

enum SharedRelationOp {
    case filter(SharedRelationUnaryOp)
    case combine(SharedRelationBinaryOp)
}

struct SharedRelationStage {
    let op: SharedRelationOp?
    let projection: [Attribute]?
}

struct SharedRelationModel {
    let input: SharedRelationInput
    let stages: [SharedRelationStage]

    /// Returns the set of identifiers corresponding to the relation objects referenced in this model.
    func referencedObjectIDs() -> Set<ObjectID> {
        var ids: Set<ObjectID> = []
        
        func processInput(_ input: SharedRelationInput) {
            ids.insert(input.objectID)
        }

        processInput(self.input)
        for stage in self.stages {
            if let op = stage.op {
                switch op {
                case .filter:
                    break
                case .combine(let binaryOp):
                    processInput(binaryOp.rhs)
                }
            }
        }
        
        return ids
    }
}

// MARK: Plist conversion

extension RelationModel {
    func toPlist() -> Any {
        let dict = NSMutableDictionary()
        switch self {
        case .stored(let model):
            dict["stored"] = model.toPlist()
        case .shared(let model):
            dict["shared"] = model.toPlist()
        }
        return dict
    }
    
    func toPlistData() -> Data? {
        do {
            return try? PropertyListSerialization.data(fromPropertyList: toPlist(), format: .xml, options: 0)
        }
    }
    
    static func fromPlist(_ plist: Any) -> RelationModel? {
        guard let dict = plist as? NSDictionary else { return nil }

        if let storedDict = dict["stored"] as? NSDictionary {
            return StoredRelationModel.fromPlist(storedDict).map{ .stored($0) }
        } else if let sharedDict = dict["shared"] as? NSDictionary {
            return SharedRelationModel.fromPlist(sharedDict).map{ .shared($0) }
        } else {
            return nil
        }
    }

    static func fromPlistData(_ data: Data) -> RelationModel? {
        do {
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            return fromPlist(plist)
        } catch {
            return nil
        }
    }
}

extension StoredRelationModel {
    func toPlist() -> Any {
        let attrNames = self.attributes.map{ $0.name }
        let rowPlists = self.rows.map{ $0.toPlist() }
        return [
            "attributes": attrNames,
            "idAttr": idAttr.name,
            "rows": rowPlists
        ]
    }
    
    static func fromPlist(_ plist: Any) -> StoredRelationModel? {
        guard let dict = plist as? NSDictionary else { return nil }
        guard let attrNames = dict["attributes"] as? [String] else { return nil }
        guard let idAttr = dict["idAttr"] as? String else { return nil }
        guard let rowPlists = dict["rows"] as? [Any] else { return nil }
        return StoredRelationModel(
            attributes: attrNames.map{ Attribute($0) },
            idAttr: Attribute(idAttr),
            // TODO: Fix this unsafe unwrap
            rows: rowPlists.map{ Row.fromPlist($0).ok! }
        )
    }
}

extension SharedRelationInput {
    func toPlist() -> Any {
        let dict = NSMutableDictionary()
        dict["objectID"] = objectID.stringValue
        if let projectedAttrs = projection {
            let attrNames = projectedAttrs.map{ $0.name }
            dict["projectedAttrs"] = attrNames
        }
        return dict
    }

    static func fromPlist(_ plist: Any) -> SharedRelationInput? {
        guard let dict = plist as? NSDictionary else { return nil }

        guard let objectID = dict["objectID"] as? String else { return nil }

        let projection: [Attribute]?
        if let attrNames = dict["projectedAttrs"] as? [String] {
            projection = attrNames.map{ Attribute($0) }
        } else {
            projection = nil
        }

        return SharedRelationInput(
            objectID: ObjectID(objectID),
            projection: projection
        )
    }
}

extension SharedRelationUnaryOp {
    func toPlist() -> Any {
        let dict = NSMutableDictionary()
        switch self {
        case let .selectEq(attr, value):
            let selectEqDict = NSMutableDictionary()
            selectEqDict["attribute"] = attr.name
            selectEqDict["value"] = value.toEncodedPlist()
            dict["selectEq"] = selectEqDict
        case .count:
            dict["count"] = true
        }
        return dict
    }

    static func fromPlist(_ plist: Any) -> SharedRelationUnaryOp? {
        guard let dict = plist as? NSDictionary else { return nil }

        if let selectEqDict = dict["selectEq"] as? NSDictionary {
            guard let attrName = selectEqDict["attribute"] as? String else { return nil }
            guard let valuePlist = selectEqDict["value"] else { return nil }
            guard let value = RelationValue.fromEncodedPlist(valuePlist).ok else { return nil }
            return .selectEq(Attribute(attrName), value)
        } else if dict["count"] != nil {
            return .count
        } else {
            return nil
        }
    }
}

extension SharedRelationBinaryOp {
    func toPlist() -> Any {
        let dict = NSMutableDictionary()
        switch self {
        case .join(let input):
            dict["join"] = input.toPlist()
        case .union(let input):
            dict["union"] = input.toPlist()
        }
        return dict
    }

    static func fromPlist(_ plist: Any) -> SharedRelationBinaryOp? {
        guard let dict = plist as? NSDictionary else { return nil }

        if let inputDict = dict["join"] as? NSDictionary {
            return SharedRelationInput.fromPlist(inputDict).map{ .join($0) }
        } else if let inputDict = dict["union"] as? NSDictionary {
            return SharedRelationInput.fromPlist(inputDict).map{ .union($0) }
        } else {
            return nil
        }
    }
}

extension SharedRelationOp {
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

extension SharedRelationStage {
    func toPlist() -> Any {
        let dict = NSMutableDictionary()
        if let op = op {
            dict["op"] = op.toPlist()
        }
        if let projectedAttrs = projection {
            let attrNames = projectedAttrs.map{ $0.name }
            dict["projectedAttrs"] = attrNames
        }
        return dict
    }

    static func fromPlist(_ plist: Any) -> SharedRelationStage? {
        guard let dict = plist as? NSDictionary else { return nil }

        let op: SharedRelationOp?
        if let opDict = dict["op"] as? NSDictionary {
            op = SharedRelationOp.fromPlist(opDict)
        } else {
            op = nil
        }

        let projection: [Attribute]?
        if let attrNames = dict["projectedAttrs"] as? [String] {
            projection = attrNames.map{ Attribute($0) }
        } else {
            projection = nil
        }

        return SharedRelationStage(
            op: op,
            projection: projection
        )
    }
}

extension SharedRelationModel {
    func toPlist() -> Any {
        let stagePlists = self.stages.map{ $0.toPlist() }
        return [
            "input": input.toPlist(),
            "stages": stagePlists
        ]
    }

    static func fromPlist(_ plist: Any) -> SharedRelationModel? {
        guard let dict = plist as? NSDictionary else { return nil }
        guard let inputDict = dict["input"] as? NSDictionary else { return nil }
        guard let input = SharedRelationInput.fromPlist(inputDict) else { return nil }
        guard let stagePlists = dict["stages"] as? [Any] else { return nil }
        return SharedRelationModel(
            input: input,
            stages: stagePlists.flatMap{ SharedRelationStage.fromPlist($0) }
        )
    }
}

// TODO: Return Result instead of Optional for fromPlist() funcs
//enum RelationModelPlistError: Error {
//}
