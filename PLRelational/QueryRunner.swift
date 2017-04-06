//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

open class QueryRunner {
    var nodes: [QueryPlanner.Node]
    fileprivate var outputCallbacks: [QueryPlanner.OutputCallback]
    
    fileprivate var activeInitiatorIndexes: [Int]
    
    fileprivate var initiatorGenerators: Dictionary<Int, AnyIterator<Result<Row, RelationError>>> = [:]
    
    fileprivate var intermediatesToProcess: [IntermediateToProcess] = []
    
    var nodeStates: [NodeState]
    
    open fileprivate(set) var done = false
    open fileprivate(set) var didError = false
    
    init(planner: QueryPlanner) {
        let nodes = planner.nodes
        self.nodes = nodes
        self.outputCallbacks = planner.allOutputCallbacks
        
        activeInitiatorIndexes = planner.initiatorIndexes.sorted(by: {
            // Put the smallest initiators where they will be used first. Initiators are
            // read from the end of `activeInitiatorIndexes` and then popped as they're
            // drained, so the smallest ones should go at the end.
            
            // Initiators with no count are considered to be larger than anything with a count.
            let count0 = nodes[$0].approximateCount ?? .infinity
            let count1 = nodes[$1].approximateCount ?? .infinity
            return count0 > count1
        })
        nodeStates = Array()
        nodeStates.reserveCapacity(nodes.count)
        for index in nodes.indices {
            nodeStates.append(NodeState(nodes: nodes, nodeIndex: index))
        }
        computeParentChildIndexes()
        computeTransactionalDatabases(planner.transactionalDatabases)
        propagateSelects()
    }
    
    /// Fill out each NodeState's `parentChildIndexes` array by scanning their parents.
    /// This computes each child's index within the parent, which the other code needs
    /// in order to write data and propagate EOF info.
    fileprivate func computeParentChildIndexes() {
        for nodeIndex in nodeStates.indices {
            nodeStates[nodeIndex].parentChildIndexes.reserveCapacity(nodes[nodeIndex].parentIndexes.count)
            
            // This would be simple, except that it's possible for the same parent to be in `parentIndexes` more
            // than once. In that scenario, the parent's `childIndexes` will also have multiple entries pointing
            // to the child. The child needs to collect all of those indexes. To simplify the computation, we
            // first sort the parent indexes so that all identical parents are adjacent. (The order of `parentIndexes`
            // does NOT matter, except that it needs to correspond with the items in `parentChildIndexes` which we
            // haven't computed yet.) We then skip over runs of duplicate parents, and add all matching indexes
            // from the parent when we encounter the first one. The result is that everything lines up.
            nodes[nodeIndex].parentIndexes.fastSmallSortInPlace()
            
            let parentIndexes = nodes[nodeIndex].parentIndexes
            let parentIndexesCount = parentIndexes.count
            var parentIndexesIndex = 0
            while parentIndexesIndex < parentIndexesCount {
                let parentIndex = parentIndexes[parentIndexesIndex]
                let parentNode = nodes[parentIndex]
                
                nodeStates[nodeIndex].parentChildIndexes.append(contentsOf: parentNode.childIndexes.indexesOf(nodeIndex))
                
                while parentIndexesIndex < parentIndexesCount && parentIndex == parentIndexes[parentIndexesIndex] {
                    parentIndexesIndex += 1
                }
            }
        }
    }
    
    /// Scan the nodes for any select operations, and propagate them to their children.
    /// This allows children to efficiently select stuff out of backing stores that support it.
    fileprivate func propagateSelects() {
        for nodeIndex in nodeStates.indices {
            if case .select(let expression) = nodes[nodeIndex].op {
                nodeStates[nodeIndex].parentalSelectPropagationDisabled = true
                for child in nodes[nodeIndex].childIndexes {
                    addSelect(node: child, expression: expression)
                }
            }
        }
    }
    
    /// For each node associated with a TransactionalDatabase, mark that node and all of its children
    /// as associated with that database, and fetch the database's transaction counter into the node
    /// state.
    fileprivate func computeTransactionalDatabases(_ map: ObjectDictionary<TransactionalDatabase, Int>) {
        for (db, topIndex) in map {
            db.lockReading()
            
            var queue = [topIndex]
            while let index = queue.popLast() {
                nodeStates[index].transactionalDatabase = db
                nodeStates[index].transactionalDatabaseTransactionID = db.transactionCounter
                queue.append(contentsOf: nodes[index].childIndexes)
            }
            
            db.unlockReading()
        }
    }
    
