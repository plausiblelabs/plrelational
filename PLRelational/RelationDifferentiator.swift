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
    fileprivate let relation: Relation
    fileprivate var derivativeMap: ObjectDictionary<AnyObject, RelationChange> = [:]
    
    fileprivate let derivative = RelationDerivative()
    
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
    
    fileprivate func derivativeOf(_ relation: Relation) -> RelationChange {
        if let obj = asObject(relation) {
            if let change = derivativeMap[obj] {
                return change
            } else {
                let change = rawDerivativeOf(relation)
                derivativeMap[obj] = change
                return change
            }
        } else {
            return rawDerivativeOf(relation)
        }
    }
    
    fileprivate func rawDerivativeOf(_ relation: Relation) -> RelationChange {
        let change: RelationChange
        switch relation {
        case let intermediate as IntermediateRelation:
            // Intermediate relations require more smarts. Do that elsewhere.
            change = intermediateDerivative(intermediate)
        case let obj as RelationDerivative.Variable:
            // Variables use their placeholders as derivatives.
            let placeholders = derivative.placeholdersForVariable(obj)
            change = RelationChange(added: placeholders.added, removed: placeholders.removed)
        default:
            // Other non-intermediate relations are constant in the face of changes, so we're just nil.
            change = RelationChange(added: nil, removed: nil)
        }
        if let debugName = relation.debugName {
            _ = change.added?.setDebugName("Added component of derivative of \(debugName)")
            _ = change.removed?.setDebugName("Removed component of derivative of \(debugName)")
        }
        return change
    }
}

extension RelationDifferentiator {
    fileprivate func intermediateDerivative(_ r: IntermediateRelation) -> RelationChange {
        switch r.op {
        case .union:
            return unionDerivative(r)
        case .intersection:
            return intersectionDerivative(r)
        case .difference:
            return differenceDerivative(r)
        case .project(let scheme):
            return projectionDerivative(r, scheme: scheme)
        case .select(let expression):
            return selectDerivative(r, expression: expression)
        case .mutableSelect(let expression):
            return mutableSelectDerivative(r, expression: expression)
        case .equijoin(let matching):
            return equijoinDerivative(r, matching: matching)
        case .rename(let renames):
            return renameDerivative(r, renames: renames)
        case .update(let newValues):
            return updateDerivative(r, newValues: newValues)
        case .aggregate(let attribute, let initialValue, let aggregateFunction):
            return aggregateDerivative(r, attribute: attribute, initialValue: initialValue, aggregateFunction: aggregateFunction)
        case .otherwise:
            return otherwiseDerivative(r)
        case .unique:
            return uniqueDerivative(r)
        }
    }
    
