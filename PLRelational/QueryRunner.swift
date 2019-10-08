//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

private let enableValidation = true

/// :nodoc: Implementation detail (will be made non-public eventually)
open class QueryRunner {
    var nodes: [QueryPlanner.Node]
    fileprivate var outputCallbacks: [QueryPlanner.OutputCallback]
    
    fileprivate var activeInitiatorIndexes: [Int]
    
    fileprivate var currentInitiatorIndex: Int?
    
    fileprivate var initiatorGenerators: Dictionary<Int, AnyIterator<Result<Set<Row>, RelationError>>> = [:]
    
    fileprivate var intermediatesToProcess: [IntermediateToProcess] = []
    
    var nodeStates: [NodeState]
    
    open fileprivate(set) var done = false
    open fileprivate(set) var didError = false
    
    init(planner: QueryPlanner) {
        let nodes = planner.nodes
        self.nodes = nodes
        self.outputCallbacks = planner.allOutputCallbacks
        
        activeInitiatorIndexes = planner.initiatorIndexes
        nodeStates = Array()
        nodeStates.reserveCapacity(nodes.count)
        for index in nodes.indices {
            nodeStates.append(NodeState(nodes: nodes, nodeIndex: index))
        }
        computeParentChildIndexes(nodeStates.indices)
        computeTransactionalDatabases(planner.transactionalDatabases)
        propagateSelects()
        validate()
    }
    
