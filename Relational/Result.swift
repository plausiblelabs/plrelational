//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public enum Result<T, E> {
    case Ok(T)
    case Err(E)
}

extension Result {
    public var ok: T? {
        switch self {
        case .Ok(let t): return t
        default: return nil
        }
    }
    
    public var err: E? {
        switch self {
        case .Err(let e): return e
        default: return nil
        }
    }
}

extension Result {
    public func map<NewT>(@noescape f: T -> NewT) -> Result<NewT, E> {
        switch self {
        case .Ok(let t): return .Ok(f(t))
        case .Err(let e): return .Err(e)
        }
    }
    
    public func map<NewT>(@noescape f: T -> NewT?) -> Result<NewT, E>? {
        switch self {
        case .Ok(let t): return f(t).map({ .Ok($0) })
        case .Err(let e): return .Err(e)
        }
    }
    
    public func mapErr<NewE>(@noescape f: E -> NewE) -> Result<T, NewE> {
        switch self {
        case .Ok(let t): return .Ok(t)
        case .Err(let e): return .Err(f(e))
        }
    }
    
    public func then<NewT>(@noescape f: T -> Result<NewT, E>) -> Result<NewT, E> {
        switch self {
        case .Ok(let t): return f(t)
        case .Err(let e): return .Err(e)
        }
    }
}

extension Result {
    public func and(other: Result<T, E>) -> Result<T, E> {
        return self.ok == nil ? self : other
    }
    
    public func or(other: Result<T, E>) -> Result<T, E> {
        return self.err == nil ? self : other
    }
}

/// For a Result that contains a sequence of Results, if it's Ok, iterate over the sequence, accumulating new Ok
/// values. If the Result contains Err, or any of the sequence elements are Err, then produce the first Err.
/// This is a free-standing function because I couldn't quite get it to work as an extension due to the extra
/// generic types. Referencing the inner types didn't make the compiler happy.
public func mapOk<Seq, InnerT, NewT, E where Seq: SequenceType, Seq.Generator.Element == Result<InnerT, E>>(result: Result<Seq, E>, @noescape _ f: InnerT -> NewT) -> Result<[NewT], E> {
    return result.then({ mapOk($0, f) })
}

/// Iterate over a sequence of Results, invoking the given function for each Ok value and returning a Result for the
/// array it produces. If any sequence elements are Err, then return the first Err encountered.
public func mapOk<Seq, InnerT, NewT, E where Seq: SequenceType, Seq.Generator.Element == Result<InnerT, E>>(seq: Seq, @noescape _ f: InnerT -> NewT) -> Result<[NewT], E> {
    var results: [NewT] = []
    for elt in seq {
        switch elt {
        case .Ok(let t): results.append(f(t))
        case .Err(let e): return .Err(e)
        }
    }
    return .Ok(results)
}

/// Iterate over a sequence of Results, invoking the given function for each Ok value and returning a Result for the
/// array it produces. If any sequence elements are Err, then return the first Err encountered. If the function returns
/// nil, then that entry is omitted from the result
public func flatmapOk<Seq, InnerT, NewT, E where Seq: SequenceType, Seq.Generator.Element == Result<InnerT, E>>(seq: Seq, @noescape _ f: InnerT -> NewT?) -> Result<[NewT], E> {
    var results: [NewT] = []
    for elt in seq {
        switch elt {
        case .Ok(let t):
            if let mapped = f(t) {
                results.append(mapped)
            }
        case .Err(let e):
            return .Err(e)
        }
    }
    return .Ok(results)
}

public func containsOk<Seq, T, E where Seq: SequenceType, Seq.Generator.Element == Result<T, E>>(seq: Seq, _ predicate: T -> Bool) -> Result<Bool, E> {
    for elt in seq {
        switch elt {
        case .Ok(let t): if predicate(t) { return .Ok(true) }
        case .Err(let e): return .Err(e)
        }
    }
    return .Ok(false)
}

extension Result {
    public func combine<U>(other: Result<U, E>) -> Result<(T, U), E> {
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
    public func orThrow() throws -> T {
        // TODO EWW: Swift doesn't support the use of the protocol itself to satisfy a requirement like "E: ErrorType"
        // so we just check at runtime instead in order to support Result<T, ErrorType>.
        precondition(E.self is ErrorType.Type || E.self is ErrorType.Protocol, "orThrow can only be used with Results that have ErrorType as their error")
        
        switch self {
        case .Ok(let t): return t
        case .Err(let e): throw e as! ErrorType
        }
    }
}

/* The flatMap (aka bind) operator. */
infix operator >>- { associativity left }
public func >>- <T, E, NT>(result: Result<T, E>, next: T -> Result<NT, E>) -> Result<NT, E> {
    return result.then(next)
}

/* Alternate flatMap that assumes a Void success value (allows for chaining without braces). */
infix operator >>>- { associativity left }
public func >>>- <E>(result: Result<Void, E>, @autoclosure next: () -> Result<Void, E>) -> Result<Void, E> {
    return result.then(next)
}
