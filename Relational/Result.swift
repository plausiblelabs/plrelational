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
    public func map<NewT>(_ f: (T) throws -> NewT) rethrows -> Result<NewT, E> {
        switch self {
        case .Ok(let t): return .Ok(try f(t))
        case .Err(let e): return .Err(e)
        }
    }
    
    public func map<NewT>(_ f: (T) throws -> NewT?) rethrows -> Result<NewT, E>? {
        switch self {
        case .Ok(let t): return try f(t).map({ .Ok($0) })
        case .Err(let e): return .Err(e)
        }
    }
    
    public func mapErr<NewE>(_ f: (E) throws -> NewE) rethrows -> Result<T, NewE> {
        switch self {
        case .Ok(let t): return .Ok(t)
        case .Err(let e): return .Err(try f(e))
        }
    }
    
    public func then<NewT>(_ f: (T) throws -> Result<NewT, E>) rethrows -> Result<NewT, E> {
        switch self {
        case .Ok(let t): return try f(t)
        case .Err(let e): return .Err(e)
        }
    }
}

extension Result {
    public func and(_ other: Result<T, E>) -> Result<T, E> {
        return self.ok == nil ? self : other
    }
    
    public func or(_ other: Result<T, E>) -> Result<T, E> {
        return self.err == nil ? self : other
    }
}

/// For a Result that contains a sequence of Results, if it's Ok, iterate over the sequence, accumulating new Ok
/// values. If the Result contains Err, or any of the sequence elements are Err, then produce the first Err.
/// This is a free-standing function because I couldn't quite get it to work as an extension due to the extra
/// generic types. Referencing the inner types didn't make the compiler happy.
public func mapOk<Seq, InnerT, NewT, E>(_ result: Result<Seq, E>, _ f: (InnerT) -> NewT) -> Result<[NewT], E> where Seq: Sequence, Seq.Iterator.Element == Result<InnerT, E> {
    return result.then({ mapOk($0, f) })
}

/// Iterate over a sequence of Results, invoking the given function for each Ok value and returning a Result for the
/// array it produces. If any sequence elements are Err, then return the first Err encountered.
public func mapOk<Seq, InnerT, NewT, E>(_ seq: Seq, _ f: (InnerT) -> NewT) -> Result<[NewT], E> where Seq: Sequence, Seq.Iterator.Element == Result<InnerT, E> {
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
public func flatmapOk<Seq, InnerT, NewT, E>(_ seq: Seq, _ f: (InnerT) -> NewT?) -> Result<[NewT], E> where Seq: Sequence, Seq.Iterator.Element == Result<InnerT, E> {
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

public func containsOk<Seq, T, E>(_ seq: Seq, _ predicate: (T) -> Bool) -> Result<Bool, E> where Seq: Sequence, Seq.Iterator.Element == Result<T, E> {
    for elt in seq {
        switch elt {
        case .Ok(let t): if predicate(t) { return .Ok(true) }
        case .Err(let e): return .Err(e)
        }
    }
    return .Ok(false)
}

/// Iterate over a sequence of values, invoking the given Result-producing function and returning a Result for the array
/// it produces.  If an Err result is produced for any element, then return the first Err encountered.
public func traverse<Seq, InnerT, NewT, E>(_ seq: Seq, _ f: (InnerT) -> Result<NewT, E>) -> Result<[NewT], E> where Seq: Sequence, Seq.Iterator.Element == InnerT {
    var results: [NewT] = []
    for elt in seq {
        let res = f(elt)
        switch res {
        case .Ok(let t): results.append(t)
        case .Err(let e): return .Err(e)
        }
    }
    return .Ok(results)
}

extension Result {
    public func combine<U>(_ other: Result<U, E>) -> Result<(T, U), E> {
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
        precondition(E.self is Error.Type || E.self is Error.Protocol, "orThrow can only be used with Results that have ErrorType as their error")
        
        switch self {
        case .Ok(let t): return t
        case .Err(let e): throw e as! Error
        }
    }
}

precedencegroup ResultFlatMapPrecedence {
    associativity: left
}

/* The flatMap (aka bind) operator. */
infix operator >>- : ResultFlatMapPrecedence
public func >>- <T, E, NT>(result: Result<T, E>, next: (T) -> Result<NT, E>) -> Result<NT, E> {
    return result.then(next)
}

/* Alternate flatMap that assumes a Void success value (allows for chaining without braces). */
infix operator >>>- : ResultFlatMapPrecedence
public func >>>- <E>(result: Result<Void, E>, next: @autoclosure () -> Result<Void, E>) -> Result<Void, E> {
    return result.then(next)
}
