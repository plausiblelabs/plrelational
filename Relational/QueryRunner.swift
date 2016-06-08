
class QueryRunner {
    let nodes: [QueryPlanner.Node]
    let rootIndex: Int
    
    var activeInitiatorIndexes: [Int]
    
    var initiatorGenerators: Dictionary<Int, AnyGenerator<Result<Row, RelationError>>> = [:]
    
    var nodeStates: [NodeState]
    
    var collectedOutput: Set<Row> = []
    
    var done = false
    
    init(planner: QueryPlanner) {
        let nodes = planner.nodes
        self.nodes = nodes
        rootIndex = planner.rootIndex
        activeInitiatorIndexes = planner.initiatorIndexes
        nodeStates = nodes.indices.map({
            NodeState(nodes: nodes, nodeIndex: $0)
        })
    }
    
    func rows() -> AnyGenerator<Result<Row, RelationError>> {
        var buffer: [Result<Row, RelationError>] = []
        return AnyGenerator(body: {
            while !self.done {
                if let row = buffer.popLast() {
                    return row
                } else {
                    buffer = self.pump()
                }
            }
            return nil
        })
    }
    
    private func pump() -> [Result<Row, RelationError>] {
        guard let nodeIndex = activeInitiatorIndexes.last else {
            done = true
            return []
        }
        
        let row = getInitiatorRow(nodeIndex)
        
        switch row {
        case .Some(.Err(let err)):
            return [.Err(err)]
        case .Some(.Ok(let row)):
            writeOutput([row], fromNode: nodeIndex)
        case .None:
            activeInitiatorIndexes.removeLast()
            markDone(nodeIndex)
        }
        
        let output = collectedOutput
        collectedOutput = []
        return output.map({ .Ok($0) })
    }
    
    private func getInitiatorRow(initiatorIndex: Int) -> Result<Row, RelationError>? {
        let op = nodes[initiatorIndex].op
        switch op {
        case .TableScan(let relation):
            let generator = initiatorGenerators.getOrCreate(initiatorIndex, defaultValue: relation.rawGenerateRows())
            let row = generator.next()
            return row
        default:
            fatalError("Unknown initiator operation \(op)")
        }
    }
    
    private func writeOutput(rows: Set<Row>, fromNode: Int) {
        guard !rows.isEmpty else { return }
        
        if fromNode == rootIndex {
            collectedOutput.unionInPlace(rows)
        } else {
            for (parentIndex, index) in nodes[fromNode].parentIndexes {
                let state = nodeStates[parentIndex]
                state.inputBuffers[index].add(rows)
                process(parentIndex, inputIndex: index)
            }
        }
    }
    
    private func markDone(nodeIndex: Int) {
        for (parentIndex, index) in nodes[nodeIndex].parentIndexes {
            let state = nodeStates[parentIndex]
            state.setInputBufferEOF(index)
            process(parentIndex, inputIndex: index)
            if state.activeBuffers == 0 {
                markDone(parentIndex)
            }
        }
    }
    
    private func process(nodeIndex: Int, inputIndex: Int) {
        let state = nodeStates[nodeIndex]
        let op = nodes[nodeIndex].op
        switch op {
        case .Union:
            processUnion(nodeIndex, state, inputIndex)
        case .Intersection:
            processIntersection(nodeIndex, state, inputIndex)
        case .Difference:
            processDifference(nodeIndex, state, inputIndex)
        case .Project(let scheme):
            processProject(nodeIndex, state, inputIndex, scheme)
        case .Select(let expression):
            processSelect(nodeIndex, state, inputIndex, expression)
        case .Equijoin(let matching):
            processEquijoin(nodeIndex, state, inputIndex, matching)
        case .Rename(let renames):
            processRename(nodeIndex, state, inputIndex, renames)
        case .Update(let newValues):
            processUpdate(nodeIndex, state, inputIndex, newValues)
        case .Aggregate(let attribute, let initialValue, let agg):
            processAggregate(nodeIndex, state, inputIndex, attribute, initialValue, agg)
        default:
            fatalError("Don't know how to process operation \(op)")
        }
    }
    
