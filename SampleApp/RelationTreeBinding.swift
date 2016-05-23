//
//  RelationTreeBinding.swift
//  Relational
//
//  Created by Chris Campbell on 5/6/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational

extension Row: TreeData {
    public typealias ID = RelationValue
    
    public var id: RelationValue {
        // TODO: Need to use the attribute provided to RelationTreeBinding init
        return self["id"]
    }
    
    public var parentID: RelationValue? {
        // TODO: Need to use the attribute provided to RelationTreeBinding init
        let parent = self["parent"]
        if parent != .NULL {
            return parent
        } else {
            return nil
        }
    }
}

public class RelationTreeBinding: TreeBinding<Row> {

    private let relation: Relation
    private let idAttr: Attribute
    private let parentAttr: Attribute
    private let orderAttr: Attribute
    
    private var removal: ObserverRemoval!
    
    init(relation: Relation, idAttr: Attribute, parentAttr: Attribute, orderAttr: Attribute) {
        self.relation = relation
        self.idAttr = idAttr
        self.parentAttr = parentAttr
        self.orderAttr = orderAttr
        
        super.init(root: Node(id: -1, data: Row()))
        
        // TODO: Depth
        // TODO: Sorting
        // TODO: Error handling
        // TODO: For now, we'll load the whole tree structure eagerly
        //let rows = relation.rows().map{$0.ok!}

        func handle(relation: Relation, inout _ treeChanges: [Change], _ f: (Row) -> [Change]) {
            for rowResult in relation.rows() {
                switch rowResult {
                case .Ok(let row):
                    treeChanges.appendContentsOf(f(row))
                case .Err(let err):
                    // TODO: error handling again
                    fatalError("Error fetching rows: \(err)")
                }
            }
        }
        
        self.removal = relation.addChangeObserver({ changes in
            var treeChanges: [Change] = []
            
            if let adds = changes.added {
                let added: Relation
                if let removes = changes.removed {
                    added = adds.project([self.idAttr]).difference(removes.project([self.idAttr])).join(adds)
                } else {
                    added = adds
                }
                handle(added, &treeChanges, self.onInsert)
            }
            
            if let adds = changes.added, removes = changes.removed {
                let updated = removes.project([self.idAttr]).join(adds)
                handle(updated, &treeChanges, self.onUpdate)
            }

            if let removes = changes.removed {
                let removed: Relation
                if let adds = changes.added {
                    removed = removes.project([self.idAttr]).difference(adds.project([self.idAttr])).join(removes)
                } else {
                    removed = removes
                }
                // TODO: rather than iterate here, maybe hand the whole relation over to onDelete
                handle(removed, &treeChanges, self.onDelete)
            }
            
            if treeChanges.count > 0 {
                self.notifyChangeObservers(treeChanges)
            }
        })
    }
    
    public func insert(row: Row, pos: Pos) {
        // TODO: Provide insert/delete/move as extension defined where R: MutableRelation
        guard var relation = relation as? MutableRelation else {
            fatalError("insert() is only supported when the underlying relation is mutable")
        }
        
        let parentIDValue = pos.parentID ?? .NULL
        let order: RelationValue = orderForPos(pos)
        
        var mutableRow = row
        mutableRow[parentAttr] = parentIDValue
        mutableRow[orderAttr] = order

        relation.add(mutableRow)
    }
    
    private func onInsert(row: Row) -> [Change] {

        func insertNode(node: Node, parent: Node) -> Int {
            return parent.children.insertSorted(node, { self.orderForNode($0) })
        }

        let node = Node(id: row[idAttr], data: row)
        let parentID = row[parentAttr]
        let parent: Node?
        let index: Int
        if parentID != .NULL {
            let parentNode = nodeForID(parentID)!
            parent = parentNode
            index = insertNode(node, parent: parentNode)
        } else {
            parent = nil
            index = insertNode(node, parent: root)
        }
        
        let path = Path(parent: parent, index: index)
        return [.Insert(path)]
    }
    
    public func delete(id: RelationValue) {
        guard var relation = relation as? MutableRelation else {
            fatalError("delete() is only supported when the underlying relation is mutable")
        }

        // Grab the node before we delete from the relation; otherwise if we are being called
        // outside of a transaction, the node may be deleted by onDelete() just after we call
        // relation.delete() below
        let node = nodeForID(id)
        
        // Delete from the relation
        // TODO: Should we delete from the bottom up?  The way things are ordered now,
        // observers will only be notified in onDelete() for the ancestor node; would it
        // make more sense to notify observers about all children?
        relation.delete(idAttr *== id)
        
        // Recursively delete descendant nodes
        // TODO: There are probably more efficient ways to handle this, but for now we'll
        // use our tree structure to determine which children need to be deleted
        if let node = node {
            for child in node.children {
                delete(child.id)
            }
        }
    }
    