    fileprivate func unionDerivative(_ r: IntermediateRelation) -> RelationChange {
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
    
    fileprivate func intersectionDerivative(_ r: IntermediateRelation) -> RelationChange {
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
    
    fileprivate func differenceDerivative(_ r: IntermediateRelation) -> RelationChange {
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
    
    fileprivate func projectionDerivative(_ r: IntermediateRelation, scheme: Scheme) -> RelationChange {
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
    
    fileprivate func selectDerivative(_ r: IntermediateRelation, expression: SelectExpression) -> RelationChange {
        // Our changes are equal to the underlying changes with the same select applied.
        // (select A)' = select A'
        let underlyingDerivative = derivativeOf(r.operands[0])
        return RelationChange(added: underlyingDerivative.added?.select(expression),
                              removed: underlyingDerivative.removed?.select(expression))
    }
    
    fileprivate func mutableSelectDerivative(_ r: IntermediateRelation, expression: SelectExpression) -> RelationChange {
        // This is like the plain select derivative, but we add in changes made to the select expression
        // itself as well. It's never possible to have changes made to the select expression itself at
        // the same time as there are changes made to operands (for now?) so there doesn't need to be
        // any fancy business when combining them.
        let underlyingDerivative = derivativeOf(r.operands[0])
        let changesFromUnderlying = RelationChange(added: underlyingDerivative.added?.select(expression),
                                                   removed: underlyingDerivative.removed?.select(expression))
        let placeholders = derivative.placeholdersForVariable(r)
        return RelationChange(
            added: changesFromUnderlying.added + placeholders.added,
            removed: changesFromUnderlying.removed + placeholders.removed)
    }
    
    fileprivate func equijoinDerivative(_ r: IntermediateRelation, matching: [Attribute: Attribute]) -> RelationChange {
        let A = r.operands[0]
        let B = r.operands[1]
        let oldA = preChangeRelation(A)
        let oldB = preChangeRelation(B)
        let dA = derivativeOf(A)
        let dB = derivativeOf(B)
        
        // When a row is added to A, then matching it with B is added to the join itself.
        // When a row is removed from A, then matching it with the old B will be what is removed from the join.
        // Likewise in reverse.
        
        let addsFromA = dA.added?.equijoin(B, matching: matching)
        let removesFromA = dA.removed?.equijoin(oldB, matching: matching)
        
        let addsFromB = dB.added.map({ A.equijoin($0, matching: matching) })
        let removesFromB = dB.removed.map({ (oldA).equijoin($0, matching: matching) })
        
        return RelationChange(added: addsFromA + addsFromB, removed: removesFromA + removesFromB)
    }
    
    fileprivate func renameDerivative(_ r: IntermediateRelation, renames: [Attribute: Attribute]) -> RelationChange {
        // Changes are the same, but renamed.
        // (rename A)' = rename A'
        let underlyingDerivative = derivativeOf(r.operands[0])
        return RelationChange(added: underlyingDerivative.added?.renameAttributes(renames),
                                  removed: underlyingDerivative.removed?.renameAttributes(renames))
    }
    
    fileprivate func updateDerivative(_ r: IntermediateRelation, newValues: Row) -> RelationChange {
        // Our updates are equal to the projected updates joined with our newValues.
        // (update A newValues)' = (projected A') join newValues
        let untouchedScheme = Scheme(attributes: Set(r.operands[0].scheme.attributes.subtracting(newValues.attributes)))
        let projectionDerivative = self.projectionDerivative(r, scheme: untouchedScheme)
        return RelationChange(added: projectionDerivative.added?.join(ConcreteRelation(newValues)),
                              removed: projectionDerivative.removed?.join(ConcreteRelation(newValues)))
    }
    
    fileprivate func aggregateDerivative(_ r: IntermediateRelation, attribute: Attribute, initialValue: RelationValue?, aggregateFunction: @escaping (RelationValue?, [Row]) -> Result<RelationValue, RelationError>) -> RelationChange {
        // Do a brute before/after difference.
        // A' = (new A) - (old A)
        // We called this approach "dumb and inefficient"; is there a better way here?
        let debugName = r.debugName ?? "<unknown>"
        let preChangeRelation = self.preChangeRelation(r.operands[0])
            .setDebugName("aggregateDerivative preChangeRelation for \(debugName)")
        let previousAgg = IntermediateRelation(op: .aggregate(attribute, initialValue, aggregateFunction), operands: [preChangeRelation])
            .setDebugName("aggregateDerivative previousAgg for \(debugName)")
        return RelationChange(added: r.difference(previousAgg),
                                  removed: previousAgg.difference(r))
    }
    
    fileprivate func otherwiseDerivative(_ r: IntermediateRelation) -> RelationChange {
        // Do another brute before/after difference.
        // A' = (new A) - (old A)
        let debugName = r.debugName ?? "<unknown>"
        let preChangeRelations = r.operands.map(self.preChangeRelation).map({
            $0.setDebugName("otherwiseDerivative preChangeRelation for \(debugName)")
        })
        let previousOtherwise = IntermediateRelation(op: .otherwise, operands: preChangeRelations)
            .setDebugName("otherwiseDerivative previousOtherwise for \(debugName)")
        return RelationChange(added: r.difference(previousOtherwise),
                              removed: previousOtherwise.difference(r))
    }
    
    fileprivate func uniqueDerivative(_ r: IntermediateRelation) -> RelationChange {
        // Do another brute before/after difference.
        // A' = (new A) - (old A)
        let debugName = r.debugName ?? "<unknown>"
        let preChangeRelations = r.operands.map(self.preChangeRelation).map({
            $0.setDebugName("otherwiseDerivative preChangeRelation for \(debugName)")
        })
        let previousUnique = IntermediateRelation(op: r.op, operands: preChangeRelations)
            .setDebugName("uniqueDerivative previousUnique for \(debugName)")
        return RelationChange(added: r.difference(previousUnique),
                              removed: previousUnique.difference(r))
    }
}

extension RelationDifferentiator {
    fileprivate func union(_ relations: [Relation?]) -> Relation? {
        let nonnil = relations.flatMap({ $0 })
        if nonnil.isEmpty {
            return nil
        } else if nonnil.count == 1 {
            return nonnil[0]
        } else {
            return IntermediateRelation.union(nonnil)
        }
    }
    
    fileprivate func intersection(_ relations: [Relation?]) -> Relation? {
        let nonnil = relations.flatMap({ $0 })
        if nonnil.isEmpty || nonnil.count != relations.count {
            return nil
        } else if nonnil.count == 1 {
            return nonnil[0]
        } else {
            return IntermediateRelation.intersection(nonnil)
        }
    }
    
    fileprivate func difference(_ a: Relation?, _ b: Relation?) -> Relation? {
        if let a = a, let b = b {
            return a.difference(b)
        } else if let a = a {
            return a
        } else {
            return nil
        }
    }
    
    fileprivate func preChangeRelation(_ r: Relation) -> Relation {
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
    
    fileprivate func preChangeRelations(_ relations: [Relation]) -> [Relation] {
        return relations.map(self.preChangeRelation)
    }
}
