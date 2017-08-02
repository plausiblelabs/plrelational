//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc: Implementation detail (will be made non-public eventually)
/// A set of arbitrary objects which can be iterated and can later be removed.
/// Ideal for observer callbacks.
public class RemovableSet<T>: Sequence {
    private var nextNumber: UInt64 = 0
    private var contents: [UInt64: T] = [:]
    
    public init() {}
    
    /// Add a value to the set. Returns a remover which, when called, removes the value from the set.
    public func add(_ value: T) -> RemovableSetRemover {
        let number = nextNumber
        nextNumber += 1
        
        contents[number] = value
        return {
            self.contents.removeValue(forKey: number)
        }
    }
    
    public func makeIterator() -> LazyMapIterator<DictionaryIterator<UInt64, T>, T> {
        return contents.values.makeIterator()
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
/// A set of observer functions which take some parameter and return Void.
/// The same as RemovableSet aside from constraining the content type and
/// providing a notify method to make it easier to call the observers.
public class RemovableFunctionSet<Params>: RemovableSet<(Params) -> Void> {
    public func notify(_ params: Params) {
        for f in self {
            f(params)
        }
    }
}

public typealias RemovableSetRemover = (Void) -> Void