    /// Run a round of processing on the query. This will either process some intermediate nodes
    /// or generate some rows from initiator nodes. Any rows that are output from the graph during
    /// processing are returned to the caller.
    func pump() -> Void {
        let pumped = pumpIntermediates()
        if !pumped {
            let result = pumpInitiator()
            if let err = result.err {
                self.done = true
                self.didError = true
                for callback in outputCallbacks {
                    callback.withWrapped({ $0(.Err(err)) })
                }
            }
        }
    }
    
    /// Process all pending intermediate nodes. If any intermediate nodes were processed, this method
    /// returns true. If no intermediates are pending, it returns false.
    fileprivate func pumpIntermediates() -> Bool {
        guard !intermediatesToProcess.isEmpty else {
            return false
        }
        
        let localIntermediates = intermediatesToProcess
        intermediatesToProcess.removeAll(keepingCapacity: true)
        
        for intermediate in localIntermediates {
            if shouldMarkIntermediateDone(intermediate.nodeIndex) {
                markDone(intermediate.nodeIndex)
            }
            process(intermediate.nodeIndex, inputIndex: intermediate.inputIndex)
        }
        return true
    }
    
    /// Return whether a given intermediate node should be marked as done. Nodes should be marked as
    /// done if they aren't already marked, if they have zero active buffers, and they will not
    /// become an initiator.
    private func shouldMarkIntermediateDone(_ index: Int) -> Bool {
        return !nodeStates[index].didMarkDone
            && nodeStates[index].activeBuffers == 0
            && !intermediateWillBecomeInitiator(index)
    }
    
    /// Return whether a given intermediate node will become an initiator. Right now, nothing
    /// does this. We might want to ditch this functionality altogether. I'm keeping it just
    /// for the moment in case I change my mind.
    private func intermediateWillBecomeInitiator(_ index: Int) -> Bool {
        return false
    }
    
    /// Process an active initiator node. If there are no active initiator nodes, sets the `done` property
    /// to true. If the initiator node produces an error instead of a row, this method returns that error.
    fileprivate func pumpInitiator() -> Result<Void, RelationError> {
        guard let nodeIndex = activeInitiatorIndexes.last else {
            done = true
            return .Ok()
        }
        
        let db = nodeStates[nodeIndex].transactionalDatabase
        db?.lockReading()
        defer { db?.unlockReading() }
        
        // If the node is associated with a transactional database, it's now locked. Get the current transaction
        // counter and compare with what's in the node state. If it's different, then a transaction has been
        // committed since we started running, and the we're now in an invalid state. Return an error.
        if let db = db , db.transactionCounter != nodeStates[nodeIndex].transactionalDatabaseTransactionID {
            return .Err(Error.mutatedDuringEnumeration)
        }
        
        let op = nodes[nodeIndex].op
        switch op {
        case .rowGenerator(let generatorGetter):
            let row = getRowGeneratorRow(nodeIndex, generatorGetter)
            switch row {
            case .some(.Err(let err)):
                return .Err(err)
            case .some(.Ok(let row)):
                writeOutput([row], fromNode: nodeIndex)
            case .none:
                activeInitiatorIndexes.removeLast()
                markDone(nodeIndex)
            }
        case .selectableGenerator(let generatorGetter):
            let row = getRowGeneratorRow(nodeIndex, {
                return generatorGetter(nodeStates[nodeIndex].parentalSelects ?? true)
            })
            switch row {
            case .some(.Err(let err)):
                return .Err(err)
            case .some(.Ok(let row)):
                writeOutput([row], fromNode: nodeIndex)
            case .none:
                activeInitiatorIndexes.removeLast()
                markDone(nodeIndex)
            }
        case .rowSet(let rowGetter):
            writeOutput(rowGetter(), fromNode: nodeIndex)
            activeInitiatorIndexes.removeLast()
            markDone(nodeIndex)
        default:
            // These shenanigans let us print the operation without descending into an infinite recursion
            // from trying to print the contents of Relations contained within. We cut off subsequent lines
            // to avoid leaking data from the Relation contents, just in case there's something sensitive.
            var stream = ""
            dump(op, to: &stream)
            let firstLine = stream.components(separatedBy: "\n").first ?? "(empty)"
            fatalError("Unknown initiator operation \(firstLine)")
        }
        
        return .Ok()
    }
    
