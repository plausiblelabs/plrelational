//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


/// Silly placeholder until we figure out what the error type should actually look like.
public typealias RelationError = Error

public typealias RelationObject = Relation & AnyObject

/// A protocol defining a relation, which is conceptually a set of `Row`s, all of which have
/// the same scheme.
public protocol Relation: CustomStringConvertible, PlaygroundMonospace {
    /// The relation's scheme.
    var scheme: Scheme { get }
    
    /// :nodoc:
    /// A value which defines how the `Relation`'s content is provided. Content can be provided directly,
    /// as an operator on other `Relation`s, or by deferring to another `Relation` entirely.
    var contentProvider: RelationContentProvider { get }
    
    /// The debug name for the `Relation`, which can be handy for identifying them in debug dumps.
    var debugName: String? { get set }
    
    /// Return `true` if the given row is contained in the `Relation`, and false if not.
    func contains(_ row: Row) -> Result<Bool, RelationError>
    
    /// :nodoc:
    /// Add an observer which is notified when the content of the Relation
    /// changes. The return value is a function which removes the observation when
    /// invoked. The caller can use that function to cancel the observation when
    /// it no longer needs it.
    func addChangeObserver(_ observer: RelationObserver, kinds: [RelationObservationKind]) -> ((Void) -> Void)

    // MARK: Core relational algebra
    
    func project(_ scheme: Scheme) -> Relation
    func project(dropping scheme: Scheme) -> Relation
    func project(_ attribute: Attribute) -> Relation

    /// Perform a select operation with a query defined by the contents of a `Row`. The
    /// resulting query is equivalent to ANDing together an equality expression for each
    /// attribute in the row, requiring it to be equal to that value in the row.
    func select(_ rowToFind: Row) -> Relation
    
    /// Perform a select operation with the given query.
    func select(_ query: SelectExpression) -> Relation
    
    /// Return a new `Relation` that renames the `Attribute`s in the keys of `renames` to the
    /// corresponding values.
    func renameAttributes(_ renames: [Attribute: Attribute]) -> Relation
    func renamePrime() -> Relation
    
    /// Return a new `Relation` which represents the union of this `Relation` and another one.
    func union(_ other: Relation) -> Relation
    
    /// Return a new `Relation` which represents the intersection of this `Relation` and another one.
    func intersection(_ other: Relation) -> Relation
    
    /// Return a new `Relation` which represents the difference of this `Relation` and another one.
    func difference(_ other: Relation) -> Relation
    
    /// Return a new `Relation` which represents the join of this `Relation` and another one.
    /// This is equivalent to an `equijoin` where the matches are equal to the intersection of
    /// the two schemes.
    func join(_ other: Relation) -> Relation
    
    /// Return a new `Relation` which represents the join of this `Relation` and another one,
    /// matching the values for the attributes given in the `matching` parameter.
    ///
    /// - parameter other: The Relation to join with.
    /// - parameter matching: A dictionary which describes the matches to perform for the join.
    ///                       The value for the key `Attribute` in this `Relation` will be matched
    ///                       with the value for the value `Attribute` in `other`.
    func equijoin(_ other: Relation, matching: [Attribute: Attribute]) -> Relation
    func thetajoin(_ other: Relation, query: SelectExpression) -> Relation
    func split(_ query: SelectExpression) -> (Relation, Relation)
    func divide(_ other: Relation) -> Relation

    // MARK: Relational algebra extensions

    func leftOuterJoin(_ other: Relation) -> Relation

    // MARK: Aggregate operations
    
    func min(_ attribute: Attribute) -> Relation
    func max(_ attribute: Attribute) -> Relation
    func count() -> Relation

    // MARK: Experimental operations

    /// Return a new `Relation` that resolves to this Relation when it is non-empty, otherwise
    /// resolves to the other Relation.
    func otherwise(_ other: Relation) -> Relation
    
    /// Return a new `Relation` that resolves to this Relation when there is a unique value
    /// for the given attribute that is the same as `matching`, otherwise resolves to an
    /// empty Relation.
    func unique(_ attribute: Attribute, matching: RelationValue) -> Relation
    
    // MARK: Synchronous updates
    
    /// :nodoc:
    /// Update the `Relation` content by assigning the given values to all rows which match the query.
    mutating func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError>
    
    /// :nodoc:
    /// Return a new Relation that is this Relation with the given update applied to it.
    func withUpdate(_ query: SelectExpression, newValues: Row) -> Relation
    
    /// :nodoc:
    /// The same as the two-parameter withUpdate, but it updates all rows.
    func withUpdate(_ newValues: Row) -> Relation
}

/// :nodoc:
/// A value which describes how a `Relation` produces values.
public enum RelationContentProvider {
    /// The `Relation` produces values by providing a generator. The first associated value is a function which,
    /// when called, produces an iterator. The iterator produces sets of rows, or errors. Depending on the
    /// underlying implementation, the iterator may produce a single set containing all rows, a bunch of sets
    /// containing individual rows, or anything in between.
    ///
    /// The `approximateCount` associated value is an optional approximate count of the number of rows in the
    /// `Relation`. Providing a value here can help the query optimizer/runner be more efficient. If `nil` is
    /// provided for this value, then it will be assumed that the number of rows in the `Relation` is large.
    case generator((Void) -> AnyIterator<Result<Set<Row>, RelationError>>, approximateCount: Double?)
    
