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
            // TODO: Error handling
            let unsortedRows = relation.rows().map{$0.ok!}
            let sortedRows = unsortedRows.sort({ $0[orderAttr] < $1[orderAttr] })
            let elements = sortedRows.map{RowArrayElement(id: $0[idAttr], data: $0)}
            weakSelf.state.withMutableValue{ $0 = .Ready(elements) }
            // TODO: Need to notify observers here
        }
        
        self.removal = relation.addChangeObserver({ [weak self] changes in
            self?.handleRelationChanges(changes)
        })
    }
    
    deinit {
        removal()
    }

    // Must be called in the context of the `workOn` scheduler.
    private func handleRelationChanges(relationChanges: RelationChange) {
        var arrayChanges: [Change] = []
        
        self.state.withMutableValue{
            var elems = $0.data ?? []
            let parts = relationChanges.parts(self.idAttr)
        
            arrayChanges.appendContentsOf(self.onInsert(parts.addedRows, elems: &elems))
            arrayChanges.appendContentsOf(self.onUpdate(parts.updatedRows, elems: &elems))
            arrayChanges.appendContentsOf(self.onDelete(parts.deletedIDs, elems: &elems))

            $0 = .Ready(elems)
        }

        // TODO: This is unsafe; observers really need to be notified while mutex is held
        // to ensure that changes are relative to current `state`
        if arrayChanges.count > 0 {
            observeOn.schedule{ [weak self] in
                self?.notifyChangeObservers(arrayChanges)
            }
        }
    }

    override func insert(row: Row, pos: Pos) {
        // TODO: Provide insert/delete/move as extension defined where R: MutableRelation
        guard var relation = relation as? MutableRelation else {
            fatalError("insert() is only supported when the underlying relation is mutable")
        }
        
        var mutableRow = row
        // TODO: This depends on the current `state`, so need to grab mutex
        mutableRow[orderAttr] = orderForPos(pos)
        
        // TODO: Need to perform `add` on the `workOn` scheduler
        relation.add(mutableRow)
    }
    
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
        // TODO: Need to perform `delete` on the `workOn` scheduler
        relation.delete(idAttr *== id)
    }

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
        // TODO: This depends on the current `state`, so need to grab mutex
        let element = elements[srcIndex]
        
        // Determine the order of the element in its new position
        let (previous, next) = adjacentElementsForIndex(dstIndex, notMatching: element)
        let newOrder = orderForElementBetween(previous, next)
        
        var mutableRelation = relation
        // TODO: Need to perform `update` on the `workOn` scheduler
        mutableRelation.update(idAttr *== element.id, newValues: [orderAttr: newOrder])
    }
    
    private func onUpdate(rows: [Row], inout elems: [Element]) -> [Change] {
        var changes: [Change] = []
        
        for row in rows {
            let newOrder = row[orderAttr]
            if newOrder != .NotFound {
                let id = row[idAttr]
                let element = elementForID(id)!
                changes.append(self.onMove(element, dstOrder: newOrder, elems: &elems))
            }
        }
        
        return changes
    }
    
    private func onMove(element: Element, dstOrder: RelationValue, inout elems: [Element]) -> Change {
        // Remove the element from the array
        let srcIndex = indexForID(element.id)!
        elems.removeAtIndex(srcIndex)
        
        // Update the order value in the element's row
        element.data[orderAttr] = dstOrder
        
        // Insert the element in its new position
        let dstIndex = elems.insertSorted(element, { $0.data[self.orderAttr] })
        
        return .Move(srcIndex: srcIndex, dstIndex: dstIndex)
    }
    
    private func adjacentElementsForIndex(index: Int, notMatching element: Element) -> (Element?, Element?) {
        // Note: In the case where an element is being reordered, the array will still contain that element,
        // but `index` represents the new position assuming it was already removed, so we use the `notMatching`
        // element to avoid choosing that same element again.
        
        func elementAtIndex(i: Int, alt: Int) -> Element? {
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
    
    private func orderForElementBetween(previous: Element?, _ next: Element?) -> RelationValue {
        let prev: Element?
        if previous == nil && next == nil {
            // Add after the last element
            prev = elements.last
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
    
    private func orderForPos(pos: Pos) -> RelationValue {
        let prev = pos.previousID.flatMap(elementForID)
        let next = pos.nextID.flatMap(elementForID)
        return orderForElementBetween(prev, next)
    }
}

extension Relation {
    /// Returns an ArrayProperty that gets its data from this relation.
    public func arrayProperty(workOn workOn: Scheduler = QueueScheduler(), observeOn: Scheduler = UIScheduler(), idAttr: Attribute = "id", orderAttr: Attribute = "order") -> ArrayProperty<RowArrayElement> {
        return RelationArrayProperty(relation: self, workOn: workOn, observeOn: observeOn, idAttr: idAttr, orderAttr: orderAttr)
    }
}