    func processUnion(nodeIndex: Int, _ state: NodeState, _ inputIndex: Int) {
        let rows = state.inputBuffers[inputIndex].popAll()
        writeOutput(state.uniq(rows), fromNode: nodeIndex)
    }
    
    func processIntersection(nodeIndex: Int, _ state: NodeState, _ inputIndex: Int) {
        // Wait until all buffers are complete before we process anything. We could optimize this a bit
        // by streaming data if all *but one* buffer is complete. Maybe later.
        if state.activeBuffers > 0 {
            return
        }
        
        var accumulated = state.inputBuffers.first?.popAll() ?? []
        for buffer in state.inputBuffers.dropFirst() {
            let bufferRows = buffer.popAll()
            accumulated.intersectInPlace(bufferRows)
        }
        writeOutput(accumulated, fromNode: nodeIndex)
    }
    
    func processDifference(nodeIndex: Int, _ state: NodeState, _ inputIndex: Int) {
        // We compute buffer[0] - buffer[1]. buffer[1] must be complete before we can compute anything.
        // Once it is complete, we can stream buffer[0] through.
        guard state.inputBuffers[1].eof else { return }
        
        let rows = state.inputBuffers[0].popAll()
        let subtracted = rows.subtract(state.inputBuffers[1].rows)
        writeOutput(subtracted, fromNode: nodeIndex)
    }
    
    func processProject(nodeIndex: Int, _ state: NodeState, _ inputIndex: Int, _ scheme: Scheme) {
        let rows = state.inputBuffers[inputIndex].popAll()
        let projected = Set(rows.map({ row -> Row in
            let subvalues = scheme.attributes.map({ ($0, row[$0]) })
            return Row(values: Dictionary(subvalues))
        }))
        writeOutput(state.uniq(projected), fromNode: nodeIndex)
    }
    
    func processSelect(nodeIndex: Int, _ state: NodeState, _ inputIndex: Int, _ expression: SelectExpression) {
        let rows = state.inputBuffers[inputIndex].popAll()
        let filtered = Set(rows.filter({ expression.valueWithRow($0).boolValue }))
        writeOutput(filtered, fromNode: nodeIndex)
    }
    
    func processEquijoin(nodeIndex: Int, _ state: NodeState, _ inputIndex: Int, _ matching: [Attribute: Attribute]) {
        // Accumulate data until at least one input is complete.
        guard state.activeBuffers <= 1 else { return }
        
        // Track the keyed join target and the larger input index across calls.
        struct ExtraState {
            var keyed: [Row: [Row]]
            var largerIndex: Int
            var largerAttributes: [Attribute]
            var largerToSmallerRenaming: [Attribute: Attribute]
        }
        
        let extraState = state.getExtraState({ Void -> ExtraState in
            // Figure out which input is smaller. If only one is complete, assume that one is smaller.
            let smallerInput: Int
            if state.inputBuffers[0].eof {
                if state.inputBuffers[1].eof {
                    smallerInput = state.inputBuffers[0].rows.count < state.inputBuffers[1].rows.count ? 0 : 1
                } else {
                    smallerInput = 0
                }
            } else {
                smallerInput = 1
            }
            
            let smallerAttributes = smallerInput == 0 ? matching.keys : matching.values
            let largerAttributes = smallerInput == 0 ? matching.values : matching.keys
            let largerToSmallerRenaming = smallerInput == 0 ? matching.reversed : matching
            
            var keyed: [Row: [Row]] = [:]
            for row in state.inputBuffers[smallerInput].popAll() {
                let joinKey = row.rowWithAttributes(smallerAttributes)
                if keyed[joinKey] != nil {
                    keyed[joinKey]!.append(row)
                } else {
                    keyed[joinKey] = [row]
                }
            }
            
            return ExtraState(
                keyed: keyed,
                largerIndex: 1 - smallerInput,
                largerAttributes: Array(largerAttributes),
                largerToSmallerRenaming: largerToSmallerRenaming)
        })
        
        let joined = state.inputBuffers[extraState.largerIndex].popAll().flatMap({ row -> [Row] in
            let joinKey = row.rowWithAttributes(extraState.largerAttributes).renameAttributes(extraState.largerToSmallerRenaming)
            guard let smallerRows = extraState.keyed[joinKey] else { return [] }
            return smallerRows.map({ Row(values: $0.values + row.values) })
        })
        writeOutput(Set(joined), fromNode: nodeIndex)
    }
    