    fileprivate func getRowGeneratorRow(_ initiatorIndex: Int, _ generatorGetter: (Void) -> AnyIterator<Result<Row, RelationError>>) -> Result<Row, RelationError>? {
        let generator = initiatorGenerators.getOrCreate(initiatorIndex, defaultValue: generatorGetter())
        return generator.next()
    }
    
    fileprivate func writeOutput<Seq: Collection>(_ rows: Seq, fromNode: Int) where Seq.Iterator.Element == Row {
        guard !rows.isEmpty else { return }
        
        for (parentIndex, index) in zip(nodes[fromNode].parentIndexes, nodeStates[fromNode].parentChildIndexes) {
            nodeStates[parentIndex].inputBuffers[index].add(rows)
            intermediatesToProcess.append(IntermediateToProcess(nodeIndex: parentIndex, inputIndex: index))
        }
        
        if let callbacks = nodes[fromNode].outputCallbacks {
            let rowsSet = Set(rows)
            for callback in callbacks {
                callback.withWrapped({ $0(.Ok(rowsSet)) })
            }
        }
    }
    
    fileprivate func markDone(_ nodeIndex: Int) {
        nodeStates[nodeIndex].didMarkDone = true
        for (parentIndex, index) in zip(nodes[nodeIndex].parentIndexes, nodeStates[nodeIndex].parentChildIndexes) {
            nodeStates[parentIndex].setInputBufferEOF(index)
            intermediatesToProcess.append(IntermediateToProcess(nodeIndex: parentIndex, inputIndex: index))
        }
    }
    
    /// Add a dynamic select expression to a node. If propagation is still enabled, `expression` is ORed
    /// with the existing `parentalSelects`, if any. If all parents have added, then the final expression
    /// is propagated to children.
    fileprivate func addSelect(node: Int, expression: SelectExpression) {
        if nodeStates[node].parentalSelectPropagationDisabled { return }
        
        let combinedExpression = nodeStates[node].parentalSelects.map({ $0 *|| expression }) ?? expression
        nodeStates[node].parentalSelects = combinedExpression.deepSimplify()
        
        nodeStates[node].parentalSelectsRemaining -= 1
        precondition(nodeStates[node].parentalSelectsRemaining >= 0, "Added more selects to node \(node) than it has parents, which should never happen")
        if nodeStates[node].parentalSelectsRemaining == 0 {
            nodeStates[node].parentalSelectPropagationDisabled = true
            for childIndex in nodes[node].childIndexes {
                if let derivedExpression = derivedSelect(node: node, child: childIndex) {
                    addSelect(node: childIndex, expression: derivedExpression)
                }
            }
        }
    }
    
    /// Compute a propagated select for a node's children.
    /// For simple things like unions, it returns the node's own select.
    /// For joins it tries to compute the portion that applies to each child.
    /// For ones that are too difficult, it'll just give up.
    fileprivate func derivedSelect(node: Int, child: Int) -> SelectExpression? {
        guard let thisSelect = nodeStates[node].parentalSelects else { return nil }
        
        switch nodes[node].op {
        case .rowGenerator, .selectableGenerator, .rowSet:
            // These shouldn't even have children
            return nil
        case .union, .intersection, .difference:
            return thisSelect
        case .project:
            // Project just reduces the scheme so the same select will still apply
            return thisSelect
        case .select(let expression):
            return expression *&& thisSelect
        case .equijoin:
            // We could potentially be smarter about selects which have attributes from both sides.
            // But for now, just pass them through only if they deal exclusively with the attributes
            // of one side.
            let childAttributes = nodes[child].scheme.attributes
            let selectAttributes = thisSelect.allAttributes()
            return selectAttributes.isSubset(of: childAttributes) ? thisSelect : nil
            
        case .rename(let renames):
            return thisSelect.withRenamedAttributes(renames.inverted)
            
        case .update(let row):
            // This can propagate iff the select does NOT deal with any of the updated values
            let rowAttributes = row.attributes
            let selectAttributes = thisSelect.allAttributes()
            for attr in rowAttributes {
                if selectAttributes.contains(attr) {
                    return nil
                }
            }
            return thisSelect
            
        case .aggregate, .otherwise, .unique:
            // Don't even try
            return nil
        }
    }
    
