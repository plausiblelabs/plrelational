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
}

public class RelationTreeBinding: TreeBinding<Row> {

    private class RowTreeNode: TreeNode<Row> {
        let parentAttr: Attribute
        
        init(id: RelationValue, row: Row, parentAttr: Attribute) {
            self.parentAttr = parentAttr
            super.init(id: id, data: row)
        }
        
        override var parentID: RelationValue? {
            let parent = data[parentAttr]
            if parent != .NULL {
                return parent
            } else {
                return nil
            }
        }
    }
    
    private let relation: Relation
    private let idAttr: Attribute
    private let parentAttr: Attribute
    private let orderAttr: Attribute
    
    private var removal: ObserverRemoval!
    
    public init(relation: Relation, idAttr: Attribute, parentAttr: Attribute, orderAttr: Attribute) {
        
        // Map Rows from underlying Relation to Node values.
        var nodeDict = [RelationValue: Node]()
        for row in relation.rows().map({$0.ok!}) {
            nodeDict[row[idAttr]] = RowTreeNode(id: row[idAttr], row: row, parentAttr: parentAttr)
        }
        
        // Create empty dummy Node to sit at the top of the tree.
        let rootNode = RowTreeNode(id: -1, row: Row(), parentAttr: parentAttr)
        
        // Use order Attribute from underlying Relation to nest child Nodes under parent elements.
        for node in nodeDict.values {
            let parentNode = nodeDict[node.data[parentAttr]] ?? rootNode
            parentNode.children.insertSorted(node, {$0.data[orderAttr]})
        }
        
        self.relation = relation
        self.idAttr = idAttr
        self.parentAttr = parentAttr
        self.orderAttr = orderAttr
        
        super.init(root: rootNode)
        
        self.removal = relation.addChangeObserver({ changes in
            var treeChanges: [Change] = []
            
            if let adds = changes.added {
                let added: Relation
                if let removes = changes.removed {
                    added = adds.project([self.idAttr]).difference(removes.project([self.idAttr])).join(adds)
                } else {
                    added = adds
                }
                // TODO: Error handling
                let addedRows = added.rows().flatMap{$0.ok}
                treeChanges.appendContentsOf(self.onInsert(addedRows))
            }
            
            if let adds = changes.added, removes = changes.removed {
                let updated = removes.project([self.idAttr]).join(adds)
                let updatedRows = updated.rows().flatMap{$0.ok}
                for row in updatedRows {
                    treeChanges.appendContentsOf(self.onUpdate(row))
                }
            }

            if let removes = changes.removed {
                let removedIDs: Relation
                if let adds = changes.added {
                    removedIDs = removes.project([self.idAttr]).difference(adds.project([self.idAttr]))
                } else {
                    removedIDs = removes.project([self.idAttr])
                }
                
                // Observers should only be notified about the top-most nodes that were deleted.
                // We handle this by looking at the identifiers of the rows/nodes to be deleted,
                // and only deleting the unique (top-most) parents.
                let idsToDelete: [RelationValue] = removedIDs.rows().flatMap{$0.ok?[self.idAttr]}
                for id in idsToDelete {
                    if let node = self.nodeForID(id) {
                        let parentID = node.parentID
                        if parentID == nil || !idsToDelete.contains(parentID!) {
                            treeChanges.appendContentsOf(self.onDelete(id))
                        }
                    }
                }
            }
            
            if treeChanges.count > 0 {
                self.notifyChangeObservers(treeChanges)
            }
        })
    }
    
    deinit {
        removal()
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
    
    private func onInsert(rows: [Row]) -> [Change] {
        
        func insertNode(node: Node, parent: Node) -> Int {
            return parent.children.insertSorted(node, { $0.data[self.orderAttr] })
        }

        // Observers should only be notified about the top-most nodes that were inserted.
        // Additionally, we need to take care to handle the case where a child node
        // insertion change is reported before its parent is inserted into the in-memory
        // tree structure.  We handle this by keeping a dictionary of nodes to be inserted,
        // and then attach them to the in-memory tree structure in a second pass.
        var nodeDict: [RelationValue: Node] = [:]
        for row in rows {
            let rowID = row[idAttr]
            nodeDict[rowID] = RowTreeNode(id: rowID, row: row, parentAttr: parentAttr)
        }
        
        // Wire up nodes to parents that only exist in the node dictionary
        var nodesToDrop: [RelationValue] = []
        for node in nodeDict.values {
            if let parentID = node.parentID {
                if let parent = nodeDict[parentID] {
                    insertNode(node, parent: parent)
                    nodesToDrop.append(node.id)
                }
            }
        }
        nodesToDrop.forEach{ nodeDict.removeValueForKey($0) }
        
        // Now attach the remaining nodes to the in-memory tree structure
        var changes: [Change] = []
        for node in nodeDict.values {
            if let parentID = node.parentID {
                if let parent = nodeForID(parentID) {
                    // Attach the node to the existing parent node
                    let index = insertNode(node, parent: parent)
                    changes.append(.Insert(Path(parent: parent, index: index)))
                } else {
                    // The parent does not exist; doom
                    fatalError("Parent does not already exist in tree structure")
                }
            } else {
                // The node will be attached to the root node
                let index = insertNode(node, parent: root)
                changes.append(.Insert(Path(parent: nil, index: index)))
            }
        }
        
        return changes
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
        relation.delete(idAttr *== id)
        
        // Recursively delete descendant nodes
        // TODO: There are probably more efficient ways to handle this (need some sort of
        // cascading delete), but for now we'll use our tree structure to determine which
        // children need to be deleted
        if let node = node {
            for child in node.children {
                delete(child.id)
            }
        }
    }
    
    private func onDelete(id: RelationValue) -> [Change] {

        func deleteNode(node: Node, inout _ nodes: [Node]) -> Int {
            let index = nodes.indexOf({$0 === node})!
            nodes.removeAtIndex(index)
            return index
        }
        
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
        let dstIndex = dstParent.children.insertSorted(node, { $0.data[self.orderAttr] })

        // Prepare changes
        let newSrcPath = TreePath(parent: optSrcParent, index: srcIndex)
        let newDstPath = TreePath(parent: optDstParent, index: dstIndex)
        return [.Move(src: newSrcPath, dst: newDstPath)]
    }

    private func adjacentNodesForIndex(index: Int, inParent parent: Node, notMatching node: Node) -> (Node?, Node?) {
        // Note: In the case where a node is being reordered within its existing parent, `parent` will
        // still contain that node, but `index` represents the new position assuming it was already removed,
        // so we use the `notMatching` node to avoid choosing that same node again.
        
        func nodeAtIndex(i: Int, alt: Int) -> Node? {
            if let n = parent.children[safe: i] {
                if n !== node {
                    return n
                } else {
                    return parent.children[safe: alt]
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
        
        // TODO: Use a more appropriate data type for storing order
        func orderForNode(node: Node) -> Double {
            return node.data[orderAttr].get()!
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
}
