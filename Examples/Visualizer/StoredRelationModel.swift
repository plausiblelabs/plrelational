//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

struct StoredRelationModel {
    let attributes: [Attribute]
    let idAttr: Attribute
    let rows: [Row]
    
    func toPlistData() -> Data? {
        let attrNames = self.attributes.map{ $0.name }
        let rowPlists = self.rows.map{ $0.toPlist() }
        let dict = [
            "attributes": attrNames,
            "idAttr": idAttr.name,
            "rows": rowPlists
        ] as [String : Any]
        do {
            return try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        }
    }
    
    static func fromPlistData(_ data: Data) -> StoredRelationModel? {
        do {
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
            guard let attrNames = plist["attributes"] as? [String] else { return nil }
            guard let idAttr = plist["idAttr"] as? String else { return nil }
            guard let rowPlists = plist["rows"] as? [Any] else { return nil }
            return StoredRelationModel(
                attributes: attrNames.map{ Attribute($0) },
                idAttr: Attribute(idAttr),
                rows: rowPlists.map{ Row.fromPlist($0).ok! }
            )
        } catch {
            return nil
        }
    }
    
    func toRelation() -> Relation {
        let r = MemoryTableRelation(scheme: Scheme(attributes: Set(attributes)))
        r.values = Set(rows)
        return r
    }
}