    fileprivate func process(_ nodeIndex: Int, inputIndex: Int) {
        let op = nodes[nodeIndex].op
        switch op {
        case .union:
            processUnion(nodeIndex, inputIndex)
        case .intersection:
            processIntersection(nodeIndex, inputIndex)
        case .difference:
            processDifference(nodeIndex, inputIndex)
        case .project(let scheme):
            processProject(nodeIndex, inputIndex, scheme)
        case .select(let expression):
            processSelect(nodeIndex, inputIndex, expression)
        case .equijoin(let matching):
            processEquijoin(nodeIndex, inputIndex, matching)
        case .rename(let renames):
            processRename(nodeIndex, inputIndex, renames)
        case .update(let newValues):
            processUpdate(nodeIndex, inputIndex, newValues)
        case .aggregate(let attribute, let initialValue, let agg):
            processAggregate(nodeIndex, inputIndex, attribute, initialValue, agg)
        case .otherwise:
            processOtherwise(nodeIndex, inputIndex)
        case .unique(let attribute, let matching):
            processUnique(nodeIndex, inputIndex, attribute, matching)
        default:
            fatalError("Don't know how to process operation \(op)")
        }
    }
    
    // Tips for implementing a process function.
    //
    // A process function corresponds to an enum case. Add a new case to the list above. Have the
    // function take the appropriate data stored in the enum case, if any.
    //
    // The process function is called repeatedly as data flows through the system. The nodeIndex
    // indicates which node is being processed. Access node-specific data using nodeStates[nodeIndex].
    // The inputIndex indicates which input data came in on. For operations which can deal with one
    // input at a time, this can be used to avoid scanning the entire thing.
    //
    // For nodes which need to wait for complete data before they can process, check the activeBuffers
    // property to see if any data is pending. When activeBuffers is 0 then no more data will arrive.
    //
    // The process function may be called multiple times for a node even when no more data is available.
    // This can happen if data was written to it multiple times before that node was processed. Make
    // sure that the processing code correctly handles this by altering the node's state as necessary
    // so that subsequent calls produce correct output. For example, when pulling data out of an input
    // buffer, use popAll() rather than rows, so that the next call will see an empty buffer.
    //
    // For operations which need to store custom state across calls, use the getExtraState and
    // setExtraState calls. These can store arbitrary data. Single values can go in directly, or they
    // can be used with tuple types, or a struct type for more complex situations.
    
    func processUnion(_ nodeIndex: Int, _ inputIndex: Int) {
        let rows = nodeStates[nodeIndex].inputBuffers[inputIndex].popAll()
        writeOutput(nodeStates[nodeIndex].uniq(rows), fromNode: nodeIndex)
    }
    
    func processIntersection(_ nodeIndex: Int, _ inputIndex: Int) {
        // Wait until all buffers are complete before we process anything. We could optimize this a bit
        // by streaming data if all *but one* buffer is complete. Maybe later.
        if nodeStates[nodeIndex].activeBuffers > 0 {
            return
        }
        
        var accumulated: Set<Row>
        if nodeStates[nodeIndex].inputBuffers.isEmpty {
            accumulated = []
        } else {
            accumulated = Set(nodeStates[nodeIndex].inputBuffers[0].popAll())
        }
        for bufferIndex in nodeStates[nodeIndex].inputBuffers.indices.dropFirst() {
            let bufferRows = nodeStates[nodeIndex].inputBuffers[bufferIndex].popAll()
            accumulated.formIntersection(bufferRows)
        }
        writeOutput(accumulated, fromNode: nodeIndex)
    }
    
    func processDifference(_ nodeIndex: Int, _ inputIndex: Int) {
        // We compute buffer[0] - buffer[1]. buffer[1] must be complete before we can compute anything.
        // Once it is complete, we can stream buffer[0] through.
        guard nodeStates[nodeIndex].inputBuffers[1].eof else { return }
        
        let rhsMap = nodeStates[nodeIndex].getExtraState({ () -> ObjectMap<()> in
            // Note: we pull the rows here but we do *not* pop them. The map doesn't keep the rows
            // alive, so we need to keep those objects alive by holding onto the rows elsewhere.
            let rows = nodeStates[nodeIndex].inputBuffers[1].rows
            let map = ObjectMap<()>(capacity: rows.count)
            for row in rows {
                map[row.inlineRow] = ()
            }
            return map
        })
        
        let lhsRows = nodeStates[nodeIndex].inputBuffers[0].popAll()
        let subtracted = lhsRows.filter({ rhsMap[$0.inlineRow] == nil })
        
        writeOutput(subtracted, fromNode: nodeIndex)
    }
    