    /// The `Relation` produces values by providing a generator which can be filtered, hopefully efficiently,
    /// with a `SelectExpression`. The query optimizer/runner will take advantage of this to request only
    /// the rows needed to fulfill a request, rather than requesting all rows, when possible.
    ///
    /// The first associated value is a function which, when called with a `SelectExpression`, produces an iterator.
    /// The iterator produces sets of rows which match the expression, or errors.
    ///
    /// The `approximateCount` associated value is a function which takes a `SelectExpression` and returns the
    /// approximate number of matching rows this `Relation` contains. This helps the query optimizer/runner, as
    /// described in `generator`.
    case efficientlySelectableGenerator((SelectExpression) -> AnyIterator<Result<Set<Row>, RelationError>>, approximateCount: (SelectExpression) -> Double?)
    
    /// The `Relation` produces values by providing a plain `Set` of rows. The first associated value is a function
    /// which, when called, provides the set. This is suitable for `Relations` which store rows in memory as a `Set`
    /// and can provide it directly.
    ///
    /// The `approximateCount` associated value describes the approximate number of rows in the `Relation`, as
    /// described in `generator`.
    case set((Void) -> Swift.Set<Row>, approximateCount: Double?)
    
    /// The `Relation` doesn't contain any values, but represents the result of applying the given operator to
    /// the given `Relation` operands.
    case intermediate(IntermediateRelation.Operator, [Relation])
    
    /// The `Relation` doesn't contain any values, but has an underlying `Relation` which can provide values.
    case underlying(Relation)
}

/// :nodoc:
/// A value describing the kind of change made to a `Relation`.
public enum RelationObservationKind {
    /// A change due to something in the Relation itself.
    case directChange
    
    /// A change due to something in a dependency of an intermediate relation, not the Relation itself.
    case dependentChange
}

extension Relation {
    
    // MARK: Debugging
    
    /// Set the debug name and return self, for convenient chaining.
    /// Value-type relations return a new one rather than mutating in place.
    public func setDebugName(_ name: String) -> Self {
        var result = self
        result.debugName = name
        return result
    }
}

/// :nodoc:
extension Relation {
    /// A shortcut that adds a change observer for all kinds.
    public func addChangeObserver(_ observer: RelationObserver) -> ((Void) -> Void) {
        return addChangeObserver(observer, kinds: [.directChange, .dependentChange])
    }
}

/// :nodoc:
extension Relation {
    
    // MARK: Synchronous fetch

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
    
    // MARK: Asynchronous fetch
    
    /// Fetch rows and invoke a callback as they come in. Each call is passed one or more rows, or an error.
    /// If no error occurs, the sequence of calls is terminated by a final call which passes zero rows.
    public func asyncBulkRows(_ callback: DispatchContextWrapped<(Result<Set<Row>, RelationError>) -> Void>) {
        AsyncManager.currentInstance.registerQuery(self, callback: callback)
    }
    
    /// Fetch rows and invoke a callback as they come in. Each call is passed one or more rows, or an error.
    /// If no error occurs, the sequence of calls is terminated by a final call which passes zero rows.
    public func asyncBulkRows(_ callback: @escaping (Result<Set<Row>, RelationError>) -> Void) {
        AsyncManager.currentInstance.registerQuery(self, callback: AsyncManager.currentInstance.runloopDispatchContext().wrap(callback))
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
        asyncAllRows(AsyncManager.currentInstance.runloopDispatchContext().wrap(callback))
    }
    
    /// Fetch all rows and invoke a callback on the current runloop when complete. The postprocessor is run on the background first.
    public func asyncAllRows<T>(postprocessor: @escaping (Set<Row>) -> T, completion: @escaping (Result<T, RelationError>) -> Void) {
        let context = AsyncManager.currentInstance.runloopDispatchContext()
        asyncAllRows(DirectDispatchContext().wrap({
            let postprocessedResult = $0.map(postprocessor)
            context.async({ completion(postprocessedResult) })
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
        return project(Scheme(attributes: self.scheme.attributes.fastSubtracting(scheme.attributes)))
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
        let resultingScheme = Scheme(attributes: self.scheme.attributes.fastSubtracting(other.scheme.attributes))
        let allCombinations = self.project(resultingScheme).join(other)
        let subtracted = allCombinations.difference(self)
        let projected = subtracted.project(resultingScheme)
        return self.project(resultingScheme).difference(projected)
    }
    
    public func leftOuterJoin(_ other: Relation) -> Relation {
        // TODO: Optimize this
        let debugPrefix = (self.debugName ?? "<unknown>") + " leftOuterJoin"
        
        let joined = self.join(other).setDebugName("\(debugPrefix) initial join")
        let projected = joined.project(self.scheme).setDebugName("\(debugPrefix) projected")
        let difference = self.difference(projected).setDebugName("\(debugPrefix) difference")
        let attrsUniqueToOther = joined.scheme.attributes.symmetricDifference(self.scheme.attributes)
        let otherNulls = MakeRelation(Array(attrsUniqueToOther), Array(repeating: .null, count: attrsUniqueToOther.count)).setDebugName("\(debugPrefix) otherNulls")
        let differenceWithNulls = difference.join(otherNulls).setDebugName("\(debugPrefix) differenceWithNulls")
        return differenceWithNulls.union(joined).setDebugName(debugPrefix)
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
        func count(_ count: RelationValue?, rows: [Row]) -> Result<RelationValue, RelationError> {
            let countInt: Int64 = count!.get()!
            return .Ok(RelationValue.integer(countInt + Int64(rows.count)))
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

/// :nodoc:
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

/// :nodoc:
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
    
    // MARK: Description
    
    public var description: String {
        return descriptionWithRows(self.rows())
    }
    
    /// :nodoc:
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

/// :nodoc:
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
