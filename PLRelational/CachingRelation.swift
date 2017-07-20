//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


/// This Relation passes data through unchanged, but it caches that data up to a certain limit.
/// Putting this on one side of a join can allow updates to be intelligently filtered.
open class CachingRelation: IntermediateRelation {
    private var observer: Observer!
    private var remover: AsyncManager.ObservationRemover!
    
    fileprivate let limit: Int
    
    /// The currently cached rows.
    public fileprivate(set) var cache: Set<Row>?
    
    /// Initialize a caching relation wrapping another relation. If the number of rows in
    /// the relation is equal to or lower than `limit`, then those rows will be cached in
    /// `cache`.
    public init(_ subRelation: Relation, limit: Int) {
        self.limit = limit
        
        super.init(op: .union, operands: [subRelation])
        
        observer = Observer(owner: self)
        remover = subRelation.addAsyncObserver(observer)
        subRelation.asyncAllRows(self.setRows)
    }
    
    deinit {
        remover()
    }
    
    fileprivate func setRows(_ result: Result<Set<Row>, RelationError>) {
        if let rows = result.ok, rows.count <= limit {
            cache = rows
        } else {
            cache = nil
        }
    }
    
    open override var contentProvider: RelationContentProvider {
        if let cache = cache {
            return .set({ cache }, approximateCount: Double(cache.count))
        } else {
            return super.contentProvider
        }
    }
}

extension CachingRelation {
    fileprivate class Observer: AsyncRelationContentCoalescedObserver {
        weak var owner: CachingRelation?
        
        init(owner: CachingRelation) {
            self.owner = owner
        }
        
        func relationWillChange(_ relation: Relation) {
            owner?.cache = nil
        }
        
        func relationDidChange(_ relation: Relation, result: Result<Set<Row>, RelationError>) {
            print("Relation did change to \(result)")
            owner?.setRows(result)
        }
    }
}

extension Relation {
    /// Return a new CachingRelation that caches `self` up to the specified limit
    public func cache(upTo: Int) -> CachingRelation {
        return CachingRelation(self, limit: upTo)
    }
}