    private func onDelete(row: Row) -> [Change] {

        func deleteNode(node: Node, inout _ nodes: [Node]) -> Int {
            let index = nodes.indexOf({$0 === node})!
            nodes.removeAtIndex(index)
            return index
        }
        
        let id = row[idAttr]
        if let node = nodeForID(id) {
            let parent: Node?
            let index: Int
            let parentID = node.data[parentAttr]
            if parentID != .NULL {
                let parentNode = nodeForID(parentID)!
                parent = parentNode
                index = deleteNode(node, &parentNode.children)
            } else {
                parent = nil
                index = deleteNode(node, &root.children)
            }
            
            let path = TreePath(parent: parent, index: index)
            return [.Delete(path)]
        } else {
            return []
        }
    }

    /// Note: dstPath.index is relative to the state of the array *after* the item is removed.
    public func move(srcPath srcPath: Path, dstPath: Path) {
        let srcParent = srcPath.parent ?? root
        let dstParent = dstPath.parent ?? root

        let srcNode = srcParent.children[srcPath.index]
        let srcID = srcNode.id
        
        let dstParentID: RelationValue
        if let dstParent = dstPath.parent {
            dstParentID = dstParent.id
        } else {
            dstParentID = .NULL
        }
        
        // Note that dstPath.index of -1 can occur in the case where a node is being dragged onto another
        let dstIndex: Int
        if dstPath.index < 0 {
            dstIndex = dstParent.children.count
        } else {
            dstIndex = dstPath.index
        }
        
        // Determine the order of the node in its new parent and/or position
        let (previous, next) = adjacentNodesForIndex(dstIndex, inParent: dstParent, notMatching: srcNode)
        let newOrder = orderWithinParent(dstParent, previous: previous, next: next)
        
        var mutableRelation = relation
        mutableRelation.update(idAttr *== srcID, newValues: [
            parentAttr: dstParentID,
            orderAttr: newOrder
        ])
    }

    private func onUpdate(row: Row) -> [Change] {
        let newParentID = row[parentAttr]
        let newOrder = row[orderAttr]
        if newParentID == .NotFound || newOrder == .NotFound {
            // TODO: We should be able to perform the move if only one of parent/order were updated
            return []
        }

        let srcID = row[idAttr]
        let srcNode = nodeForID(srcID)!
        return onMove(srcNode, dstParentID: newParentID, dstOrder: newOrder)
    }
    
    private func onMove(node: Node, dstParentID: RelationValue, dstOrder: RelationValue) -> [Change] {
        let optSrcParent = parentForNode(node)
        let optDstParent: Node?
        if dstParentID == .NULL {
            optDstParent = nil
        } else {
            optDstParent = nodeForID(dstParentID)!
        }

        let srcParent = optSrcParent ?? root
        let dstParent = optDstParent ?? root

        // Remove the node from its current parent
        let srcIndex = srcParent.children.indexOf({ $0 === node })!
        srcParent.children.removeAtIndex(srcIndex)
        
        // Update the values in the node's row
        node.data[parentAttr] = dstParentID
        node.data[orderAttr] = dstOrder

        // Insert the node in its new parent
        let dstIndex = dstParent.children.insertSorted(node, { self.orderForNode($0) })

        // Prepare changes
        let newSrcPath = TreePath(parent: optSrcParent, index: srcIndex)
        let newDstPath = TreePath(parent: optDstParent, index: dstIndex)
        return [.Move(src: newSrcPath, dst: newDstPath)]
    }

    private func adjacentNodesForIndex(index: Int, inParent parent: Node, notMatching node: Node) -> (Node?, Node?) {
        // Note: In the case where a node is being reordered within its existing parent, `parent` will
        // still contain that node, but `index` represents the new position assuming it was already removed,
        // so we use the `notMatching` node to avoid choosing that same node again.
        
        func safeGet(i: Int) -> Node? {
            if i >= 0 && i < parent.children.count {
                return parent.children[i]
            } else {
                return nil
            }
        }
        
        func nodeAtIndex(i: Int, alt: Int) -> Node? {
            if let n = safeGet(i) {
                if n !== node {
                    return n
                } else {
                    return safeGet(alt)
                }
            } else {
                return nil
            }
        }
        
        let lo = nodeAtIndex(index - 1, alt: index - 2)
        let hi = nodeAtIndex(index,     alt: index + 1)
        return (lo, hi)
    }
    
    private func orderWithinParent(parent: Node, previous: Node?, next: Node?) -> RelationValue {
        let prev: Node?
        if previous == nil && next == nil {
            // Add after the last child
            prev = parent.children.last
        } else {
            // Insert after previous child
            prev = previous
        }
        let lo: Double = prev.map(orderForNode) ?? 1.0
        let hi: Double = next.map(orderForNode) ?? 9.0
        return RelationValue(lo + ((hi - lo) / 2.0))
    }
    
    private func orderForPos(pos: Pos) -> RelationValue {
        let parent: Node
        if let parentID = pos.parentID {
            parent = nodeForID(parentID)!
        } else {
            parent = root
        }
        
        let previous = pos.previousID.flatMap(nodeForID)
        let next = pos.nextID.flatMap(nodeForID)
        
        return orderWithinParent(parent, previous: previous, next: next)
    }
    
    private func orderForNode(node: Node) -> Double {
        return node.data[orderAttr].get()!
    }
}