    func processRename(nodeIndex: Int, _ state: NodeState, _ inputIndex: Int, _ renames: [Attribute: Attribute]) {
        let rows = state.inputBuffers[inputIndex].popAll()
        let renamed = rows.map({ $0.renameAttributes(renames) })
        writeOutput(Set(renamed), fromNode: nodeIndex)
    }
    
    func processUpdate(nodeIndex: Int, _ state: NodeState, _ inputIndex: Int, _ newValues: Row) {
        let rows = state.inputBuffers[inputIndex].popAll()
        let updated = rows.map({ Row(values: $0.values + newValues.values) })
        writeOutput(state.uniq(Set(updated)), fromNode: nodeIndex)
    }
    
    func processAggregate(nodeIndex: Int, _ state: NodeState, _ inputIndex: Int, _ attribute: Attribute, _ initialValue: RelationValue?, _ agg: (RelationValue?, RelationValue) -> Result<RelationValue, RelationError>) {
        var soFar = state.getExtraState({ initialValue })
        for row in state.inputBuffers[inputIndex].popAll() {
            let newValue = row[attribute]
            let aggregated = agg(soFar, newValue)
            switch aggregated {
            case .Ok(let value):
                soFar = value
            case .Err(let err):
                fatalError("Don't know how to handle errors here yet. \(err)")
            }
        }
        state.setExtraState(soFar)
        
        if state.activeBuffers == 0 {
            if let soFar = soFar {
                writeOutput([Row(values: [attribute: soFar])], fromNode: nodeIndex)
            }
        }
    }
}

extension QueryRunner {
    class NodeState {
        let nodeIndex: Int
        
        var outputForUniquing: Set<Row> = []
        var inputBuffers: [Buffer] = []
        
        var activeBuffers: Int
        
        var extraState: Any?
        
        init(nodes: [QueryPlanner.Node], nodeIndex: Int) {
            self.nodeIndex = nodeIndex
            let childCount = nodes[nodeIndex].childCount
            while inputBuffers.count < childCount {
                inputBuffers.append(Buffer())
            }
            activeBuffers = inputBuffers.count
        }
        
        func setInputBufferEOF(index: Int) {
            precondition(inputBuffers[index].eof == false)
            inputBuffers[index].eof = true
            activeBuffers -= 1
        }
        
        func uniq(rows: Set<Row>) -> Set<Row> {
            let unique = rows.subtract(outputForUniquing)
            outputForUniquing.unionInPlace(unique)
            return unique
        }
        
        func getExtraState<T>(calculate: Void -> T) -> T {
            if let state = extraState {
                return state as! T
            } else {
                let state = calculate()
                extraState = state
                return state
            }
        }
        
        func setExtraState<T>(value: T) {
            extraState = value
        }
    }
}

extension QueryRunner {
    class Buffer {
        var rows: Set<Row> = []
        var eof = false
        
        func pop() -> Row? {
            return rows.popFirst()
        }
        
        func popAll() -> Set<Row> {
            let ret = rows
            rows = []
            return ret
        }
        
        func add<S: SequenceType where S.Generator.Element == Row>(seq: S) {
            rows.unionInPlace(seq)
        }
    }
}