    func processProject(_ nodeIndex: Int, _ inputIndex: Int, _ scheme: Scheme) {
        let rows = nodeStates[nodeIndex].inputBuffers[inputIndex].popAll()
        let projected = Set(rows.map({ row -> Row in
            let subvalues = scheme.attributes.map({ ($0, row[$0]) })
            return Row(values: Dictionary(subvalues))
        }))
        writeOutput(nodeStates[nodeIndex].uniq(projected), fromNode: nodeIndex)
    }
    
    func processSelect(_ nodeIndex: Int, _ inputIndex: Int, _ expression: SelectExpression) {
        let rows = nodeStates[nodeIndex].inputBuffers[inputIndex].popAll()
        let filtered = Set(rows.filter({ expression.valueWithRow($0).boolValue }))
        writeOutput(filtered, fromNode: nodeIndex)
    }
    
    func processEquijoin(_ nodeIndex: Int, _ inputIndex: Int, _ matching: [Attribute: Attribute]) {
        // Accumulate data until at least one input is complete.
        guard nodeStates[nodeIndex].activeBuffers <= 1 else { return }
        
        // If we get no more than this many rows on the smaller side, then
        // we'll build a select out of them and pass that up the larger side.
        let maxSelectSize = 10
        
        // Track the keyed join target and the larger input index across calls.
        struct ExtraState {
            var keyed: [Row: [Row]]
            var largerIndex: Int
            var largerAttributes: [Attribute]
            var largerToSmallerRenaming: [Attribute: Attribute]
        }
        
        let extraState = nodeStates[nodeIndex].getExtraState({ Void -> ExtraState in
            // Figure out which input is smaller. If only one is complete, assume that one is smaller.
            let smallerInput: Int
            if nodeStates[nodeIndex].inputBuffers[0].eof {
                if nodeStates[nodeIndex].inputBuffers[1].eof {
                    smallerInput = nodeStates[nodeIndex].inputBuffers[0].rows.count < nodeStates[nodeIndex].inputBuffers[1].rows.count ? 0 : 1
                } else {
                    smallerInput = 0
                }
            } else {
                smallerInput = 1
            }
            
            let smallerAttributes = smallerInput == 0 ? matching.keys : matching.values
            let largerAttributes = smallerInput == 0 ? matching.values : matching.keys
            let largerToSmallerRenaming = smallerInput == 0 ? matching.inverted : matching
            
            // It's common to join identical attributes, so filter out any renames which "rename"
            // to the same attribute. This speeds things up and will allow skipping rename work
            // altogether if they're all like that.
            let largerToSmallerRenamingWithoutNoops = largerToSmallerRenaming.filter({ $0 != $1 })
            
            var keyed: [Row: [Row]] = [:]
            for row in nodeStates[nodeIndex].inputBuffers[smallerInput].popAll() {
                let joinKey = row.rowWithAttributes(smallerAttributes)
                if keyed[joinKey] != nil {
                    keyed[joinKey]!.append(row)
                } else {
                    keyed[joinKey] = [row]
                }
            }
            
            if !nodeStates[nodeIndex].parentalSelectPropagationDisabled && keyed.count <= maxSelectSize {
                nodeStates[nodeIndex].parentalSelectPropagationDisabled = true
                let select = keyed.keys.map(SelectExpressionFromRow).combined(with: *||) ?? false
                for childIndex in nodes[nodeIndex].childIndexes {
                    nodeStates[nodeIndex].parentalSelectsRemaining = .max
                    addSelect(node: childIndex, expression: select)
                }
            }
            
            return ExtraState(
                keyed: keyed,
                largerIndex: 1 - smallerInput,
                largerAttributes: Array(largerAttributes),
                largerToSmallerRenaming: Dictionary(largerToSmallerRenamingWithoutNoops as [(Attribute, Attribute)])) // For some reason, Swift 3 currently fails to infer generic types without this pointless cast
        })
        
        let joined = nodeStates[nodeIndex].inputBuffers[extraState.largerIndex].popAll().flatMap({ row -> [Row] in
            let joinKey = row.rowWithAttributes(extraState.largerAttributes).renameAttributes(extraState.largerToSmallerRenaming)
            guard let smallerRows = extraState.keyed[joinKey] else { return [] }
            return smallerRows.map({ $0 + row })
        })
        writeOutput(Set(joined), fromNode: nodeIndex)
    }
    
