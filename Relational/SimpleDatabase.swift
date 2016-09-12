//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

class SimpleDatabase {
    var relations: [String: ConcreteRelation] = [:]
    
    func createRelation(_ name: String, scheme: Scheme) {
        relations[name] = ConcreteRelation(scheme: scheme, values: [], defaultSort: nil)
    }
    
    subscript(name: String) -> ConcreteRelation {
        get {
            return relations[name]!
        }
        set {
            relations[name] = newValue
        }
    }
}

extension SimpleDatabase: CustomStringConvertible {
    var description: String {
        let strings = relations.map({ name, relation in
            "Relation \(name):\n" +
            "================\n" +
            "\(relation)\n" +
            "================"
        })
        return strings.joined(separator: "\n\n")
    }
}

extension SimpleDatabase {
    fileprivate func valueToPlist(_ value: RelationValue) -> AnyObject {
        switch value {
        case .null: return NSNull()
        case .integer(let x): return NSNumber(value: x as Int64)
        case .real(let x): return NSNumber(value: x)
        case .text(let x): return x as NSString
        case .blob(let x): return NSData(bytes: UnsafePointer<UInt8>(x), length: x.count)
        case .notFound: fatalError("NotFound value should not be serialized!")
        }
    }
    
    static fileprivate func plistToValue(_ plist: AnyObject) -> RelationValue {
        switch plist {
        case is NSNull: return .null
        case let x as NSNumber:
            if strcmp(x.objCType, "d") == 0 {
                return .real(x.doubleValue)
            } else {
                return .integer(x.int64Value)
            }
        case let x as NSString:
            return .text(x as String)
        case let x as Data:
            let array = Array(UnsafeBufferPointer(start: (x as NSData).bytes.bindMemory(to: UInt8.self, capacity: x.count), count: x.count))
            return .blob(array)
        default:
            fatalError("Unexpected plist type \(type(of: plist))")
        }
    }
    
    func toPlist() -> Any {
        return Dictionary(relations.map({ (name, relation) -> (String, [String: Any]) in
            let scheme = relation.scheme.attributes.map({ $0.name })
            
            let values = relation.rows().map({ row in
                // We know that ConcreteRelations never produce errors when iterating.
                Dictionary(row.ok!.map({ ($0.name, self.valueToPlist($1)) }))
            })
            return (name, ["scheme": scheme, "values": values])
        })) as AnyObject
    }
    
    static func fromPlist(_ plist: Any) -> SimpleDatabase {
        let dict = plist as! [String: [String: Any]]
        let db = SimpleDatabase()
        for (name, contents) in dict {
            let scheme = contents["scheme"] as! [String]
            db.createRelation(name, scheme: Scheme(attributes: Set(scheme.map({ Attribute($0) }))))
            
            let values = contents["values"] as! [[String: AnyObject]]
            for row in values {
                db[name].add(Row(values: Dictionary(row.map({ (Attribute($0), self.plistToValue($1)) }))))
            }
        }
        return db
    }
}
