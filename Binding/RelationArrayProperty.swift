//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

public class RowArrayElement: ArrayElement {
    public typealias ID = RelationValue
    public typealias Data = Row

    public let id: RelationValue
    public var data: Row
    
    init(id: RelationValue, data: Row) {
        self.id = id
        self.data = data
    }
}

class RelationArrayProperty: ArrayProperty<RowArrayElement> {
    
    private let relation: Relation
    private let workOn: Scheduler
    private let observeOn: Scheduler
    private let idAttr: Attribute
    private let orderAttr: Attribute
    
    private var removal: ObserverRemoval!

    init(relation: Relation, workOn: Scheduler, observeOn: Scheduler, idAttr: Attribute, orderAttr: Attribute) {
        precondition(relation.scheme.attributes.isSupersetOf([idAttr, orderAttr]))
        
        self.relation = relation
        self.workOn = workOn
        self.observeOn = observeOn
        self.idAttr = idAttr
        self.orderAttr = orderAttr

        super.init(initialState: .Computing(nil))

        // TODO: There's a race here; need to make sure any relation changes observed while loading the
        // initial relation data are accounted for
        workOn.schedule{ [weak self] in
            guard let weakSelf = self else { return }
            
            // Pull data from the relation to compute the initial array state
            // TODO: Error handling
            let unsortedRows = relation.rows().map{ $0.ok! }
            let sortedRows = unsortedRows.sort{ $0[orderAttr] < $1[orderAttr] }
            let elements = sortedRows.map{ RowArrayElement(id: $0[idAttr], data: $0) }
            let newState: AsyncState<[Element]> = .Ready(elements)
            weakSelf.state.withMutableValue{ $0 = newState }

            // Notify observers of the initial computed state
            observeOn.schedule{ [weak self] in
                self?.notifyObservers(newState: newState, arrayChanges: [])
            }
        }
        
        self.removal = relation.addChangeObserver({ [weak self] changes in
            // TODO: We're assuming here that `relation` was updated on the `workOn` scheduler;
            // we should probably just perform this on `workOn` just to be sure
            self?.handleRelationChanges(changes)
        })
    }
    
    deinit {
        removal()
    }
    
    // Must be called in the context of the `workOn` scheduler.
    private func handleRelationChanges(relationChanges: RelationChange) {
        // Notify observers that we're entering a Computing state
        var computingState: AsyncState<[Element]>!
        self.state.withMutableValue{
            let existingArray = $0.data
            computingState = .Computing(existingArray)
            $0 = computingState
        }
        observeOn.schedule{ [weak self] in
            self?.notifyObservers(newState: computingState, arrayChanges: [])
        }

        // Compute array changes
        var newState: AsyncState<[Element]>!
        var arrayChanges: [Change] = []
        self.state.withMutableValue{
            var elems = $0.data ?? []
            let parts = relationChanges.parts(self.idAttr)
        
            arrayChanges.appendContentsOf(self.onInsert(parts.addedRows, elems: &elems))
            arrayChanges.appendContentsOf(self.onUpdate(parts.updatedRows, elems: &elems))
            arrayChanges.appendContentsOf(self.onDelete(parts.deletedIDs, elems: &elems))

            newState = .Ready(elems)
            $0 = newState
        }

        // Notify observers of the new state
        if arrayChanges.count > 0 {
            observeOn.schedule{ [weak self] in
                self?.notifyObservers(newState: newState, arrayChanges: arrayChanges)
            }
        }
    }

    override func insert(row: Row, pos: Pos) {
        // TODO: Provide insert/delete/move as extension defined where R: MutableRelation
        guard var relation = relation as? MutableRelation else {
            fatalError("insert() is only supported when the underlying relation is mutable")
        }

        // Determine the position of the row to be inserted relative to the current array state
        // TODO: Shouldn't we be doing this in the `workOn` context?
        var mutableRow = row
        self.state.withValue{
            let elems = $0.data ?? []
            mutableRow[orderAttr] = self.orderForPos(pos, elems: elems)
        }

        // Insert into the relation
        workOn.schedule{
            relation.add(mutableRow)
        }
    }
    
    // Must be called in the context of the `workOn` scheduler.
    private func onInsert(rows: [Row], inout elems: [Element]) -> [Change] {

        func insertElement(element: Element) -> Int {
            return elems.insertSorted(element, { $0.data[self.orderAttr] })
        }

        func insertRow(row: Row) -> Int {
            let id = row[self.idAttr]
            let element = RowArrayElement(id: id, data: row)
            return insertElement(element)
        }
        
        var changes: [Change] = []
        for row in rows {
            let index = insertRow(row)
            changes.append(.Insert(index))
        }

        return changes
    }

