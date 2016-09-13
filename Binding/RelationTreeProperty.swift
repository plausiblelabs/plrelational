//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

public final class RowTreeNode: TreeNode {
    public typealias ID = RelationValue
    public typealias Data = Row
    
    public let id: RelationValue
    public var data: Row
    public var children: [RowTreeNode]
    fileprivate let parentAttr: Attribute
    public let tag: AnyObject?
    
    init(id: RelationValue, row: Row, parentAttr: Attribute, children: [RowTreeNode] = [], tag: AnyObject?) {
        self.id = id
        self.data = row
        self.children = children
        self.parentAttr = parentAttr
        self.tag = tag
    }
    
    public var parentID: RelationValue? {
        let parent = data[parentAttr]
        if parent != .null {
            return parent
        } else {
            return nil
        }
    }
}

class RelationTreeProperty: TreeProperty<RowTreeNode> {

    fileprivate let relation: Relation
    fileprivate let tag: AnyObject?
    fileprivate let idAttr: Attribute
    fileprivate let parentAttr: Attribute
    fileprivate let orderAttr: Attribute
    
    fileprivate var removal: ObserverRemoval!
    
    init(relation: Relation, tag: AnyObject?, idAttr: Attribute, parentAttr: Attribute, orderAttr: Attribute) {
        precondition(relation.scheme.attributes.isSuperset(of: [idAttr, parentAttr, orderAttr]))

        // Map Rows from underlying Relation to Node values.
        var nodeDict = [RelationValue: Node]()
        for row in relation.rows().map({$0.ok!}) {
            nodeDict[row[idAttr]] = RowTreeNode(id: row[idAttr], row: row, parentAttr: parentAttr, tag: tag)
        }
        
        // Create empty dummy Node to sit at the top of the tree.
        let rootNode = RowTreeNode(id: -1, row: Row(), parentAttr: parentAttr, tag: tag)
        
        // Use order Attribute from underlying Relation to nest child Nodes under parent elements.
        for node in nodeDict.values {
            let parentNode = nodeDict[node.data[parentAttr]] ?? rootNode
            _ = parentNode.children.insertSorted(node, {$0.data[orderAttr]})
        }
        
        self.relation = relation
        self.tag = tag
        self.idAttr = idAttr
        self.parentAttr = parentAttr
        self.orderAttr = orderAttr
        
        super.init(root: rootNode)
        
        self.removal = relation.addChangeObserver({ [weak self] changes in
            self?.handleRelationChanges(changes)
        })
    }
    
    deinit {
        removal()
    }
    
    fileprivate func handleRelationChanges(_ relationChanges: RelationChange) {
        let parts = relationChanges.parts(self.idAttr)
        
        var treeChanges: [Change] = []
        treeChanges.append(contentsOf: self.onInsert(parts.addedRows))
        treeChanges.append(contentsOf: self.onUpdate(parts.updatedRows))
        treeChanges.append(contentsOf: self.onDelete(parts.deletedIDs))
        
        if treeChanges.count > 0 {
            self.notifyChangeObservers(treeChanges)
        }
    }
    
    override func insert(_ row: Row, pos: Pos) {
        // TODO: Provide insert/delete/move as extension defined where R: MutableRelation
        guard var relation = relation as? MutableRelation else {
            fatalError("insert() is only supported when the underlying relation is mutable")
        }
        
        var mutableRow = row
        computeOrderForInsert(&mutableRow, pos: pos)
        _ = relation.add(mutableRow)
    }
    
    override func computeOrderForInsert(_ row: inout Row, pos: Pos) {
        let parentIDValue = pos.parentID ?? .null
        let order: RelationValue = orderForPos(pos)
        
        row[parentAttr] = parentIDValue
        row[orderAttr] = order
    }

    fileprivate func onInsert(_ rows: [Row]) -> [Change] {
        
        func insertNode(_ node: Node, parent: Node) -> Int {
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
            nodeDict[rowID] = RowTreeNode(id: rowID, row: row, parentAttr: parentAttr, tag: tag)
        }
        
        // Wire up nodes to parents that only exist in the node dictionary
        var nodesToDrop: [RelationValue] = []
        for node in nodeDict.values {
            if let parentID = node.parentID {
                if let parent = nodeDict[parentID] {
                    _ = insertNode(node, parent: parent)
                    nodesToDrop.append(node.id)
                }
            }
        }
        nodesToDrop.forEach{ nodeDict.removeValue(forKey: $0) }
        
        // Now attach the remaining nodes to the in-memory tree structure
        var changes: [Change] = []
        for node in nodeDict.values {
            if let parentID = node.parentID {
                if let parent = nodeForID(parentID) {
                    // Attach the node to the existing parent node
                    let index = insertNode(node, parent: parent)
                    changes.append(.insert(Path(parent: parent, index: index)))
                } else {
                    // The parent does not exist; doom
                    fatalError("Parent does not already exist in tree structure")
                }
            } else {
                // The node will be attached to the root node
                let index = insertNode(node, parent: root)
                changes.append(.insert(Path(parent: nil, index: index)))
            }
        }
        
        return changes
    }
    
