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
    func toPlist() -> AnyObject {
        return Dictionary(relations.map({ (name, relation) -> (String, [String: AnyObject]) in
            let scheme = relation.scheme.attributes.map({ $0.name })
            
            let values = relation.rows().map({ row in
                Dictionary(row.values.map({ ($0.name, $1) }))
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
            
            let values = contents["values"] as! [[String: String]]
            for row in values {
                db[name].add(Row(values: Dictionary(row.map({ (Attribute($0), $1) }))))
            }
        }
        return db
    }
}