    func processRename(_ nodeIndex: Int, _ inputIndex: Int, _ renames: [Attribute: Attribute]) {
        let rows = nodeStates[nodeIndex].inputBuffers[inputIndex].popAll()
        let renamed = rows.map({ $0.renameAttributes(renames) })
        writeOutput(Set(renamed), fromNode: nodeIndex)
    }
    
    func processUpdate(_ nodeIndex: Int, _ inputIndex: Int, _ newValues: Row) {
        let rows = nodeStates[nodeIndex].inputBuffers[inputIndex].popAll()
        let updated = rows.map({ $0 + newValues })
        writeOutput(nodeStates[nodeIndex].uniq(Set(updated)), fromNode: nodeIndex)
    }
    
    func processAggregate(_ nodeIndex: Int, _ inputIndex: Int, _ attribute: Attribute, _ initialValue: RelationValue?, _ agg: (RelationValue?, RelationValue) -> Result<RelationValue, RelationError>) {
        var soFar = nodeStates[nodeIndex].getExtraState({ initialValue })
        for row in nodeStates[nodeIndex].inputBuffers[inputIndex].popAll() {
            let newValue = row[attribute]
            let aggregated = agg(soFar, newValue)
            switch aggregated {
            case .Ok(let value):
                soFar = value
            case .Err(let err):
                fatalError("Don't know how to handle errors here yet. \(err)")
            }
        }
        nodeStates[nodeIndex].setExtraState(soFar)
        
        if nodeStates[nodeIndex].activeBuffers == 0 {
            if let soFar = soFar {
                writeOutput([Row(values: [attribute: soFar])], fromNode: nodeIndex)
                nodeStates[nodeIndex].setExtraState(nil as RelationValue?)
            }
        }
    }
    
    func processOtherwise(_ nodeIndex: Int, _ inputIndex: Int) {
        // Wait until all buffers are complete before we process anything. We could optimize this a bit
        // by streaming data if all *but one* buffer is complete. Maybe later.
        if nodeStates[nodeIndex].activeBuffers > 0 {
            return
        }
        
        var found = false
        for i in nodeStates[nodeIndex].inputBuffers.indices {
            let rows = nodeStates[nodeIndex].inputBuffers[i].popAll()
            if !found && !rows.isEmpty {
                found = true
                writeOutput(Set(rows), fromNode: nodeIndex)
            }
        }
    }
    
    func processUnique(_ nodeIndex: Int, _ inputIndex: Int, _ attribute: Attribute, _ matching: RelationValue) {
        // We have to wait until everything is here before we can proceed.
        if nodeStates[nodeIndex].activeBuffers > 0 {
            return
        }
        
        let rows = nodeStates[nodeIndex].inputBuffers[0].popAll()
        var valueSoFar: RelationValue?
        var isUnique = true
        for row in rows {
            let value = row[attribute]
            if valueSoFar == nil {
                valueSoFar = value
            } else if valueSoFar != value {
                isUnique = false
                break
            }
        }
        
        if isUnique {
            writeOutput(Set(rows), fromNode: nodeIndex)
        }
    }
    
    func processEquijoinedSelectableGenerator(_ nodeIndex: Int, _ inputIndex: Int, _ matching: [Attribute: Attribute], _ generatorGetter: (SelectExpression) -> AnyIterator<Result<Row, RelationError>>) {
        if nodeStates[nodeIndex].activeBuffers > 0 {
            return
        }
        
        if nodeStates[nodeIndex].extraState == nil {
            let rows = nodeStates[nodeIndex].inputBuffers[0].popAll()
            let onlyMatchingAttributes = rows.map({ $0.rowWithAttributes(matching.keys) })
            let renamed = Set(onlyMatchingAttributes.map({ $0.renameAttributes(matching) }))
            let expressions = renamed.map(SelectExpressionFromRow)
            let expression = expressions.combined(with: *||)
            
            let iterator = generatorGetter(expression ?? false) // TODO: select stuff
            nodeStates[nodeIndex].setExtraState(iterator)
            activeInitiatorIndexes.append(nodeIndex)
        }
    }
}

