//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


/// Silly placeholder until we figure out what the error type should actually look like.
public typealias RelationError = Error

public protocol Relation: CustomStringConvertible, PlaygroundMonospace {
    var scheme: Scheme { get }
    
    var contentProvider: RelationContentProvider { get }

    func contains(_ row: Row) -> Result<Bool, RelationError>
    
    mutating func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError>
    
    /// Add an observer which is notified when the content of the Relation
    /// changes. The return value is a function which removes the observation when
    /// invoked. The caller can use that function to cancel the observation when
    /// it no longer needs it.
    func addChangeObserver(_ observer: RelationObserver, kinds: [RelationObservationKind]) -> ((Void) -> Void)
    
    func union(_ other: Relation) -> Relation
    func intersection(_ other: Relation) -> Relation
    func difference(_ other: Relation) -> Relation
    
    func join(_ other: Relation) -> Relation
    func equijoin(_ other: Relation, matching: [Attribute: Attribute]) -> Relation
    func thetajoin(_ other: Relation, query: SelectExpression) -> Relation
    func split(_ query: SelectExpression) -> (Relation, Relation)
    func divide(_ other: Relation) -> Relation
    
    func leftOuterJoin(_ other: Relation) -> Relation
    
    func min(_ attribute: Attribute) -> Relation
    func max(_ attribute: Attribute) -> Relation
    func count() -> Relation
    
    /// Return a new Relation that resolves to this Relation when it is non-empty, otherwise
    /// resolves to the other Relation.
    func otherwise(_ other: Relation) -> Relation
    
    /// Return a new Relation that resolves to this Relation when there is a unique value
    /// for the given attribute that is the same as `matching`, otherwise resolves to an
    /// empty Relation.
    func unique(_ attribute: Attribute, matching: RelationValue) -> Relation
    
    func select(_ rowToFind: Row) -> Relation
    func select(_ query: SelectExpression) -> Relation
    
    /// Return a new Relation that is this Relation with the given update applied to it.
    func withUpdate(_ query: SelectExpression, newValues: Row) -> Relation
    
    /// The same as the two-parameter withUpdate, but it updates all rows.
    func withUpdate(_ newValues: Row) -> Relation
    
    func renameAttributes(_ renames: [Attribute: Attribute]) -> Relation
}

public enum RelationContentProvider {
    case generator((Void) -> AnyIterator<Result<Row, RelationError>>)
    case set((Void) -> Swift.Set<Row>)
    case intermediate(IntermediateRelation.Operator, [Relation])
    case underlying(Relation)
}

public enum RelationObservationKind {
    /// A change due to something in the Relation itself.
    case directChange
    
    /// A change due to something in a dependency of an intermediate relation, not the Relation itself.
    case dependentChange
}

extension Relation {
    /// A shortcut that adds a change observer for all kinds.
    public func addChangeObserver(_ observer: RelationObserver) -> ((Void) -> Void) {
        return addChangeObserver(observer, kinds: [.directChange, .dependentChange])
    }
}

extension Relation {
    /// Return a generator which iterates over the contents of the Relation. It tries to perform incremental
    /// work on each pass, although currently the amount of work is potentially unbounded (but should be
    /// mostly small). On each iteration, the result may be an error (if one was encountered while building
    /// the output data), or a set of output rows.
    ///
    /// Each iteration may produce many output rows (if the work done suddenly produces a bunch, as is the
    ///case with many operations which need to buffer data), one output row (if you have a very
    /// straightforward Relation, or the stars line up), or zero output rows (if the incremental work done
    /// ended up just noticing the end of rows in some Relation, or if it produced some rows internally but
    /// they all got buffered). There may still be more data coming if zero rows are returned, so code
    /// accordingly.
    public func bulkRows() -> AnyIterator<Result<Set<Row>, RelationError>> {
        var collectedOutput: Set<Row> = []
        var error: RelationError?
        func outputCallback(_ result: Result<Set<Row>, RelationError>) {
            switch result {
            case .Ok(let rows):
                collectedOutput.formUnion(rows)
            case .Err(let err):
                error = err
            }
        }
        
        let data = LogRelationIterationBegin(self)
        let planner = QueryPlanner(roots: [(self, DirectDispatchContext().wrap(outputCallback))])
        let runner = QueryRunner(planner: planner)
        
        let generator = AnyIterator({ Void -> Result<Set<Row>, RelationError>? in
            if runner.done { return nil }
            
            runner.pump()
            
            if let error = error {
                return .Err(error)
            } else {
                let rows = collectedOutput
                collectedOutput.removeAll(keepingCapacity: true)
                return .Ok(rows)
            }
        })
        return LogRelationIterationReturn(data, generator)
    }
    
    /// A wrapper on bulkRows() which returns exactly one row (or error) per iteration. This can be more
    /// convenient to work with, but gives you less control over how much work is done on each iteration.
    public func rows() -> AnyIterator<Result<Row, RelationError>> {
        var buffer: Set<Row> = []
        let bulkGenerator = bulkRows()
        return AnyIterator({
            while true {
                if let bufferRow = buffer.popFirst() {
                    return .Ok(bufferRow)
                } else {
                    let nextBulk = bulkGenerator.next()
                    switch nextBulk {
                    case .some(.Ok(let rows)):
                        buffer = rows
                    case .some(.Err(let err)):
                        return .Err(err)
                    case nil:
                        return nil
                    }
                }
            }
        })
    }
}

