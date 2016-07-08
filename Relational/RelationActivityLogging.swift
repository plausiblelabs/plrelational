//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

/// Relation logging support. Disabled at compile time by default, which should result in zero overhead with the
/// always-inlined functions. To enable, add this to Other Swift Flags:
///     -DLOG_RELATION_ACTIVITY

/// When logging is enabled, individual logging features can be enabled or disabled with these properties.
#if LOG_RELATION_ACTIVITY
private struct Flags {
    /// Print the stack trace of each Relation's creation.
    static let printCreationStacks = false
    
    /// Do a simple dump of each top-level Relation that's iterated. Relations iterated while iterating
    /// another Relation aren't considered top-level and don't get dumped.
    static let dumpTopLevelSimple = false
    
    /// Do a uniquing dump of each top-level Relation that's iterated. This assigns a symbol to Relations
    /// in the tree that are repeatedly referenced so they don't repeat in the dumped representation.
    static let dumpTopLevelUniquing = false
    
    /// Dump each top-level Relation that's iterated to a Graphviz dot file which can be rendered graphically.
    static let dumpTopLevelGraphviz = false
    
    /// Do a full (recursive) dump of iterated top-level Relations.
    static let dumpTopLevelFull = false
    
    /// Print information about the beginning, end, and each row of iteration
    static let printIterations = false
    
    /// Collect the running times for each top-level iteration in a given event loop, and print the times in sorted order
    static let printTopLevelRunningTimes = false
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

#if LOG_RELATION_ACTIVITY
private var indentLevel = Mutexed(0)
private var completionScheduled = false
private var completedTopLevelRelations: [(String, NSTimeInterval)] = []
#endif

#if LOG_RELATION_ACTIVITY
func elapsedTimeString(interval: NSTimeInterval) -> String {
    return String(format: "%4fs", interval)
}
#endif

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
        if indentLevel.get() == 0 {
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
                    
                    if Flags.printTopLevelRunningTimes {
                        completedTopLevelRelations.sortInPlace({ $0.1 < $1.1 })
                        for (description, elapsedTime) in completedTopLevelRelations {
                            print("\(elapsedTimeString(elapsedTime)): \(description)")
                        }
                        let total = completedTopLevelRelations.reduce(0, combine: { $0 + $1.1 })
                        print("Iterated \(completedTopLevelRelations.count) relations in total time: \(elapsedTimeString(total))")
                        completedTopLevelRelations = []
                    }
                })
                completionScheduled = true
            }
        }
        let now = NSProcessInfo().systemUptime
        
        if Flags.printIterations {
            let indentString = "".stringByPaddingToLength(indentLevel.get() * 4, withString: " ", startingAtIndex: 0)
            print("\(indentString)\(description) began iteration at \(now)")
        }
        
        let data = RelationIterationLoggingData(
            callerDescription: description,
            startTime: now,
            indentLevel: indentLevel.get(),
            indentDecrementor: ValueWithDestructor(value: (), destructor: { indentLevel.withMutableValue({ $0 -= 1 }) })
        )
        indentLevel.withMutableValue({ $0 += 1 })
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
                let elapsedTime = NSProcessInfo().systemUptime - data.startTime
                if Flags.printIterations {
                    print("\(indentString)\(data.callerDescription) finished iteration, produced \(rowCount) rows in \(elapsedTimeString(elapsedTime)) seconds")
                }
                if data.indentLevel == 0 && Flags.printTopLevelRunningTimes {
                    completedTopLevelRelations.append((data.callerDescription, elapsedTime))
                }
            }
            return next
        })
    #else
    return generator
    #endif
}

@inline(__always) func LogRelationIterationReturn(data: RelationIterationLoggingData, _ generator: AnyGenerator<Result<Set<Row>, RelationError>>) -> AnyGenerator<Result<Set<Row>, RelationError>> {
    #if LOG_RELATION_ACTIVITY
        var rowCount = 0
        let indentString = "".stringByPaddingToLength(data.indentLevel * 4, withString: " ", startingAtIndex: 0)
        return AnyGenerator(body: {
            let next = generator.next()
            switch next {
            case .Some(.Ok(let rows)):
                if Flags.printIterations {
                    print("\(indentString)\(data.callerDescription) returning rows \(rows)")
                    rowCount += rows.count
                }
            case .Some(.Err(let err)):
                if Flags.printIterations {
                    print("\(indentString)\(data.callerDescription) returning error \(err)")
                }
            case .None:
                let elapsedTime = NSProcessInfo().systemUptime - data.startTime
                if Flags.printIterations {
                    print("\(indentString)\(data.callerDescription) finished iteration, produced \(rowCount) rows in \(elapsedTimeString(elapsedTime)) seconds")
                }
                if data.indentLevel == 0 && Flags.printTopLevelRunningTimes {
                    completedTopLevelRelations.append((data.callerDescription, elapsedTime))
                }
            }
            return next
        })
    #else
        return generator
    #endif
}