    /// Fill out each NodeState's `parentChildIndexes` array by scanning their parents.
    /// This computes each child's index within the parent, which the other code needs
    /// in order to write data and propagate EOF info.
    fileprivate func computeParentChildIndexes(_ indexes: CountableRange<Int>) {
        for nodeIndex in indexes {
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
                for var childIndex in nodes[nodeIndex].childIndexes {
                    if shouldCopyForParentalSelect(childIndex) {
                        childIndex = copyNodeTree(childIndex, parent: nodeIndex)
                    }
                    addSelect(node: childIndex, expression: expression)
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
    
    private func approximateCount(nodeIndex: Int) -> Double {
        if nodeStates[nodeIndex].parentalSelectsRemaining == 0, let select = nodeStates[nodeIndex].parentalSelects {
            return nodes[nodeIndex].approximateCount(select) ?? .infinity
        } else {
            return nodes[nodeIndex].approximateCount(true) ?? .infinity
        }
    }
    
    private func popInitiatorIndex() -> Int? {
        // Use the smallest initiators first based on the approximate count.
        let indexesAndCounts = activeInitiatorIndexes.map({
            return (approximateCount(nodeIndex: $0), $0)
        })
        if let (index, (_, result)) = indexesAndCounts.enumerated().min(by: {
            $0.1.0 < $1.1.0
        }) {
            activeInitiatorIndexes.remove(at: index)
            return result
        } else {
            return nil
        }
    }
    
    private func getInitiatorIndex() -> Int? {
        if let current = currentInitiatorIndex {
            return current
        } else {
            currentInitiatorIndex = popInitiatorIndex()
            return currentInitiatorIndex
        }
    }
    
    private func endCurrentInitiator() {
        currentInitiatorIndex = nil
    }
    
    /// Process an active initiator node. If there are no active initiator nodes, sets the `done` property
    /// to true. If the initiator node produces an error instead of a row, this method returns that error.
    fileprivate func pumpInitiator() -> Result<Void, RelationError> {
        guard let nodeIndex = getInitiatorIndex() else {
            done = true
            return .Ok(())
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
            let rows = getRowGeneratorRows(nodeIndex, generatorGetter)
            switch rows {
            case .some(.Err(let err)):
                return .Err(err)
            case .some(.Ok(let rows)):
                writeOutput(rows, fromNode: nodeIndex)
            case .none:
                endCurrentInitiator()
                markDone(nodeIndex)
            }
        case .selectableGenerator(let generatorGetter):
            let rows = getRowGeneratorRows(nodeIndex, {
                let select = nodeStates[nodeIndex].parentalSelectsRemaining == 0
                    ? nodeStates[nodeIndex].parentalSelects ?? true
                    : true
                return generatorGetter(select)
            })
            switch rows {
            case .some(.Err(let err)):
                return .Err(err)
            case .some(.Ok(let rows)):
                writeOutput(rows, fromNode: nodeIndex)
            case .none:
                endCurrentInitiator()
                markDone(nodeIndex)
            }
        case .rowSet(let rowGetter):
            let rows = rowGetter()
            writeOutput(rows, fromNode: nodeIndex)
            endCurrentInitiator()
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
        
        return .Ok(())
    }
    
    fileprivate func getRowGeneratorRows(_ initiatorIndex: Int, _ generatorGetter: () -> AnyIterator<Result<Set<Row>, RelationError>>) -> Result<Set<Row>, RelationError>? {
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
        if nodes[node].outputCallbacks != nil { return }
        
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
            
        case .dead:
            fatalError("Encountered a dead node while trying to derive a select expression")
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
        
        let rhsMap = nodeStates[nodeIndex].getExtraState({ nodeState -> ObjectMap<()> in
            // Note: we pull the rows here but we do *not* pop them. The map doesn't keep the rows
            // alive, so we need to keep those objects alive by holding onto the rows elsewhere.
            let rows = nodeState.inputBuffers[1].rows
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
        let maxSelectSize = 100
        
        // Track the keyed join target and the larger input index across calls.
        struct ExtraState {
            var keyed: [Row: [Row]]
            var largerIndex: Int
            var largerAttributes: [Attribute]
            var largerToSmallerRenaming: [Attribute: Attribute]
        }
        
        // Can't use the getExtraState convenience, since nodeStates might be mutated.
        let extraState: ExtraState
        if let s = nodeStates[nodeIndex].extraState as? ExtraState {
            extraState = s
        } else {
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
            
            // The larger input is the other one.
            let largerInput = smallerInput == 0 ? 1 : 0
            
            let matchingKeys = Array(matching.keys)
            let matchingValues = Array(matching.values)
            
            let smallerAttributes = smallerInput == 0 ? matchingKeys : matchingValues
            let largerAttributes = smallerInput == 0 ? matchingValues : matchingKeys
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
            
            if !nodeStates[nodeIndex].parentalSelectPropagationDisabled && keyed.count <= maxSelectSize && keyed[.empty] == nil {
                nodeStates[nodeIndex].parentalSelectPropagationDisabled = true
                let select = keyed.keys.map(SelectExpressionFromRow).combined(with: *||) ?? false
                
                // The select derived above would apply to the smaller side. We need to rename
                // the keys in order for it to apply correctly to the larger side.
                let smallerToLargerRenaming = largerInput == 0 ? matching.inverted : matching
                let renamedSelect = select.withRenamedAttributes(smallerToLargerRenaming)
                
                var childIndex = nodes[nodeIndex].childIndexes[largerInput]
                nodeStates[nodeIndex].parentalSelectsRemaining = .max
                if shouldCopyForParentalSelect(childIndex) {
                    childIndex = copyNodeTree(childIndex, parent: nodeIndex)
                }
                addSelect(node: childIndex, expression: renamedSelect)
            }
            
            extraState = ExtraState(
                keyed: keyed,
                largerIndex: 1 - smallerInput,
                largerAttributes: largerAttributes,
                largerToSmallerRenaming: largerToSmallerRenamingWithoutNoops) // For some reason, Swift 3 currently fails to infer generic types without this pointless cast
            nodeStates[nodeIndex].setExtraState(extraState)
        }
        
        let rows = nodeStates[nodeIndex].inputBuffers[extraState.largerIndex].popAll()
        let joined = rows.flatMap({ row -> [Row] in
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
    
    func processAggregate(_ nodeIndex: Int, _ inputIndex: Int, _ attribute: Attribute, _ initialValue: RelationValue?, _ agg: (RelationValue?, [Row]) -> Result<RelationValue, RelationError>) {
        var soFar = nodeStates[nodeIndex].getExtraState({ _ in initialValue })
        let rows = nodeStates[nodeIndex].inputBuffers[inputIndex].popAll()
        if !rows.isEmpty {
            let aggregated = agg(soFar, rows)
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
    /// Copy a tree of nodes including the one passed in as the parameter and all
    /// of its children. Note: this does *not* bother with child nodes that are
    /// reachable by more than one path. Those will be copied more than once.
    /// The parents of the returned node will be empty.
    /// - returns: The index of the copied node.
    func copyNodeTree(_ index: Int, parent: Int) -> Int {
        let firstNewIndex = nodes.count
        let result = copyNodeTreeNoStates(index)
        
        nodes[result].parentIndexes = [parent]
        nodes[parent].childIndexes.replace(index, with: result)
        
        let childParentIndex = nodes[index].parentIndexes.firstIndex(of: parent)!
        nodes[index].parentIndexes.remove(at: childParentIndex)
        nodeStates[index].parentChildIndexes.remove(at: childParentIndex)
        nodeStates[index].parentalSelectsRemaining -= 1
        
        for i in firstNewIndex ..< nodes.count {
            nodeStates.append(NodeState(nodes: nodes, nodeIndex: i))
        }
        computeParentChildIndexes(firstNewIndex ..< nodes.count)
        
        return result
    }
    
    fileprivate func validate() {
        guard enableValidation else { return }
        
        for i in nodes.indices {
            for child in nodes[i].childIndexes {
                precondition(nodes[child].parentIndexes.contains(i))
            }
            for (parent, parentIndex) in zip(nodes[i].parentIndexes, nodeStates[i].parentChildIndexes) {
                precondition(nodes[parent].childIndexes[parentIndex] == i)
            }
        }
    }
    
    /// Copy a tree of nodes, ignoring node states. After this returns,
    /// all new nodes will be appended to the end of the `nodes` array,
    /// but the `nodeStates` array will be unchanged. Node states must
    /// be fixed up after making this call.
    private func copyNodeTreeNoStates(_ index: Int) -> Int {
        let newChildren = nodes[index].childIndexes.map(copyNodeTreeNoStates)
        
        let newIndex = nodes.count
        for i in newChildren {
            nodes[i].parentIndexes = [newIndex]
        }
        
        var node = QueryPlanner.Node(op: nodes[index].op, scheme: nodes[index].scheme, approximateCount: nodes[index].approximateCount)
        node.debugName = nodes[index].debugName
        nodes.append(node)
        nodes[newIndex].childIndexes = newChildren
        if QueryPlanner.isInitiator(op: nodes[newIndex].op) {
            activeInitiatorIndexes.append(newIndex)
        }
        
        return newIndex
    }
    
    /// Determine whether a given node should be copied when applying a parental select.
    /// Copying a node will allow an efficient select to be performed on initiators
    /// even if other parts of the graph which refer to it don't provide parental selects.
    /// The criteria used are:
    /// 1. Total number of children (double-counting anything that can be reached by
    ///    more than one path) must be no more than a certain number (currently 100).
    /// 2. Parental selects remaining must be at least 2. If 1 then no other parts of
    ///    the graph point here, or they've already provided their selects. If 0 then
    ///    something went wrong.
    /// 3. There must be at least one selectable generator in the subtree (otherwise there
    ///    is no point in doing all this work).
    func shouldCopyForParentalSelect(_ index: Int) -> Bool {
        let childCountLimit = 100
        
        if nodeStates[index].parentalSelectsRemaining < 2 {
            return false
        }
        
        var toSearch = [index]
        var numberSearched = 0
        
        var sawSelectableGenerator = false
        while let toExamine = toSearch.popLast() {
            numberSearched += 1
            if numberSearched > childCountLimit {
                return false
            }
            
            let op = nodes[toExamine].op
            
            // If any part of the subtree has started generating, don't even try.
            if QueryPlanner.isInitiator(op: op) && initiatorGenerators[toExamine] != nil {
                return false
            }
            
            if case .selectableGenerator = nodes[toExamine].op {
                sawSelectableGenerator = true
            }
            toSearch.append(contentsOf: nodes[toExamine].childIndexes)
        }
        
        return sawSelectableGenerator
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
        
        mutating func getExtraState<T>(_ calculate: (NodeState) -> T) -> T {
            if let state = extraState {
                return state as! T
            } else {
                let state = calculate(self)
                setExtraState(state)
                return state
            }
        }
        
        mutating func setExtraState<T>(_ value: T) {
            extraState = value
        }
    }
}

extension QueryRunner {
    // This is a class rather than a struct, because it gets stored into SmallInlineArray.
    // When that happens and it's a struct, `rows` is effectively nested in the array,
    // which prevents in-place mutations.
    class Buffer {
        var rows: [Row] = []
        var eof = false
        var rowsAdded = 0
        
        func pop() -> Row? {
            return rows.popLast()
        }
        
        func popAll() -> [Row] {
            let ret = rows
            rows = []
            return ret
        }
        
        func add<S: Sequence>(_ seq: S) where S.Iterator.Element == Row {
            let beforeCount = rows.count
            rows.append(contentsOf: seq)
            rowsAdded = rowsAdded &+ (rows.count - beforeCount)
        }
    }
}

extension QueryRunner {
    fileprivate struct IntermediateToProcess: Hashable {
        var nodeIndex: Int
        var inputIndex: Int
        
        fileprivate func hash(into hasher: inout Hasher) {
            hasher.combine(nodeIndex)
            hasher.combine(inputIndex)
        }
    }
}

private func ==(a: QueryRunner.IntermediateToProcess, b: QueryRunner.IntermediateToProcess) -> Bool {
    return a.nodeIndex == b.nodeIndex && a.inputIndex == b.inputIndex
}

/// :nodoc: Implementation detail (will be made non-public eventually)
extension QueryRunner {
    public enum Error: Swift.Error {
        case mutatedDuringEnumeration
    }
}
