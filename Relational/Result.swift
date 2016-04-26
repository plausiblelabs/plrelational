
public enum Result<T, E> {
    case Ok(T)
    case Err(E)
}

extension Result {
    var ok: T? {
        switch self {
        case .Ok(let t): return t
        default: return nil
        }
    }
    
    var err: E? {
        switch self {
        case .Err(let e): return e
        default: return nil
        }
    }
}

extension Result {
    func map<NewT>(@noescape f: T -> NewT) -> Result<NewT, E> {
        switch self {
        case .Ok(let t): return .Ok(f(t))
        case .Err(let e): return .Err(e)
        }
    }
    
    func map<NewT>(@noescape f: T -> NewT?) -> Result<NewT, E>? {
        switch self {
        case .Ok(let t): return f(t).map({ .Ok($0) })
        case .Err(let e): return .Err(e)
        }
    }
    
    func then<NewT>(@noescape f: T -> Result<NewT, E>) -> Result<NewT, E> {
        switch self {
        case .Ok(let t): return f(t)
        case .Err(let e): return .Err(e)
        }
    }
}

/// For a Result that contains a sequence of Results, if it's Ok, iterate over the sequence, accumulating new Ok
/// values. If the Result contains Err, or any of the sequence elements are Err, then produce the first Err.
/// This is a free-standing function because I couldn't quite get it to work as an extension due to the extra
/// generic types. Referencing the inner types didn't make the compiler happy.
func mapOk<Seq, InnerT, NewT, E where Seq: SequenceType, Seq.Generator.Element == Result<InnerT, E>>(result: Result<Seq, E>, _ f: InnerT -> NewT) -> Result<[NewT], E> {
    return result.then({ mapOk($0, f) })
}

/// Iterate over a sequence of Results, invoking the given function for each Ok value and returning a Result for the
/// array it produces. If any sequence elements are Err, then return the first Err encountered.
func mapOk<Seq, InnerT, NewT, E where Seq: SequenceType, Seq.Generator.Element == Result<InnerT, E>>(seq: Seq, _ f: InnerT -> NewT) -> Result<[NewT], E> {
    var results: [NewT] = []
    for elt in seq {
        switch elt {
        case .Ok(let t): results.append(f(t))
        case .Err(let e): return .Err(e)
        }
    }
    return .Ok(results)
}

extension Result {
    func combine<U>(other: Result<U, E>) -> Result<(T, U), E> {
        switch (self, other) {
        case (.Ok(let t), .Ok(let u)): return .Ok((t, u))
        case (.Err(let e), _): return .Err(e)
        case (_, .Err(let e)): return .Err(e)
            
        default:
            fatalError("This should never be reached, but the compiler doesn't think the previous cases are exhaustive")
        }
    }
}

extension Result {
    func orThrow() throws -> T {
        // TODO EWW: Swift doesn't support the use of the protocol itself to satisfy a requirement like "E: ErrorType"
        // so we just check at runtime instead in order to support Result<T, ErrorType>.
        precondition(E.self is ErrorType.Type || E.self is ErrorType.Protocol, "orThrow can only be used with Results that have ErrorType as their error")
        
        switch self {
        case .Ok(let t): return t
        case .Err(let e): throw e as! ErrorType
        }
    }
}
