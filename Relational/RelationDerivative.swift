
class RelationDerivative {
    /// A variable is a bottom-level Relation which changes directly (rather than changing because
    /// something that it depends on changed). Variables must be objects, because value types can't
    /// sensibly vary in an indirect fashion. Not all object Relations are variables, but saying a
    /// variable is a Relation and an AnyObject gives us what we need here.
    typealias Variable = protocol<Relation, AnyObject>
    
    var placeholders: ObjectDictionary<AnyObject, (added: IntermediateRelation, removed: IntermediateRelation)> = [:]
    
    private var underlyingDerivative: RelationChange?
    
    func placeholdersForVariable(variable: Variable) -> (added: Relation, removed: Relation) {
        let placeholders = self.placeholders.getOrCreate(variable, defaultValue: (
            added: IntermediateRelation(op: .Union, operands: [ConcreteRelation(scheme: variable.scheme)]),
            removed: IntermediateRelation(op: .Union, operands: [ConcreteRelation(scheme: variable.scheme)])
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
    
    func setChange(change: RelationChange, forVariable: Variable) {
        let (added, removed) = placeholders[forVariable]!
        setChange(change.added, forPlaceholder: added)
        setChange(change.removed, forPlaceholder: removed)
    }
    
    var change: RelationChange {
        return underlyingDerivative!
    }
    
    func setUnderlyingDerivative(change: RelationChange) {
        underlyingDerivative = change
    }
    
    private func setChange(change: Relation?, forPlaceholder placeholder: IntermediateRelation) {
        let realChange = change ?? ConcreteRelation(scheme: placeholder.scheme)
        placeholder.operands = [realChange]
    }
}