extension QueryRunner {
    struct NodeState {
        let nodeIndex: Int
        
        var outputForUniquing: Set<Row>? = nil
        var inputBuffers = SmallInlineArray<Buffer>()
        
        /// Each entry here corresponds to the same index in QueryPlanner.Node's `parentIndexes`.
        /// An entry refers to this node's index within the corresponding parent node.
        var parentChildIndexes: [Int] = []
        
        var didMarkDone = false
        
        var activeBuffers: Int
        
        /// A select expression propagated from this node's parents. Nodes can optionally
        /// push selects into their children to try to make things more efficient. If a
        /// select propagates all the way to an efficientlySelectableGenerator and it hasn't
        /// been started yet, then that select will be passed in when creating the generator.
        /// This can make processing data much faster.
        var parentalSelects: SelectExpression?
        
        /// The number of parental selects remaining before the built-up expression can be
        /// propagated to children. This starts out equal to the number of parents this node
        /// has, and decreases by one each time a parentalSelect is added.
        var parentalSelectsRemaining: Int
        
        /// When set to true, propagation of parental selects is disabled. This is set when
        /// selects are propagated to children, to avoid doing it twice for nodes that
        /// do it independently rather than based purely on parent activity.
        var parentalSelectPropagationDisabled = false
        
        var transactionalDatabase: TransactionalDatabase? = nil
        
        var transactionalDatabaseTransactionID: UInt64 = 0
        
        var extraState: Any?
        
        init(nodes: [QueryPlanner.Node], nodeIndex: Int) {
            self.nodeIndex = nodeIndex
            let childCount = nodes[nodeIndex].childCount
            while inputBuffers.count < childCount {
                inputBuffers.append(Buffer())
            }
            activeBuffers = inputBuffers.count
            parentalSelectsRemaining = nodes[nodeIndex].parentCount
        }
        
        mutating func setInputBufferEOF(_ index: Int) {
            precondition(inputBuffers[index].eof == false)
            inputBuffers[index].eof = true
            activeBuffers -= 1
        }
        
        mutating func uniq<Seq: Collection>(_ rows: Seq) -> Set<Row> where Seq.Iterator.Element == Row {
            if rows.count == 0 {
                return []
            }
            
            var rowsSet = (rows as? Set<Row>) ?? Set(rows)
            if outputForUniquing == nil {
                outputForUniquing = rowsSet
                return rowsSet
            } else {
                rowsSet.fastSubtract(outputForUniquing!)
                outputForUniquing!.formUnion(rowsSet)
                return rowsSet
            }
        }
        
        mutating func getExtraState<T>(_ calculate: (Void) -> T) -> T {
            if let state = extraState {
                return state as! T
            } else {
                let state = calculate()
                extraState = state
                return state
            }
        }
        
        mutating func setExtraState<T>(_ value: T) {
            extraState = value
        }
    }
}

extension QueryRunner {
    // This is a struct rather than a class, because it gets stored into SmallInlineArray.
    // When that happens and it's a struct, `rows` is effectively nested in the array,
    // which prevents in-place mutations.
    class Buffer {
        var rows: [Row] = []
        var eof = false
        
        func pop() -> Row? {
            return rows.popLast()
        }
        
        func popAll() -> [Row] {
            let ret = rows
            rows = []
            return ret
        }
        
        func add<S: Sequence>(_ seq: S) where S.Iterator.Element == Row {
            rows.append(contentsOf: seq)
        }
    }
}

extension QueryRunner {
    fileprivate struct IntermediateToProcess: Hashable {
        var nodeIndex: Int
        var inputIndex: Int
        
        fileprivate var hashValue: Int {
            return nodeIndex ^ inputIndex
        }
    }
}

private func ==(a: QueryRunner.IntermediateToProcess, b: QueryRunner.IntermediateToProcess) -> Bool {
    return a.nodeIndex == b.nodeIndex && a.inputIndex == b.inputIndex
}

extension QueryRunner {
    public enum Error: Swift.Error {
        case mutatedDuringEnumeration
    }
}
