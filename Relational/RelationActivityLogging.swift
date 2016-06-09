
import Foundation

/// Relation logging support. Disabled at compile time by default, which should result in zero overhead with the
/// always-inlined functions. To enable, add this to Other Swift Flags:
///     -DLOG_RELATION_ACTIVITY

/// When logging is enabled, individual logging features can be enabled or disabled with these properties.
#if LOG_RELATION_ACTIVITY
private struct Flags {
    /// Print the stack trace of each Relation's creation.
    static let printCreationStacks = true
    
    /// Do a simple dump of each top-level Relation that's iterated. Relations iterated while iterating
    /// another Relation aren't considered top-level and don't get dumped.
    static let dumpTopLevelSimple = true
    
    /// Do a uniquing dump of each top-level Relation that's iterated. This assigns a symbol to Relations
    /// in the tree that are repeatedly referenced so they don't repeat in the dumped representation.
    static let dumpTopLevelUniquing = true
    
    /// Dump each top-level Relation that's iterated to a Graphviz dot file which can be rendered graphically.
    static let dumpTopLevelGraphviz = true
    
    /// Do a full (recursive) dump of iterated top-level Relations.
    static let dumpTopLevelFull = true
    
    /// Print information about the beginning, end, and each row of iteration
    static let printIterations = true
}
#endif

struct RelationIterationLoggingData {
    #if LOG_RELATION_ACTIVITY
    var callerDescription: String
    var startTime: NSTimeInterval
    var indentLevel: Int
    var indentDecrementor: ValueWithDestructor<Void>
    #endif
}

private var indentLevel = 0
private var completionScheduled = false

@inline(__always) func LogRelationCreation<T: Relation>(caller: T) {
    #if LOG_RELATION_ACTIVITY
        if let obj = caller as? AnyObject {
            print("Created \(caller.dynamicType) \(String(format: "%p", ObjectIdentifier(obj).uintValue))")
            if Flags.printCreationStacks {
                for line in NSThread.callStackSymbols() {
                    print(line)
                }
            }
        }
    #endif
}

@inline(__always) func LogRelationIterationBegin<T: Relation>(caller: T) -> RelationIterationLoggingData {
    #if LOG_RELATION_ACTIVITY
        let description: String
        if let obj = caller as? AnyObject {
            description = String(format: "%@ %p", NSStringFromClass(obj.dynamicType), unsafeAddressOf(obj))
        } else {
            description = String(caller.dynamicType)
        }
        if indentLevel == 0 {
            print("----------")
            print("Starting top-level iteration of \(description)")
            if Flags.dumpTopLevelSimple {
                caller.simpleDump()
            }
            if Flags.dumpTopLevelUniquing {
                caller.uniquingDump()
            }
            if Flags.dumpTopLevelGraphviz {
                caller.graphvizDump()
            }
            if Flags.dumpTopLevelFull {
                caller.fullDebugDump(showContents: false)
            }
            
            if !completionScheduled {
                dispatch_async(dispatch_get_main_queue(), {
                    print("==========")
                    print("RETURNED TO EVENT LOOP")
                    print("==========")
                    completionScheduled = false
                })
                completionScheduled = true
            }
        }
        let now = NSProcessInfo().systemUptime
        
        if Flags.printIterations {
            let indentString = "".stringByPaddingToLength(indentLevel * 4, withString: " ", startingAtIndex: 0)
            print("\(indentString)\(description) began iteration at \(now)")
        }
        
        let data = RelationIterationLoggingData(
            callerDescription: description,
            startTime: now,
            indentLevel: indentLevel,
            indentDecrementor: ValueWithDestructor(value: (), destructor: { indentLevel -= 1 })
        )
        indentLevel += 1
        return data
    #else
    return RelationIterationLoggingData()
    #endif
}

@inline(__always) func LogRelationIterationReturn(data: RelationIterationLoggingData, _ generator: AnyGenerator<Result<Row, RelationError>>) -> AnyGenerator<Result<Row, RelationError>> {
    #if LOG_RELATION_ACTIVITY
        var rowCount = 0
        let indentString = "".stringByPaddingToLength(data.indentLevel * 4, withString: " ", startingAtIndex: 0)
        return AnyGenerator(body: {
            let next = generator.next()
            switch next {
            case .Some(.Ok(let row)):
                if Flags.printIterations {
                    print("\(indentString)\(data.callerDescription) returning row \(row)")
                    rowCount += 1
                }
            case .Some(.Err(let err)):
                if Flags.printIterations {
                    print("\(indentString)\(data.callerDescription) returning error \(err)")
                }
            case .None:
                if Flags.printIterations {
                    let elapsedTime = NSProcessInfo().systemUptime - data.startTime
                    print("\(indentString)\(data.callerDescription) finished iteration, produced \(rowCount) rows in \(elapsedTime) seconds")
                }
            }
            return next
        })
    #else
    return generator
    #endif
}