    override func delete(_ id: RelationValue) {
        guard var relation = relation as? MutableRelation else {
            fatalError("delete() is only supported when the underlying relation is mutable")
        }

        // Grab the node before we delete from the relation; otherwise if we are being called
        // outside of a transaction, the node may be deleted by onDelete() just after we call
        // relation.delete() below
        let node = nodeForID(id)
        
        // Delete from the relation
        _ = relation.delete(idAttr *== id)
        
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

    fileprivate func onDelete(_ idsToDelete: [RelationValue]) -> [Change] {
        // Observers should only be notified about the top-most nodes that were deleted.
        // We handle this by looking at the identifiers of the rows/nodes to be deleted,
        // and only deleting the unique (top-most) parents.
        var changes: [Change] = []
        for id in idsToDelete {
            if let node = self.nodeForID(id) {
                let parentID = node.parentID
                if parentID == nil || !idsToDelete.contains(parentID!) {
                    if let change = self.onDelete(id) {
                        changes.append(change)
                    }
                }
            }
        }
        return changes
    }

    fileprivate func onDelete(_ id: RelationValue) -> Change? {

        func deleteNode(_ node: Node, _ nodes: inout [Node]) -> Int {
            let index = nodes.index(where: {$0 === node})!
            nodes.remove(at: index)
            return index
        }
        
        return nodeForID(id).map{ node in
            let parent: Node?
            let index: Int
            let parentID = node.data[parentAttr]
            if parentID != .null {
                let parentNode = nodeForID(parentID)!
                parent = parentNode
                index = deleteNode(node, &parentNode.children)
            } else {
                parent = nil
                index = deleteNode(node, &root.children)
            }
            
            let path = TreePath(parent: parent, index: index)
            return .delete(path)
        }
    }

    /// Note: dstPath.index is relative to the state of the array *after* the item is removed.
    override func move(srcPath: Path, dstPath: Path) {
        let srcParent = srcPath.parent ?? root
        let dstParent = dstPath.parent ?? root

        let srcNode = srcParent.children[srcPath.index]
        let srcID = srcNode.id
        
        let dstParentID: RelationValue
        if let dstParent = dstPath.parent {
            dstParentID = dstParent.id
        } else {
            dstParentID = .null
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
        _ = mutableRelation.update(idAttr *== srcID, newValues: [
            parentAttr: dstParentID,
            orderAttr: newOrder
        ])
    }

    fileprivate func onUpdate(_ rows: [Row]) -> [Change] {
        var changes: [Change] = []
        for row in rows {
            if let change = self.onUpdate(row) {
                changes.append(change)
            }
        }
        return changes
    }
    
    fileprivate func onUpdate(_ row: Row) -> Change? {
        let newParentID = row[parentAttr]
        let newOrder = row[orderAttr]
        if newParentID == .notFound || newOrder == .notFound {
            // TODO: We should be able to perform the move if only one of parent/order were updated
            return nil
        }

        let srcID = row[idAttr]
        let srcNode = nodeForID(srcID)!
        return onMove(srcNode, dstParentID: newParentID, dstOrder: newOrder)
    }
    
    fileprivate func onMove(_ node: Node, dstParentID: RelationValue, dstOrder: RelationValue) -> Change {
        let optSrcParent = parentForNode(node)
        let optDstParent: Node?
        if dstParentID == .null {
            optDstParent = nil
        } else {
            optDstParent = nodeForID(dstParentID)!
        }

        let srcParent = optSrcParent ?? root
        let dstParent = optDstParent ?? root

        // Remove the node from its current parent
        let srcIndex = srcParent.children.index(where: { $0 === node })!
        srcParent.children.remove(at: srcIndex)
        
        // Update the values in the node's row
        node.data[parentAttr] = dstParentID
        node.data[orderAttr] = dstOrder

        // Insert the node in its new parent
        let dstIndex = dstParent.children.insertSorted(node, { $0.data[self.orderAttr] })

        // Prepare changes
        let newSrcPath = TreePath(parent: optSrcParent, index: srcIndex)
        let newDstPath = TreePath(parent: optDstParent, index: dstIndex)
        return .move(src: newSrcPath, dst: newDstPath)
    }

    fileprivate func adjacentNodesForIndex(_ index: Int, inParent parent: Node, notMatching node: Node) -> (Node?, Node?) {
        // Note: In the case where a node is being reordered within its existing parent, `parent` will
        // still contain that node, but `index` represents the new position assuming it was already removed,
        // so we use the `notMatching` node to avoid choosing that same node again.
        
        func nodeAtIndex(_ i: Int, alt: Int) -> Node? {
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
    
    fileprivate func orderWithinParent(_ parent: Node, previous: Node?, next: Node?) -> RelationValue {
        let prev: Node?
        if previous == nil && next == nil {
            // Add after the last child
            prev = parent.children.last
        } else {
            // Insert after previous child
            prev = previous
        }
        
        // TODO: Use a more appropriate data type for storing order
        func orderForNode(_ node: Node) -> Double {
            return node.data[orderAttr].get()!
        }

        let lo: Double = prev.map(orderForNode) ?? 1.0
        let hi: Double = next.map(orderForNode) ?? 9.0
        return RelationValue(lo + ((hi - lo) / 2.0))
    }
    
    fileprivate func orderForPos(_ pos: Pos) -> RelationValue {
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

extension Relation {
    /// Returns a TreeProperty that gets its data from this relation.
    public func treeProperty(tag: AnyObject? = nil, idAttr: Attribute = "id", parentAttr: Attribute = "parent", orderAttr: Attribute = "order") -> TreeProperty<RowTreeNode> {
        return RelationTreeProperty(relation: self, tag: tag, idAttr: idAttr, parentAttr: parentAttr, orderAttr: orderAttr)
    }
}
