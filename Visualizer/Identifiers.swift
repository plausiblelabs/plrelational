//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

class AttrID {
    fileprivate let uuid: UUID
    
    init() {
        self.uuid = UUID()
    }
    
    init(_ stringValue: String) {
        self.uuid = UUID(stringValue)
    }
    
    init(_ relationValue: RelationValue) {
        self.uuid = UUID(relationValue)
    }
    
    var relationValue: RelationValue {
        return uuid.relationValue
    }
    
    var stringValue: String {
        return uuid.stringValue
    }
}

// MARK: Object ID

final class ObjectID: AttrID {
    static func fromNullable(_ relationValue: RelationValue) -> ObjectID? {
        if relationValue != .null {
            return ObjectID(relationValue)
        } else {
            return nil
        }
    }
}

extension ObjectID: Equatable {}
func ==(a: ObjectID, b: ObjectID) -> Bool {
    return a.uuid == b.uuid
}

extension ObjectID: Hashable {
    var hashValue: Int {
        return uuid.hashValue
    }
}

extension ObjectID: CustomStringConvertible {
    var description: String {
        return "ObjectID(\(stringValue)"
    }
}

// MARK: Doc Item ID

final class DocItemID: AttrID {
    static func fromNullable(_ relationValue: RelationValue) -> DocItemID? {
        if relationValue != .null {
            return DocItemID(relationValue)
        } else {
            return nil
        }
    }
}

extension DocItemID: Equatable {}
func ==(a: DocItemID, b: DocItemID) -> Bool {
    return a.uuid == b.uuid
}

extension DocItemID: Hashable {
    var hashValue: Int {
        return uuid.hashValue
    }
}

extension DocItemID: CustomStringConvertible {
    var description: String {
        return "DocItemID(\(stringValue)"
    }
}

// MARK: Tab ID

final class TabID: AttrID {
    static func fromNullable(_ relationValue: RelationValue) -> TabID? {
        if relationValue != .null {
            return TabID(relationValue)
        } else {
            return nil
        }
    }
}

extension TabID: Equatable {}
func ==(a: TabID, b: TabID) -> Bool {
    return a.uuid == b.uuid
}

extension TabID: Hashable {
    var hashValue: Int {
        return uuid.hashValue
    }
}

extension TabID: CustomStringConvertible {
    var description: String {
        return "TabID(\(stringValue)"
    }
}

// MARK: History Item ID

final class HistoryItemID: AttrID {
    static func fromNullable(_ relationValue: RelationValue) -> HistoryItemID? {
        if relationValue != .null {
            return HistoryItemID(relationValue)
        } else {
            return nil
        }
    }
}

extension HistoryItemID: Equatable {}
func ==(a: HistoryItemID, b: HistoryItemID) -> Bool {
    return a.uuid == b.uuid
}

extension HistoryItemID: Hashable {
    var hashValue: Int {
        return uuid.hashValue
    }
}

extension HistoryItemID: CustomStringConvertible {
    var description: String {
        return "HistoryItemID(\(stringValue)"
    }
}

// MARK: UUID

// TODO: Need to check whether provided string values are well-formed
struct UUID {
    let stringValue: String
    
    init() {
        self.stringValue = ProcessInfo.processInfo.globallyUniqueString
    }
    
    init(_ stringValue: String) {
        self.stringValue = stringValue
    }
    
    init(_ relationValue: RelationValue) {
        self.stringValue = relationValue.get()!
    }
    
    var relationValue: RelationValue {
        return RelationValue(self)
    }
}

extension UUID: Equatable {}
func ==(a: UUID, b: UUID) -> Bool {
    return a.stringValue == b.stringValue
}

extension UUID: Hashable {
    var hashValue: Int {
        return stringValue.hashValue
    }
}

extension RelationValue {
    init(_ uuid: UUID) {
        self = .text(uuid.stringValue)
    }
}
