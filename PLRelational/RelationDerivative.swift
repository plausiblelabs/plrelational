//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

class RelationDerivative {
    /// A variable is a bottom-level Relation which changes directly (rather than changing because
    /// something that it depends on changed). Variables must be objects, because value types can't
    /// sensibly vary in an indirect fashion. Not all object Relations are variables, but saying a
    /// variable is a Relation and an AnyObject gives us what we need here.
    typealias Variable = Relation & AnyObject
    
    var placeholders: ObjectDictionary<AnyObject, (added: IntermediateRelation, removed: IntermediateRelation)> = [:]
    
    fileprivate var underlyingDerivative: RelationChange?
    
    func placeholdersForVariable(_ variable: Variable) -> (added: Relation, removed: Relation) {
        let placeholders = self.placeholders.getOrCreate(variable, defaultValue: (
            added: IntermediateRelation(op: .union, operands: [ConcreteRelation(scheme: variable.scheme)]),
            removed: IntermediateRelation(op: .union, operands: [ConcreteRelation(scheme: variable.scheme)])
        ))
        return (placeholders.0, placeholders.1)
    }
    
    var allVariables: [Variable] {
        return placeholders.keys.map({ $0 as! Variable })
    }
    
    func clearVariables() {
        for (_, placeholders) in self.placeholders {
            self.setChange(nil, forPlaceholder: placeholders.added)
            self.setChange(nil, forPlaceholder: placeholders.removed)
        }
    }
    
    func setChange(_ change: RelationChange, forVariable: Variable) {
        let (added, removed) = placeholders[forVariable]!
        setChange(change.added, forPlaceholder: added)
        setChange(change.removed, forPlaceholder: removed)
    }
    
    func addChange(_ change: RelationChange, toVariable variable: Variable) {
        let currentChange = changeForVariable(variable)
        
        let new = change.added - currentChange.removed
        let gone = change.removed - currentChange.added
        
        let newAdded = currentChange.added + new - change.removed
        let newRemoved = currentChange.removed + gone - change.added
        
        let newChange = RelationChange(added: newAdded, removed: newRemoved)
        setChange(newChange, forVariable: variable)
    }
    
    var change: RelationChange {
        return underlyingDerivative!
    }
    
    func setUnderlyingDerivative(_ change: RelationChange) {
        underlyingDerivative = change
    }
    
    fileprivate func setChange(_ change: Relation?, forPlaceholder placeholder: IntermediateRelation) {
        let realChange = change ?? ConcreteRelation(scheme: placeholder.scheme)
        placeholder.operands = [realChange]
    }
    
    fileprivate func changeForVariable(_ variable: Variable) -> RelationChange {
        let (added, removed) = placeholders[variable]!
        return RelationChange(added: changeForPlaceholder(added),
                              removed: changeForPlaceholder(removed))
    }
    
    fileprivate func changeForPlaceholder(_ placeholder: IntermediateRelation) -> Relation? {
        return placeholder.operands.first
    }
}
