
/*
 
 For pure binary operations, where the scheme is the same on both sides, any given row
 can be in or not in either side before or after.
 
 Notation for the status of a row in a relation:
 
 in - Present both before and after a change.
 !in - Not present before nor after.
 in+ - Added to the relation, in the "added" set.
 in- - Removed from the relation, in the "removed" set.
 
 
 Binary operation table for one row R in A op B:
 
   A  in   !in  in+  in-
 B
  in  X     X    ?    ?
 !in  X     X    ?    ?
 in+  ?     ?    ?    ?
 in-  ?     ?    ?    ?
 
 There are sixteen before-and-after possibilities for a row. Four of them involve no change
 and can be ignored, leaving us with twelve potential changes:
 
 Linear table:
 
 #  |  A  |  B  |
 ---+-----+-----+
  1 | in  | in+ |
  2 | in  | in- |
  3 | !in | in+ |
  4 | !in | in- |
  5 | in+ | in  |
  6 | in+ | !in |
  7 | in+ | in+ |
  8 | in+ | in- |
  9 | in- | in  |
 10 | in- | !in |
 11 | in- | in+ |
 12 | in- | in- |
 ---+-----+-----+
 
 For each operation, this table can be evaluated for the status of each row, then a relation
 created that generates the proper result for each row. This will produce the correct derivative.
 Since we only care about changes, the output doesn't need `in` or `!in`, only `in+` and `in-`.
 
 
 Union table:
 
 #  |  A  |  B  | A u B |
 ---+-----+-----+-------+
  1 | in  | in+ |       |
  2 | in  | in- |       |
  3 | !in | in+ |  in+  |
  4 | !in | in- |  in-  |
  5 | in+ | in  |       |
  6 | in+ | !in |  in+  |
  7 | in+ | in+ |  in+  |
  8 | in+ | in- |       |
  9 | in- | in  |       |
 10 | in- | !in |  in-  |
 11 | in- | in+ |       |
 12 | in- | in- |  in-  |
 ---+-----+-----+-------+
 
 + = ((A+ - (B - B+)) - B-) u ((B+ - (A - A+)) - A-)
 - = (A- - (B - B-)) u (B- - (A - A-))
 
 */
class RelationDerivative {
    let added: Relation?
    let removed: Relation?
    
    private init(added: Relation?, removed: Relation?) {
        self.added = added
        self.removed = removed
    }
}

class RelationDifferentiator {
    let withRespectTo: protocol<Relation, AnyObject>
    let addPlaceholder: Relation
    let removePlaceholder: Relation
    
    var derivativeMap: ObjectDictionary<AnyObject, RelationDerivative> = [:]
    
    init(withRespectTo: protocol<Relation, AnyObject>, addPlaceholder: Relation, removePlaceholder: Relation) {
        self.withRespectTo = withRespectTo
        self.addPlaceholder = addPlaceholder
        self.removePlaceholder = removePlaceholder
    }
}

extension RelationDifferentiator {
    func derivativeOf(relation: Relation) -> RelationDerivative {
        if let obj = relation as? AnyObject {
            return derivativeMap.getOrCreate(obj, defaultValue: rawDerivativeOf(relation))
        } else {
            return rawDerivativeOf(relation)
        }
    }
    
    private func rawDerivativeOf(relation: Relation) -> RelationDerivative {
        switch relation {
        case let obj as AnyObject where obj === withRespectTo:
            // When we find the relation we're differentiating with respect to, then use the placeholders.
            return RelationDerivative(added: addPlaceholder, removed: removePlaceholder)
        case let intermediate as IntermediateRelation:
            // Intermediate relations require more smarts. Do that elsewhere.
            return intermediateDerivative(intermediate)
        default:
            // Other non-intermediate relations are constant in the face of changes, so we're just nil.
            return RelationDerivative(added: nil, removed: nil)
        }
    }
}

extension RelationDifferentiator {
    private func intermediateDerivative(r: IntermediateRelation) -> RelationDerivative {
        switch r.op {
        case .Union:
            return unionDerivative(r)
        case .Intersection:
            return intersectionDerivative(r)
        case .Difference:
            return differenceDerivative(r)
        case .Project(let scheme):
            return projectionDerivative(r, scheme: scheme)
        case .Select(let expression):
            return selectDerivative(r, expression: expression)
        case .Equijoin(let matching):
            return equijoinDerivative(r, matching: matching)
        case .Rename(let renames):
            return renameDerivative(r, renames: renames)
        case .Update(let newValues):
            return updateDerivative(r, newValues: newValues)
        case .Aggregate(let attribute, let initialValue, let aggregateFunction):
            return aggregateDerivative(r, attribute: attribute, initialValue: initialValue, aggregateFunction: aggregateFunction)
        }
    }
    
