//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

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
 
  # |  A  |  B  | A u B |
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
 
 
 Intersection table:
 
  # |  A  |  B  | A ∩ B |
 ---+-----+-----+-------+
  1 | in  | in+ |  in+  |
  2 | in  | in- |  in-  |
  3 | !in | in+ |       |
  4 | !in | in- |       |
  5 | in+ | in  |  in+  |
  6 | in+ | !in |       |
  7 | in+ | in+ |  in+  |
  8 | in+ | in- |       |
  9 | in- | in  |  in-  |
 10 | in- | !in |       |
 11 | in- | in+ |       |
 12 | in- | in- |  in-  |
 ---+-----+-----+-------+
 
 + = ((A+ ∩ B) - B-) u ((B+ ∩ A) - A-)
 - = ((A- ∩ (B u B-)) - B+) u (((B- ∩ (A u A-)) - A+)
 
 
 Difference table:
 
  # |  A  |  B  | A - B |
 ---+-----+-----+-------+
  1 | in  | in+ |  in-  |
  2 | in  | in- |  in+  |
  3 | !in | in+ |       |
  4 | !in | in- |       |
  5 | in+ | in  |       |
  6 | in+ | !in |  in+  |
  7 | in+ | in+ |       |
  8 | in+ | in- |  in+  |
  9 | in- | in  |       |
 10 | in- | !in |  in-  |
 11 | in- | in+ |  in-  |
 12 | in- | in- |       |
 ---+-----+-----+-------+
 
 + = (A ∩ B-) + (A+ - B)
 - = ((A - A+) ∩ B+) + ((A- - B-) - (B - B+))

 */

class RelationDifferentiator {
    private let relation: Relation
    private var derivativeMap: ObjectDictionary<AnyObject, RelationChange> = [:]
    
    private let derivative = RelationDerivative()
    
    init(relation: Relation) {
        self.relation = relation
    }
}

extension RelationDifferentiator {
    func computeDerivative() -> RelationDerivative {
        // Fetching the derivative of the top relation will compute the whole thing.
        derivative.setUnderlyingDerivative(derivativeOf(relation))
        return derivative
    }
    
    private func derivativeOf(relation: Relation) -> RelationChange {
        if let obj = relation as? AnyObject {
            return derivativeMap.getOrCreate(obj, defaultValue: rawDerivativeOf(relation))
        } else {
            return rawDerivativeOf(relation)
        }
    }
    
    private func rawDerivativeOf(relation: Relation) -> RelationChange {
        switch relation {
        case let intermediate as IntermediateRelation:
            // Intermediate relations require more smarts. Do that elsewhere.
            return intermediateDerivative(intermediate)
        case let obj as RelationDerivative.Variable:
            // Variables use their placeholders as derivatives.
            let placeholders = derivative.placeholdersForVariable(obj)
            return RelationChange(added: placeholders.added, removed: placeholders.removed)
        default:
            // Other non-intermediate relations are constant in the face of changes, so we're just nil.
            return RelationChange(added: nil, removed: nil)
        }
    }
}

extension RelationDifferentiator {
    private func intermediateDerivative(r: IntermediateRelation) -> RelationChange {
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
        case .Otherwise:
            return otherwiseDerivative(r)
        case .Unique:
            return uniqueDerivative(r)
        }
    }
    
    private func unionDerivative(r: IntermediateRelation) -> RelationChange {
        if r.operands.isEmpty {
            return RelationChange(added: nil, removed: nil)
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
            
        return RelationChange(added: added, removed: removed)
    }
    
    private func intersectionDerivative(r: IntermediateRelation) -> RelationChange {
        if r.operands.isEmpty {
            return RelationChange(added: nil, removed: nil)
        } else if r.operands.count == 1 {
            return derivativeOf(r.operands[0])
        }
        
        // We only support two operands. (For now?)
        let A = r.operands[0]
        let B = r.operands[1]
        let dA = derivativeOf(A)
        let dB = derivativeOf(B)
        
        // + = ((A+ ∩ B) - B-) u ((B+ ∩ A) - A-)
        // - = ((A- ∩ (B u B-)) - B+) u (((B- ∩ (A u A-)) - A+)
        let added = ((dA.added ∩ B) - dB.removed) + ((dB.added ∩ A) - dA.removed)
        let removed = ((dA.removed ∩ (B + dB.removed)) - dB.added) + ((dB.removed ∩ (A + dA.removed)) - dA.added)
        
        return RelationChange(added: added, removed: removed)
    }
    
    private func differenceDerivative(r: IntermediateRelation) -> RelationChange {
        if r.operands.isEmpty {
            return RelationChange(added: nil, removed: nil)
        } else if r.operands.count == 1 {
            return derivativeOf(r.operands[0])
        }
        
        // We only support two operands. (For now?)
        let A = r.operands[0]
        let B = r.operands[1]
        let dA = derivativeOf(A)
        let dB = derivativeOf(B)
        
        // + = (A ∩ B-) + (A+ - B)
        // - = ((A - A+) ∩ B+) + ((A- - B-) - (B - B+))
        let added = (A ∩ dB.removed) + (dA.added - B)
        let removed = ((A - dA.added) ∩ dB.added) + ((dA.removed - dB.removed) - (B - dB.added))
        
        return RelationChange(added: added, removed: removed)
    }
    
    private func projectionDerivative(r: IntermediateRelation, scheme: Scheme) -> RelationChange {
        // Adds to the underlying relation are adds to the projected relation
        // if there were no matching rows in the relation before. To compute
        // that, project the changes, then subtract the pre-change relation,
        // which is the post-change relation minus additions and plus removals.
        //
        // Removes are the same, except they subtract the post-change relation,
        // which is just the relation.
        let underlyingDerivative = derivativeOf(r.operands[0])
        let preChangeRelation = self.preChangeRelation(r.operands[0])
        
        return RelationChange(added: underlyingDerivative.added?.project(scheme).difference(preChangeRelation.project(scheme)),
                                  removed: underlyingDerivative.removed?.project(scheme).difference(r))
    }
    
    private func selectDerivative(r: IntermediateRelation, expression: SelectExpression) -> RelationChange {
        // Our changes are equal to the underlying changes with the same select applied.
        // (select A)' = select A'
        let underlyingDerivative = derivativeOf(r.operands[0])
        return RelationChange(added: underlyingDerivative.added?.select(expression),
                                  removed: underlyingDerivative.removed?.select(expression))
    }
    
    private func equijoinDerivative(r: IntermediateRelation, matching: [Attribute: Attribute]) -> RelationChange {
        // TODO: if we apply some brainpower we may be able to figure out how to compute this derivative without running
        // the entire join multiple times just to compute the before/after differences.
        let prejoin = preChangeRelation(r.operands[0]).equijoin(preChangeRelation(r.operands[1]), matching: matching)
        let added = r - prejoin
        let removed = prejoin - r
        return RelationChange(added: added, removed: removed)
    }
    
    private func renameDerivative(r: IntermediateRelation, renames: [Attribute: Attribute]) -> RelationChange {
        // Changes are the same, but renamed.
        // (rename A)' = rename A'
        let underlyingDerivative = derivativeOf(r.operands[0])
        return RelationChange(added: underlyingDerivative.added?.renameAttributes(renames),
                                  removed: underlyingDerivative.removed?.renameAttributes(renames))
    }
    
    private func updateDerivative(r: IntermediateRelation, newValues: Row) -> RelationChange {
        // Our updates are equal to the projected updates joined with our newValues.
        // (update A newValues)' = (projected A') join newValues
        let untouchedScheme = Scheme(attributes: Set(r.operands[0].scheme.attributes.subtract(newValues.values.keys)))
        let projectionDerivative = self.projectionDerivative(r, scheme: untouchedScheme)
        return RelationChange(added: projectionDerivative.added?.join(ConcreteRelation(newValues)),
                                  removed: projectionDerivative.removed?.join(ConcreteRelation(newValues)))
    }
    
    private func aggregateDerivative(r: IntermediateRelation, attribute: Attribute, initialValue: RelationValue?, aggregateFunction: (RelationValue?, RelationValue) -> Result<RelationValue, RelationError>) -> RelationChange {
        // Do a brute before/after difference.
        // A' = (new A) - (old A)
        // We called this approach "dumb and inefficient"; is there a better way here?
        let preChangeRelation = self.preChangeRelation(r.operands[0])
        let previousAgg = IntermediateRelation(op: .Aggregate(attribute, initialValue, aggregateFunction), operands: [preChangeRelation])
        return RelationChange(added: r.difference(previousAgg),
                                  removed: previousAgg.difference(r))
    }
    
    private func otherwiseDerivative(r: IntermediateRelation) -> RelationChange {
        // Do another brute before/after difference.
        // A' = (new A) - (old A)
        let preChangeRelations = r.operands.map(self.preChangeRelation)
        let previousOtherwise = IntermediateRelation(op: .Otherwise, operands: preChangeRelations)
        return RelationChange(added: r.difference(previousOtherwise),
                              removed: previousOtherwise.difference(r))
    }
    
    private func uniqueDerivative(r: IntermediateRelation) -> RelationChange {
        // Do another brute before/after difference.
        // A' = (new A) - (old A)
        let preChangeRelations = r.operands.map(self.preChangeRelation)
        let previousOtherwise = IntermediateRelation(op: r.op, operands: preChangeRelations)
        return RelationChange(added: r.difference(previousOtherwise),
                              removed: previousOtherwise.difference(r))
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
