//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// A value which is either a successful result, or an error.
public enum Result<T, E> {
    /// A successful result.
    case Ok(T)
    
    /// An error.
    case Err(E)
}

extension Result {
    /// Provide the result value for success, and `nil` for failure.
    public var ok: T? {
        switch self {
        case .Ok(let t): return t
        default: return nil
        }
    }
    
    /// Provide the result value for success, and fatal error for failure.
    public var forcedOK: T {
        switch self {
        case .Ok(let t): return t
        case .Err(let err): fatalError("Unexpectedly found error when force unwrapping \(type(of: self)): \(err)")
        }
    }
    
    /// Provide the error value for errors, and `nil` for success.
    public var err: E? {
        switch self {
        case .Err(let e): return e
        default: return nil
        }
    }
}

extension Result {
    /// Map the `Result` to a new `Result` by applying the given function to the underlying
    /// value for success, or propagating the error for failure.
    public func map<NewT>(_ f: (T) throws -> NewT) rethrows -> Result<NewT, E> {
        switch self {
        case .Ok(let t): return .Ok(try f(t))
        case .Err(let e): return .Err(e)
        }
    }
    
    /// Map the `Result` to a new `Result` by applying the given function to the underlying
    /// value for success, or propagating the error for failure. Returns `nil` if the function
    /// returns nil.
    public func map<NewT>(_ f: (T) throws -> NewT?) rethrows -> Result<NewT, E>? {
        switch self {
        case .Ok(let t): return try f(t).map({ .Ok($0) })
        case .Err(let e): return .Err(e)
        }
    }
    
    /// Map the `Result` to a new `Result` by applying the given function to the error,
    /// or propagating the value for success.
    public func mapErr<NewE>(_ f: (E) throws -> NewE) rethrows -> Result<T, NewE> {
        switch self {
        case .Ok(let t): return .Ok(t)
        case .Err(let e): return .Err(try f(e))
        }
    }
    
    /// Map the `Result` to a new `Result` by applying the given function to the underlying value
    /// for success, or propagating the error for failure. Takes a function which returns a `Result`,
    /// and returns the error if that function returns an error.
    public func flatMap<NewT>(_ f: (T) throws -> Result<NewT, E>) rethrows -> Result<NewT, E> {
        switch self {
        case .Ok(let t): return try f(t)
        case .Err(let e): return .Err(e)
        }
    }
    
    /// The same as `flatMap`.
    public func then<NewT>(_ f: (T) throws -> Result<NewT, E>) rethrows -> Result<NewT, E> {
        return try flatMap(f)
    }
}

extension Result {
    /// If both `self` and `other` are success, return `self`. Otherwise return
    /// the first error in the pair.
    public func and(_ other: Result<T, E>) -> Result<T, E> {
        return self.ok == nil ? self : other
    }
    
    /// If either `self` or `other` are success, return the first value in the pair.
    /// Otherwise return the first error in the pair.
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

/// Iterate over a sequence of `Result`s, checking each value against the predicate. If a value is found where the
/// predicate is `true`, return `true`. If an error is found first, return that error. If no matching value and no
/// error is found, return `false`.
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

/// Take an Optional<Result> and turn it into a Result<Optional>.
public func hoistOptional<T, E>(_ optionalResult: Result<T, E>?) -> Result<T?, E> {
    return optionalResult.map({ $0.map({ $0 }) }) ?? .Ok(nil)
}

extension Result {
    /// Transform two `Result`s into a single `Result` whose value is a tuple containing the two
    /// original values.
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
    /// Return the underlying value. If the `Result` contains an error, throw that error.
    /// NOTE: The error type must be something throwable (i.e. conforms to `Swift.Error`)
    /// but this can't be enforced in the type system currently, so it's up to you to
    /// only call this when the type is appropriate.
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

extension Result where E == Error {
    /// Convert a throwing expression into a `Result`. If the expression returns a value, the `Result`
    /// contains that value as success. If it throws, the `Result` contains the thrown error as an error.
    public init(_ f: @autoclosure () throws -> T) {
        do {
            let value = try f()
            self = .Ok(value)
        } catch {
            self = .Err(error)
        }
    }
}

precedencegroup ResultFlatMapPrecedence {
    associativity: left
}

/// The flatMap (aka bind) operator.
infix operator >>- : ResultFlatMapPrecedence
public func >>- <T, E, NT>(result: Result<T, E>, next: (T) -> Result<NT, E>) -> Result<NT, E> {
    return result.flatMap(next)
}

/// Alternate flatMap that assumes a Void success value (allows for chaining without braces).
infix operator >>>- : ResultFlatMapPrecedence
public func >>>- <E>(result: Result<Void, E>, next: @autoclosure () -> Result<Void, E>) -> Result<Void, E> {
    return result.flatMap(next)
}