    private func unionDerivative(r: IntermediateRelation) -> RelationDerivative {
        if r.operands.isEmpty {
            return RelationDerivative(added: nil, removed: nil)
        } else if r.operands.count == 1 {
            return derivativeOf(r.operands[0])
        }
        
        // We only support two operands. (For now?)
        let A = r.operands[0]
        let B = r.operands[1]
        let dA = derivativeOf(A)
        let dB = derivativeOf(B)
        
        // + = ((A+ - (B - B+)) - B-) u ((B+ - (A - A+)) - A-)
        // - = (A- - (B - B-)) u (B- - (A - A-))
        let added = ((dA.added - (B - dB.added)) - dB.removed) + ((dB.added - (A - dA.added)) - dA.removed)
        let removed = (dA.removed - (B - dB.removed)) + (dB.removed - (A - dA.removed))
            
        return RelationDerivative(added: added, removed: removed)
    }
    
    private func intersectionDerivative(r: IntermediateRelation) -> RelationDerivative {
        // Adding or removing a row from one part of an intersection alters the intersection
        // iff the row is already in another part of the intersection.
        // The derivative of an intersection is equal to the derivative of each part, with
        // other parts intersected, all unioned together.
        // (A intersect B)' = (A' intersect B) union (B' intersect A)
        let pieces = r.operands.enumerate().map({ (index, operand) -> (added: Relation?, removed: Relation?) in
            let derivative = derivativeOf(operand)
            return (
                derivative.added?.intersection(IntermediateRelation.union(r.otherOperands(index))),
                derivative.removed?.intersection(IntermediateRelation.union(r.otherOperands(index)))
            )
        })
        
        // We must also account for changes which apply everywhere simultaneously.
        // The intersection of all operand changes is our change too.
        let allDerivatives = r.operands.map(derivativeOf)
        let withAll = pieces + [(
            added: intersection(allDerivatives.map({ $0.added })),
            removed: intersection(allDerivatives.map({ $0.removed })))]
        
        return RelationDerivative(added: union(withAll.map({ $0.added })),
                                  removed: union(withAll.map({ $0.removed })))
    }
    
    private func differenceDerivative(r: IntermediateRelation) -> RelationDerivative {
        // When the first one changes, our changes are the same, minus the second.
        // When the second one changes, then changes are reversed and intersected
        // with the first.
        // (A - B)' = (A' - B) union (A intersect reverse(B'))
        let derivatives = r.operands.map({
            derivativeOf($0)
        })
        let oldOperands = preChangeRelations(r.operands)
        let added0 = derivatives[0].added?.difference(oldOperands[1])
        let removed0 = derivatives[0].removed?.difference(oldOperands[1])
        let added1 = derivatives[1].removed?.intersection(oldOperands[0])
        let removed1 = derivatives[1].added?.intersection(oldOperands[0])
        
        // Changes which occur on both sides simultaneously don't occur at all in the difference,
        // so subtract the other derivative from each.
        
        return RelationDerivative(added: union([difference(added0, derivatives[1].added), difference(added1, derivatives[0].removed)]),
                                  removed: union([difference(removed0, derivatives[1].removed), difference(removed1, derivatives[0].added)]))
    }
    
    private func projectionDerivative(r: IntermediateRelation, scheme: Scheme) -> RelationDerivative {
        // Adds to the underlying relation are adds to the projected relation
        // if there were no matching rows in the relation before. To compute
        // that, project the changes, then subtract the pre-change relation,
        // which is the post-change relation minus additions and plus removals.
        //
        // Removes are the same, except they subtract the post-change relation,
        // which is just the relation.
        let underlyingDerivative = derivativeOf(r.operands[0])
        let preChangeRelation = self.preChangeRelation(r.operands[0])
        
        return RelationDerivative(added: underlyingDerivative.added?.project(scheme).difference(preChangeRelation.project(scheme)),
                                  removed: underlyingDerivative.removed?.project(scheme).difference(r))
    }
    
    private func selectDerivative(r: IntermediateRelation, expression: SelectExpression) -> RelationDerivative {
        // Our changes are equal to the underlying changes with the same select applied.
        // (select A)' = select A'
        let underlyingDerivative = derivativeOf(r.operands[0])
        return RelationDerivative(added: underlyingDerivative.added?.select(expression),
                                  removed: underlyingDerivative.removed?.select(expression))
    }
    
