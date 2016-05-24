
import Foundation

/// Iteration logging support. Disabled at compile time by default, which should result in zero overhead with the
/// always-inlined functions. To enable, add this to Other Swift Flags:
///     -DLOG_RELATION_ITERATION

struct RelationIterationLoggingData {
    #if LOG_RELATION_ITERATION
    var callerDescription: String
    var startTime: NSTimeInterval
    var indentLevel: Int
    var indentDecrementor: ValueWithDestructor<Void>
    #endif
}

private var indentLevel = 0

@inline(__always) func LogRelationIterationBegin<T: Relation>(caller: T) -> RelationIterationLoggingData {
    #if LOG_RELATION_ITERATION
        let description: String
        if let obj = caller as? AnyObject {
            description = String(format: "%@ %p", NSStringFromClass(obj.dynamicType), unsafeAddressOf(obj))
        } else {
            description = String(caller.dynamicType)
        }
        let now = NSProcessInfo().systemUptime
        
        let indentString = "".stringByPaddingToLength(indentLevel * 4, withString: " ", startingAtIndex: 0)
        print("\(indentString)\(description) began iteration at \(now)")
        
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
    #if LOG_RELATION_ITERATION
        var rowCount = 0
        let indentString = "".stringByPaddingToLength(data.indentLevel * 4, withString: " ", startingAtIndex: 0)
        return AnyGenerator(body: {
            let next = generator.next()
            switch next {
            case .Some(.Ok(let row)):
                print("\(indentString)\(data.callerDescription) returning row \(row)")
                rowCount += 1
            case .Some(.Err(let err)):
                print("\(indentString)\(data.callerDescription) returning error \(err)")
            case .None:
                print("\(indentString)\(data.callerDescription) finished iteration, produced \(rowCount) rows in \(NSProcessInfo().systemUptime - data.startTime) seconds")
            }
            return next
        })
    #else
    return generator
    #endif
}