extension Relation {
    /// Fetch rows and invoke a callback as they come in. Each call is passed one or more rows, or an error.
    /// If no error occurs, the sequence of calls is terminated by a final call which passes zero rows.
    public func asyncBulkRows(_ callback: DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>) {
        RunloopQueryManager.currentInstance.registerQuery(self, callback: callback)
    }
    
    /// Fetch rows and invoke a callback as they come in. Each call is passed one or more rows, or an error.
    /// If no error occurs, the sequence of calls is terminated by a final call which passes zero rows.
    public func asyncBulkRows(_ callback: @escaping (Result<Set<Row>, RelationError>) -> Void) {
        RunloopQueryManager.currentInstance.registerQuery(self, callback: callback)
    }
    
    /// Fetch all rows and invoke a callback when complete.
    public func asyncAllRows(_ callback: DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>) {
        var allRows: Set<Row> = []
        asyncBulkRows(DirectDispatchContext().wrap({ result in
            switch result {
            case .Ok([]):
                callback.withWrapped({ $0(.Ok(allRows)) })
            case .Ok(let rows):
                allRows.formUnion(rows)
            
            case .Err(QueryRunner.Error.mutatedDuringEnumeration):
                allRows = []
                self.asyncAllRows(callback)
            case .Err:
                callback.withWrapped({ $0(result) })
            }
        }))
    }
    
    /// Fetch all rows and invoke a callback on the current runloop when complete.
    public func asyncAllRows(_ callback: @escaping (Result<Set<Row>, RelationError>) -> Void) {
        asyncAllRows(CFRunLoopGetCurrent().wrap(callback))
    }
    
    /// Fetch all rows and invoke a callback on the current runloop when complete. The postprocessor is run on the background first.
    public func asyncAllRows<T>(postprocessor: @escaping (Set<Row>) -> T, completion: @escaping (Result<T, RelationError>) -> Void) {
        let runloop = CFRunLoopGetCurrent()!
        asyncAllRows(DirectDispatchContext().wrap({
            let postprocessedResult = $0.map(postprocessor)
            runloop.async({ completion(postprocessedResult) })
        }))
    }
}

extension Relation {
    public func union(_ other: Relation) -> Relation {
        return IntermediateRelation.union([self, other])
    }
    
    public func intersection(_ other: Relation) -> Relation {
        return IntermediateRelation.intersection([self, other])
    }
    
    public func difference(_ other: Relation) -> Relation {
        return IntermediateRelation(op: .difference, operands: [self, other])
    }
    
    public func project(_ scheme: Scheme) -> Relation {
        return IntermediateRelation(op: .project(scheme), operands: [self])
    }

    /// Returns a projection of this Relation that includes only those attributes that appear in this Relation's
    /// scheme but not in the given scheme.
    public func project(dropping scheme: Scheme) -> Relation {
        return project(Scheme(attributes: self.scheme.attributes.subtracting(scheme.attributes)))
    }

    public func project(_ attribute: Attribute) -> Relation {
        return project([attribute])
    }

    public func join(_ other: Relation) -> Relation {
        let intersectedScheme = Scheme(attributes: self.scheme.attributes.intersection(other.scheme.attributes))
        let matching = Dictionary(intersectedScheme.attributes.map({ ($0, $0) }))
        return equijoin(other, matching: matching)
    }
    
    public func equijoin(_ other: Relation, matching: [Attribute: Attribute]) -> Relation {
        return IntermediateRelation(op: .equijoin(matching), operands: [self, other])
    }
    
    public func thetajoin(_ other: Relation, query: SelectExpression) -> Relation {
        return self.join(other).select(query)
    }
    
    public func split(_ query: SelectExpression) -> (Relation, Relation) {
        let matching = select(query)
        let notmatching = difference(matching)
        return (matching, notmatching)
    }
    
    public func divide(_ other: Relation) -> Relation {
        let resultingScheme = Scheme(attributes: self.scheme.attributes.subtracting(other.scheme.attributes))
        let allCombinations = self.project(resultingScheme).join(other)
        let subtracted = allCombinations.difference(self)
        let projected = subtracted.project(resultingScheme)
        return self.project(resultingScheme).difference(projected)
    }
    
    public func leftOuterJoin(_ other: Relation) -> Relation {
        // TODO: Optimize this
        let joined = self.join(other)
        let projected = joined.project(self.scheme)
        let difference = self.difference(projected)
        let attrsUniqueToOther = joined.scheme.attributes.symmetricDifference(self.scheme.attributes)
        let otherNulls = MakeRelation(Array(attrsUniqueToOther), Array(repeating: .null, count: attrsUniqueToOther.count))
        let differenceWithNulls = difference.join(otherNulls)
        return differenceWithNulls.union(joined)
    }
}

