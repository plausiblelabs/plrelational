//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

public class RowArrayElement: RowCollectionElement, ArrayElement {
    override init(id: RelationValue, data: Row, tag: AnyObject?) {
        super.init(id: id, data: data, tag: tag)
    }
}

private typealias Element = RowArrayElement
private typealias Pos = ArrayPos<Element>
private typealias Change = ArrayChange<Element>

class RelationArrayProperty: ArrayProperty<RowArrayElement> {
    
    private let relation: Relation
    fileprivate let idAttr: Attribute
    private let orderAttr: Attribute
    private let orderFunc: (RelationValue, RelationValue) -> Bool
    private let tag: AnyObject?
    fileprivate let sourceSignal: PipeSignal<SignalChange>
    
    private var relationObserverRemoval: ObserverRemoval?

    fileprivate init(relation: Relation, idAttr: Attribute, orderAttr: Attribute, descending: Bool, tag: AnyObject?) {
        precondition(relation.scheme.attributes.isSuperset(of: [idAttr, orderAttr]))
        
        self.relation = relation
        self.idAttr = idAttr
        self.orderAttr = orderAttr
        if descending {
            self.orderFunc = { $0 > $1 }
        } else {
            self.orderFunc = { $0 < $1 }
        }
        self.tag = tag

        self.sourceSignal = PipeSignal()
        
        super.init(signal: sourceSignal)

        // TODO: There is a possibility (however unlikely) that the underlying relation is already
        // in an async update, i.e., it has already delivered a relationWillChange.  If that happens,
        // setting changeCount to zero here will be incorrect.
        //var changeCount = 0
        sourceSignal.onObserve = { observer in
            if self.relationObserverRemoval == nil {
                // Observe the underlying relation the first time someone observes our public signal
                self.relationObserverRemoval = relation.addAsyncObserver(self)
                
                // Perform an async query to compute the initial array
                self.sourceSignal.notifyBeginPossibleAsyncChange()
                relation.asyncAllRows(
                    postprocessor: { rows -> [RowArrayElement] in
                        let sortedRows = rows.sorted{ self.orderFunc($0[self.orderAttr], $1[self.orderAttr]) }
                        return sortedRows.map{
                            RowArrayElement(id: $0[self.idAttr], data: $0, tag: self.tag)
                        }
                    },
                    completion: { result in
                        if let sortedElements = result.ok {
                            self.elements = sortedElements
                            self.sourceSignal.notifyValueChanging([.initial(sortedElements)], transient: false)
                        }
                        self.sourceSignal.notifyEndPossibleAsyncChange()
                    }
                )
            } else {
                // For subsequent observers, deliver our current value to just the observer being attached
//                for _ in 0..<changeCount {
//                    // If the underlying relation is in an asynchronous change (delivered WillChange before
//                    // this observer was attached), we need to give this new observer the corresponding
//                    // number of WillChange notifications so that it is correctly balanced when the
//                    // DidChange notification(s) come in later
//                    observer.notifyBeginPossibleAsyncChange()
//                }
                observer.notifyValueChanging([.initial(self.elements)], transient: false)
            }
        }
    }
    
    deinit {
        relationObserverRemoval?()
    }
    
    fileprivate func onInsert(_ rows: [Row], changes: inout [Change]) {
        var insertedIDs: [RelationValue] = []

        func insertElement(_ element: Element) {
            _ = elements.insertSorted(element, { $0.data[orderAttr] }, orderFunc)
        }

        func insertRow(_ row: Row) {
            let id = row[idAttr]
            let element = RowArrayElement(id: id, data: row, tag: self.tag)
            insertElement(element)
            insertedIDs.append(id)
        }
        
        // First insert the rows
        for row in rows {
            insertRow(row)
        }
        
        // Once all rows are inserted, find the unique insertion index for each one
        // so that changes are reported deterministically
        var indexes: [Int] = []
        for id in insertedIDs {
            if let index = elements.firstIndex(where: { $0.id == id }) {
                indexes.append(index)
            }
        }
        for index in indexes.sorted() {
            changes.append(.insert(index))
        }
    }

    fileprivate func onDelete(_ ids: [RelationValue], changes: inout [Change]) {
        for id in ids {
            if let index = elements.firstIndex(where: { $0.id == id }) {
                elements.remove(at: index)
                changes.append(.delete(index))
            }
        }
    }