    private func equijoinDerivative(r: IntermediateRelation, matching: [Attribute: Attribute]) -> RelationDerivative {
        // Changes in a relation are joined with the other one to produce the final result.
        // (A join B)' = (A' join B) union (A join B')
        let derivatives = r.operands.map({
            derivativeOf($0)
        })
        let added0 = derivatives[0].added?.equijoin(preChangeRelation(r.operands[1]), matching: matching)
        let removed0 = derivatives[0].removed?.equijoin(preChangeRelation(r.operands[1]), matching: matching)
        let added1 = derivatives[1].added.map({ preChangeRelation(r.operands[0]).equijoin($0, matching: matching) })
        let removed1 = derivatives[1].removed.map({ preChangeRelation(r.operands[0]).equijoin($0, matching: matching) })
        
        return RelationDerivative(added: union([added0, added1]),
                                  removed: union([removed0, removed1]))
    }
    
    private func renameDerivative(r: IntermediateRelation, renames: [Attribute: Attribute]) -> RelationDerivative {
        // Changes are the same, but renamed.
        // (rename A)' = rename A'
        let underlyingDerivative = derivativeOf(r.operands[0])
        return RelationDerivative(added: underlyingDerivative.added?.renameAttributes(renames),
                                  removed: underlyingDerivative.removed?.renameAttributes(renames))
    }
    
    private func updateDerivative(r: IntermediateRelation, newValues: Row) -> RelationDerivative {
        // Our updates are equal to the projected updates joined with our newValues.
        // (update A newValues)' = (projected A') join newValues
        let untouchedScheme = Scheme(attributes: Set(r.operands[0].scheme.attributes.subtract(newValues.values.keys)))
        let projectionDerivative = self.projectionDerivative(r, scheme: untouchedScheme)
        return RelationDerivative(added: projectionDerivative.added?.join(ConcreteRelation(newValues)),
                                  removed: projectionDerivative.removed?.join(ConcreteRelation(newValues)))
    }
    
    private func aggregateDerivative(r: IntermediateRelation, attribute: Attribute, initialValue: RelationValue?, aggregateFunction: (RelationValue?, RelationValue) -> Result<RelationValue, RelationError>) -> RelationDerivative {
        // Do a brute before/after difference.
        // A' = (new A) - (old A)
        // We called this approach "dumb and inefficient"; is there a better way here?
        let preChangeRelation = self.preChangeRelation(r.operands[0])
        let previousAgg = IntermediateRelation(op: .Aggregate(attribute, initialValue, aggregateFunction), operands: [preChangeRelation])
        return RelationDerivative(added: r.difference(previousAgg),
                                  removed: previousAgg.difference(r))
    }
}

extension RelationDifferentiator {
    private func union(relations: [Relation?]) -> Relation? {
        let nonnil = relations.flatMap({ $0 })
        if nonnil.isEmpty {
            return nil
        } else if nonnil.count == 1 {
            return nonnil[0]
        } else {
            return IntermediateRelation.union(nonnil)
        }
    }
    
    private func intersection(relations: [Relation?]) -> Relation? {
        let nonnil = relations.flatMap({ $0 })
        if nonnil.isEmpty || nonnil.count != relations.count {
            return nil
        } else if nonnil.count == 1 {
            return nonnil[0]
        } else {
            return IntermediateRelation.intersection(nonnil)
        }
    }
    
    private func difference(a: Relation?, _ b: Relation?) -> Relation? {
        if let a = a, b = b {
            return a.difference(b)
        } else if let a = a {
            return a
        } else {
            return nil
        }
    }
    
    private func preChangeRelation(r: Relation) -> Relation {
        let d = derivativeOf(r)
        var preChangeRelation = r
        if let added = d.added {
            preChangeRelation = preChangeRelation.difference(added)
        }
        if let removed = d.removed {
            preChangeRelation = preChangeRelation.union(removed)
        }
        return preChangeRelation
    }
    
    private func preChangeRelations(relations: [Relation]) -> [Relation] {
        return relations.map(self.preChangeRelation)
    }
}

private func +(lhs: Relation?, rhs: Relation?) -> Relation? {
    switch (lhs, rhs) {
    case let (.Some(lhs), .Some(rhs)):
        return lhs.union(rhs)
    case let (.Some(lhs), .None):
        return lhs
    case let (.None, .Some(rhs)):
        return rhs
    case (.None, .None):
        return nil
    }
}

private func -(lhs: Relation?, rhs: Relation?) -> Relation? {
    if let lhs = lhs, rhs = rhs {
        return lhs.difference(rhs)
    } else if let lhs = lhs {
        return lhs
    } else {
        return nil
    }
}