extension Relation {
    public func min(_ attribute: Attribute) -> Relation {
        return IntermediateRelation.aggregate(self, attribute: attribute, initial: nil, agg: Swift.min)
    }
    
    public func max(_ attribute: Attribute) -> Relation {
        return IntermediateRelation.aggregate(self, attribute: attribute, initial: nil, agg: Swift.max)
    }
    
    public func count() -> Relation {
        func count(_ count: RelationValue?, currentValueIgnore: RelationValue) -> Result<RelationValue, RelationError> {
            let countInt: Int64 = count!.get()!
            return .Ok(RelationValue.integer(countInt + 1))
        }
        return IntermediateRelation(op: .aggregate("count", 0, count), operands: [self])
    }
}

extension Relation {
    public func otherwise(_ other: Relation) -> Relation {
        precondition(self.scheme.attributes == other.scheme.attributes)
        return IntermediateRelation(op: .otherwise, operands: [self, other])
    }
    
    public func unique(_ attribute: Attribute, matching: RelationValue) -> Relation {
        return IntermediateRelation(op: .unique(attribute, matching), operands: [self])
    }
}

extension Relation {
    public func select(_ rowToFind: Row) -> Relation {
        let rowScheme = Set(rowToFind.map({ $0.0 }))
        precondition(rowScheme.isSubset(of: scheme.attributes))
        return select(SelectExpressionFromRow(rowToFind))
    }
    
    public func select(_ query: SelectExpression) -> Relation {
        return IntermediateRelation(op: .select(query), operands: [self])
    }
}

extension Relation {
    public func renameAttributes(_ renames: [Attribute: Attribute]) -> Relation {
        return IntermediateRelation(op: .rename(renames), operands: [self])
    }
    
    public func renamePrime() -> Relation {
        let renames = Dictionary(scheme.attributes.map({ ($0, Attribute($0.name + "'")) }))
        return renameAttributes(renames)
    }
}

extension Relation {
    public func withUpdate(_ query: SelectExpression, newValues: Row) -> Relation {
        // Pick out the rows which will be updated, and update them.
        let toUpdate = self.select(query)
        let updatedValues = toUpdate.withUpdate(newValues)
        
        // Pick out the rows not selected for the update.
        let nonUpdated = self.select(*!query)
        
        // The result is the union of the updated values and the rows not selected.
        return nonUpdated.union(updatedValues)
    }
    
    public func withUpdate(_ newValues: Row) -> Relation {
        return IntermediateRelation(op: .update(newValues), operands: [self])
    }
}

extension Relation {
    public var isEmpty: Result<Bool, RelationError> {
        switch rows().next() {
        case .none: return .Ok(true)
        case .some(.Ok): return .Ok(false)
        case .some(.Err(let e)): return .Err(e)
        }
    }
}

extension Relation {
    public var description: String {
        return descriptionWithRows(self.rows())
    }
    
    public func descriptionWithRows(_ rows: AnyIterator<Result<Row, RelationError>>) -> String {
        let columns = scheme.attributes.sorted()
        let rows = rows.map({ row in
            columns.map({ (col: Attribute) -> String in
                switch row.map({ $0[col] }) {
                case .Ok(let value):
                    return String(describing: value)
                case .Err(let err):
                    return "Err(\(err))"
                }
            })
        })
        
        let all = ([columns.map({ $0.name })] + rows)
        let lengths = all.map({ $0.map({ $0.characters.count }) })
        let columnLengths = (0 ..< columns.count).map({ index in
            return lengths.map({ $0[index] }).reduce(0, Swift.max)
        })
        let padded = all.map({ zip(columnLengths, $0).map({ $1.pad(to: $0, with: " ") }) })
        let joined = padded.map({ $0.joined(separator: "  ") })
        return joined.joined(separator: "\n")
    }
}

extension Relation {
    public func addChangeObserver(_ f: @escaping (RelationChange) -> Void) -> ((Void) -> Void) {
        let x = addChangeObserver(SimpleRelationObserverProxy(f: f))
        return x
    }
    
    public func addWeakChangeObserver<T: AnyObject>(_ target: T, method: @escaping (T) -> (RelationChange) -> Void) {
        var relationRemove: ((Void) -> Void)? = nil
        var deallocRemove: ((Void) -> Void)? = nil
        
        relationRemove = self.addChangeObserver({ [weak target] in
            if let target = target {
                method(target)($0)
            } else {
                guard let relationRemove = relationRemove else { preconditionFailure("Change observer fired but relation remove function was never set!") }
                relationRemove()
                
                guard let deallocRemove = deallocRemove else { preconditionFailure("Change observer fired but target remove function was never set!") }
                deallocRemove()
            }
        })
        
        deallocRemove = ObserveDeallocation(target, {
            guard let relationRemove = relationRemove else { preconditionFailure("Dealloc observation fired but relation remove function was never set!") }
            relationRemove()
        })
    }
    
    public func addWeakChangeObserver<T: AnyObject>(_ target: T, call: @escaping (T, RelationChange) -> Void) {
        addWeakChangeObserver(target, method: { obj in { change in call(obj, change) } })
    }
}