    fileprivate func onUpdate(_ rows: [Row], changes: inout [Change]) {
        for row in rows {
            let id = row[idAttr]
            if let element = elementForID(id) {
                // Capture the old/new order values
                let oldOrder = element.data[orderAttr]
                let newOrder = row[orderAttr]
                
                // Update the element's row data
                element.data = element.data.rowWithUpdate(row)

                if newOrder != .notFound && newOrder != oldOrder {
                    // The order *might* be changing
                    // TODO: Check whether the order is changing without actually doing
                    // the remove/insert first
                    
                    // Remove the element from the array
                    let srcIndex = indexForID(element.id)!
                    _ = elements.remove(at: srcIndex)
                    
                    // Insert the element in its new position
                    let dstIndex = elements.insertSorted(element, { $0.data[orderAttr] }, orderFunc)

                    if dstIndex != srcIndex {
                        // This is a move
                        changes.append(.move(srcIndex: srcIndex, dstIndex: dstIndex))
                    } else {
                        // The order is unchanged, treat it as a simple update
                        changes.append(.update(dstIndex))
                    }
                } else {
                    // Treat this as an update
                    if let index = indexForID(id) {
                        changes.append(.update(index))
                    }
                }
            }
        }
    }
    
    private func adjacentElementsForIndex(_ index: Int, notMatching element: Element) -> (Element?, Element?) {
        // Note: In the case where an element is being reordered, the array will still contain that element,
        // but `index` represents the new position assuming it was already removed, so we use the `notMatching`
        // element to avoid choosing that same element again.
        
        func elementAtIndex(_ i: Int, alt: Int) -> Element? {
            if let e = elements[safe: i] {
                if e !== element {
                    return e
                } else {
                    return elements[safe: alt]
                }
            } else {
                return nil
            }
        }
        
        let lo = elementAtIndex(index - 1, alt: index - 2)
        let hi = elementAtIndex(index,     alt: index + 1)
        return (lo, hi)
    }
    
    private func orderForElementBetween(_ previous: Element?, _ next: Element?) -> Double {
        let prev: Element?
        if previous == nil && next == nil {
            // Add after the last element
            prev = elements.last
        } else {
            // Insert after previous element
            prev = previous
        }
        
        // TODO: Use a more appropriate data type for storing order
        func orderForElement(_ element: Element) -> Double {
            return element.data[orderAttr].get()!
        }
        
        let lo: Double = prev.map(orderForElement) ?? 1.0
        let hi: Double = next.map(orderForElement) ?? 9.0
        return lo + ((hi - lo) / 2.0)
    }
    
    override func orderForPos(_ pos: ArrayPos<RowArrayElement>) -> Double {
        let prev = pos.previousID.flatMap(elementForID)
        let next = pos.nextID.flatMap(elementForID)
        return orderForElementBetween(prev, next)
    }
    
    override func orderForMove(srcIndex: Int, dstIndex: Int) -> Double {
        // Note: dstIndex is relative to the state of the array *after* the item is removed
        let element = elements[srcIndex]
        let (prev, next) = adjacentElementsForIndex(dstIndex, notMatching: element)
        return orderForElementBetween(prev, next)
    }
}

extension RelationArrayProperty: AsyncRelationChangeCoalescedObserver {

    func relationWillChange(_ relation: Relation) {
        sourceSignal.notifyBeginPossibleAsyncChange()
    }

    func relationDidChange(_ relation: Relation, result: Result<RowChange, RelationError>) {
        switch result {
        case .Ok(let rows):
            // Compute array changes
            let parts = partsOf(rows, idAttr: idAttr)
            if !parts.isEmpty {
                var arrayChanges: [Change] = []
                self.onDelete(parts.deletedIDs, changes: &arrayChanges)
                self.onInsert(parts.addedRows, changes: &arrayChanges)
                self.onUpdate(parts.updatedRows, changes: &arrayChanges)
                if arrayChanges.count > 0 {
                    sourceSignal.notifyValueChanging(arrayChanges, transient: false)
                }
            }
            sourceSignal.notifyEndPossibleAsyncChange()
            
        case .Err(let err):
            // TODO: actual handling
            fatalError("Got error for relation change: \(err)")
        }
    }
}

extension Relation {
    
    // MARK: ArrayProperty creation
    
    /// Returns an ArrayProperty that gets its data from this relation.
    public func arrayProperty(idAttr: Attribute, orderAttr: Attribute, descending: Bool = false, tag: AnyObject? = nil) -> ArrayProperty<RowArrayElement> {
        return RelationArrayProperty(relation: self, idAttr: idAttr, orderAttr: orderAttr, descending: descending, tag: tag)
    }
}
