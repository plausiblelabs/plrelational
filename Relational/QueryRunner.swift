
class QueryRunner {
    let nodeTree: ObjectSet<QueryPlanner.Node>
    let root: QueryPlanner.Node
    
    var activeInitiators: ObjectSet<QueryPlanner.Node>
    
    var initiatorGenerators: ObjectDictionary<QueryPlanner.Node, AnyGenerator<Result<Row, RelationError>>> = [:]
    
    var nodeStates: ObjectDictionary<QueryPlanner.Node, NodeState> = [:]
    
    var collectedOutput: Set<Row> = []
    
    var done = false
    
    init(nodeTree: ObjectSet<QueryPlanner.Node>) {
        self.nodeTree = nodeTree
        self.root = nodeTree.find({ $0.parents.isEmpty })!
        
        let initiators = nodeTree.filter({
            switch $0.op {
            case .TableScan:
                return true
            default:
                return false
            }
        })
        
        activeInitiators = ObjectSet(initiators)
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
        guard let node = activeInitiators.any else {
            done = true
            return []
        }
        
        let row = getInitiatorRow(node)
        
        switch row {
        case .Some(.Err(let err)):
            return [.Err(err)]
        case .Some(.Ok(let row)):
            writeOutput([row], fromNode: node)
        case .None:
            activeInitiators.remove(node)
            markDone(node)
        }
        
        let output = collectedOutput
        collectedOutput = []
        return output.map({ .Ok($0) })
    }
    
    private func getInitiatorRow(initiator: QueryPlanner.Node) -> Result<Row, RelationError>? {
        switch initiator.op {
        case .TableScan(let relation):
            let generator = initiatorGenerators.getOrCreate(initiator, defaultValue: relation.rows())
            let row = generator.next()
            return row
        default:
            fatalError("Unknown initiator operation \(initiator.op)")
        }
    }
    
    private func writeOutput(rows: Set<Row>, fromNode: QueryPlanner.Node) {
        if fromNode === root {
            collectedOutput.unionInPlace(rows)
        } else {
            for (parent, index) in fromNode.parents {
                let state = nodeStates.getOrCreate(parent, defaultValue: NodeState(node: parent))
                state.inputBuffers[index].add(rows)
                process(parent, inputIndex: index)
            }
        }
    }
    
    private func markDone(node: QueryPlanner.Node) {
        for (parent, index) in node.parents {
            let state = nodeStates.getOrCreate(parent, defaultValue: NodeState(node: parent))
            state.setInputBufferEOF(index)
            process(parent, inputIndex: index)
            if state.activeBuffers == 0 {
                markDone(parent)
            }
        }
    }
    
    private func process(node: QueryPlanner.Node, inputIndex: Int) {
        let state = nodeStates[node]!
        switch node.op {
        case .Union:
            processUnion(node, state, inputIndex)
        case .Intersection:
            processIntersection(node, state, inputIndex)
        case .Difference:
            processDifference(node, state, inputIndex)
        case .Project(let scheme):
            processProject(node, state, inputIndex, scheme)
        case .Select(let expression):
            processSelect(node, state, inputIndex, expression)
        case .Equijoin(let matching):
            processEquijoin(node, state, inputIndex, matching)
        default:
            fatalError("Don't know how to process operation \(node.op)")
        }
    }
    
    func processUnion(node: QueryPlanner.Node, _ state: NodeState, _ inputIndex: Int) {
        let rows = state.inputBuffers[inputIndex].popAll()
        writeOutput(state.uniq(rows), fromNode: node)
    }
    
    func processIntersection(node: QueryPlanner.Node, _ state: NodeState, _ inputIndex: Int) {
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
        writeOutput(accumulated, fromNode: node)
    }
    
    func processDifference(node: QueryPlanner.Node, _ state: NodeState, _ inputIndex: Int) {
        // We compute buffer[0] - buffer[1]. buffer[1] must be complete before we can compute anything.
        // Once it is complete, we can stream buffer[0] through.
        guard state.inputBuffers[1].eof else { return }
        
        let rows = state.inputBuffers[0].popAll()
        let subtracted = rows.subtract(state.inputBuffers[1].rows)
        writeOutput(subtracted, fromNode: node)
    }
    
    func processProject(node: QueryPlanner.Node, _ state: NodeState, _ inputIndex: Int, _ scheme: Scheme) {
        let rows = state.inputBuffers[inputIndex].popAll()
        let projected = Set(rows.map({ row -> Row in
            let subvalues = scheme.attributes.map({ ($0, row[$0]) })
            return Row(values: Dictionary(subvalues))
        }))
        writeOutput(state.uniq(projected), fromNode: node)
    }
    
    func processSelect(node: QueryPlanner.Node, _ state: NodeState, _ inputIndex: Int, _ expression: SelectExpression) {
        let rows = state.inputBuffers[inputIndex].popAll()
        let filtered = Set(rows.filter({ expression.valueWithRow($0).boolValue }))
        writeOutput(filtered, fromNode: node)
    }
    
    func processEquijoin(node: QueryPlanner.Node, _ state: NodeState, _ inputIndex: Int, _ matching: [Attribute: Attribute]) {
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
        writeOutput(Set(joined), fromNode: node)
    }
}

extension QueryRunner {
    class NodeState {
        let node: QueryPlanner.Node
        
        var outputForUniquing: Set<Row> = []
        var inputBuffers: [Buffer] = []
        
        var activeBuffers: Int
        
        var extraState: Any?
        
        init(node: QueryPlanner.Node) {
            self.node = node
            while inputBuffers.count < node.childCount {
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