    override func delete(id: RelationValue) {
        guard var relation = relation as? MutableRelation else {
            fatalError("delete() is only supported when the underlying relation is mutable")
        }

        // Delete from the relation
        workOn.schedule{
            relation.delete(self.idAttr *== id)
        }
    }

    // Must be called in the context of the `workOn` scheduler.
    private func onDelete(ids: [RelationValue], inout elems: [Element]) -> [Change] {
        var changes: [Change] = []
        
        for id in ids {
            if let index = elems.indexOf({ $0.id == id }) {
                elems.removeAtIndex(index)
                changes.append(.Delete(index))
            }
        }
        
        return changes
    }

    /// Note: dstIndex is relative to the state of the array *after* the item is removed.
    override func move(srcIndex srcIndex: Int, dstIndex: Int) {
        var elemID: RelationValue!
        var newOrder: RelationValue!

        // Determine the order of the element in its new position (relative to the current array state)
        // TODO: Shouldn't we be doing this in the `workOn` context?
        self.state.withValue{
            let elems = $0.data ?? []
            let element = elems[srcIndex]
            elemID = element.id
        
            let (previous, next) = self.adjacentElementsForIndex(dstIndex, notMatching: element, inElements: elems)
            newOrder = self.orderForElementBetween(previous, next, elems: elems)
        }

        // Update the relation
        workOn.schedule{
            var mutableRelation = self.relation
            mutableRelation.update(self.idAttr *== elemID, newValues: [self.orderAttr: newOrder])
        }
    }
    
    // Must be called in the context of the `workOn` scheduler.
    private func onUpdate(rows: [Row], inout elems: [Element]) -> [Change] {
        var changes: [Change] = []
        
        for row in rows {
            let newOrder = row[orderAttr]
            if newOrder != .NotFound {
                let id = row[idAttr]
                let element = elementForID(id, elems)!
                changes.append(self.onMove(element, dstOrder: newOrder, elems: &elems))
            }
        }
        
        return changes
    }
    
    // Must be called in the context of the `workOn` scheduler.
    private func onMove(element: Element, dstOrder: RelationValue, inout elems: [Element]) -> Change {
        // Remove the element from the array
        let srcIndex = indexForID(element.id, elems)!
        elems.removeAtIndex(srcIndex)
        
        // Update the order value in the element's row
        element.data[orderAttr] = dstOrder
        
        // Insert the element in its new position
        let dstIndex = elems.insertSorted(element, { $0.data[self.orderAttr] })
        
        return .Move(srcIndex: srcIndex, dstIndex: dstIndex)
    }
    
    private func adjacentElementsForIndex(index: Int, notMatching element: Element, inElements elems: [Element]) -> (Element?, Element?) {
        // Note: In the case where an element is being reordered, the array will still contain that element,
        // but `index` represents the new position assuming it was already removed, so we use the `notMatching`
        // element to avoid choosing that same element again.
        
        func elementAtIndex(i: Int, alt: Int) -> Element? {
            if let e = elems[safe: i] {
                if e !== element {
                    return e
                } else {
                    return elems[safe: alt]
                }
            } else {
                return nil
            }
        }
        
        let lo = elementAtIndex(index - 1, alt: index - 2)
        let hi = elementAtIndex(index,     alt: index + 1)
        return (lo, hi)
    }
    
    private func orderForElementBetween(previous: Element?, _ next: Element?, elems: [Element]) -> RelationValue {
        let prev: Element?
        if previous == nil && next == nil {
            // Add after the last element
            prev = elems.last
        } else {
            // Insert after previous element
            prev = previous
        }
        
        // TODO: Use a more appropriate data type for storing order
        func orderForElement(element: Element) -> Double {
            return element.data[orderAttr].get()!
        }
        
        let lo: Double = prev.map(orderForElement) ?? 1.0
        let hi: Double = next.map(orderForElement) ?? 9.0
        return RelationValue(lo + ((hi - lo) / 2.0))
    }
    
    private func orderForPos(pos: Pos, elems: [Element]) -> RelationValue {
        let prev = pos.previousID.flatMap{ elementForID($0, elems) }
        let next = pos.nextID.flatMap{ elementForID($0, elems) }
        return orderForElementBetween(prev, next, elems: elems)
    }
}

extension Relation {
    /// Returns an ArrayProperty that gets its data from this relation.
    public func arrayProperty(workOn workOn: Scheduler = QueueScheduler(), observeOn: Scheduler = UIScheduler(), idAttr: Attribute = "id", orderAttr: Attribute = "order") -> ArrayProperty<RowArrayElement> {
        return RelationArrayProperty(relation: self, workOn: workOn, observeOn: observeOn, idAttr: idAttr, orderAttr: orderAttr)
    }
}
