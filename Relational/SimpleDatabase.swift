import Foundation

class SimpleDatabase {
    var relations: [String: ConcreteRelation] = [:]
    
    func createRelation(name: String, scheme: Scheme) {
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
        return strings.joinWithSeparator("\n\n")
    }
}

extension SimpleDatabase {
    private func valueToPlist(value: RelationValue) -> AnyObject {
        switch value {
        case .NULL: return NSNull()
        case .Integer(let x): return NSNumber(longLong: x)
        case .Real(let x): return x
        case .Text(let x): return x
        case .Blob(let x): return NSData(bytes: x, length: x.count)
        case .NotFound: fatalError("NotFound value should not be serialized!")
        }
    }
    
    static private func plistToValue(plist: AnyObject) -> RelationValue {
        switch plist {
        case is NSNull: return .NULL
        case let x as NSNumber:
            if strcmp(x.objCType, "d") == 0 {
                return .Real(x.doubleValue)
            } else {
                return .Integer(x.longLongValue)
            }
        case let x as NSString:
            return .Text(x as String)
        case let x as NSData:
            let array = Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>(x.bytes), count: x.length))
            return .Blob(array)
        default:
            fatalError("Unexpected plist type \(plist.dynamicType)")
        }
    }
    
    func toPlist() -> AnyObject {
        return Dictionary(relations.map({ (name, relation) -> (String, [String: AnyObject]) in
            let scheme = relation.scheme.attributes.map({ $0.name })
            
            let values = relation.rows().map({ row in
                // We know that ConcreteRelations never produce errors when iterating.
                Dictionary(row.ok!.values.map({ ($0.name, self.valueToPlist($1)) }))
            })
            return (name, ["scheme": scheme, "values": values])
        }))
    }
    
    static func fromPlist(plist: AnyObject) -> SimpleDatabase {
        let dict = plist as! [String: [String: AnyObject]]
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
