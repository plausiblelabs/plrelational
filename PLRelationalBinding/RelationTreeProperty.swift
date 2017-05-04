//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

public final class RowTreeNode: RowCollectionElement, TreeNode {
    public var children: [RowTreeNode]
    private let parentAttr: Attribute
    
    init(id: RelationValue, row: Row, parentAttr: Attribute, children: [RowTreeNode] = [], tag: AnyObject?) {
        self.children = children
        self.parentAttr = parentAttr
        super.init(id: id, data: row, tag: tag)
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

private typealias Node = RowTreeNode
private typealias Pos = TreePos<Node>
private typealias Path = TreePath<Node>
private typealias Change = TreeChange<Node>

class RelationTreeProperty: TreeProperty<RowTreeNode>, AsyncRelationChangeCoalescedObserver {

    private let relation: Relation
    private let idAttr: Attribute
    private let parentAttr: Attribute
    private let orderAttr: Attribute
    private let tag: AnyObject?
    
    private var removal: ObserverRemoval?
    private var started = false
    
    init(relation: Relation, idAttr: Attribute, parentAttr: Attribute, orderAttr: Attribute, tag: AnyObject?) {
        precondition(relation.scheme.attributes.isSuperset(of: [idAttr, parentAttr, orderAttr]))

        self.relation = relation
        self.idAttr = idAttr
        self.parentAttr = parentAttr
        self.orderAttr = orderAttr
        self.tag = tag
        
        let rootNode = RowTreeNode(id: -1, row: Row(), parentAttr: self.parentAttr, tag: tag)
        let (signal, notify) = Signal<SignalChange>.pipe()
        super.init(root: rootNode, signal: signal, notify: notify)
    }
    
    deinit {
        removal?()
    }
    
    /*override*/ func start() {
        if started {
            return
        }
        
        removal = relation.addAsyncObserver(self)

        notify.valueWillChange()
        relation.asyncAllRows(
            postprocessor: { rows -> RowTreeNode in
                // Map Rows from underlying Relation to Node values
                var nodeDict = [RelationValue: Node]()
                for row in rows {
                    let rowID = row[self.idAttr]
                    nodeDict[rowID] = RowTreeNode(id: rowID, row: row, parentAttr: self.parentAttr, tag: self.tag)
                }
                
                // Use order Attribute from underlying Relation to nest child Nodes under parent elements
                let rootNode = RowTreeNode(id: -1, row: Row(), parentAttr: self.parentAttr, tag: self.tag)
                for node in nodeDict.values {
                    let parentNode = nodeDict[node.data[self.parentAttr]] ?? rootNode
                    _ = parentNode.children.insertSorted(node, {$0.data[self.orderAttr]})
                }
                
                return rootNode
            },
            completion: { result in
                if let rootNode = result.ok {
                    self.root = rootNode
                    self.notifyObservers(treeChanges: [.initial(rootNode)])
                }
                self.notify.valueDidChange()
            }
        )
        started = true
    }
    
    private func onInsert(rows: [Row], changes: inout [Change]) {
        
        func insertNode(_ node: Node, parent: Node) -> Int {
            return parent.children.insertSorted(node, { $0.data[orderAttr] })
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
    }
    
    private func onDelete(ids: [RelationValue], changes: inout [Change]) {
        // Observers should only be notified about the top-most nodes that were deleted.
        // We handle this by looking at the identifiers of the rows/nodes to be deleted,
        // and only deleting the unique (top-most) parents.
        for id in ids {
            if let node = self.nodeForID(id) {
                let parentID = node.parentID
                if parentID == nil || !ids.contains(parentID!) {
                    if let change = self.onDelete(id) {
                        changes.append(change)
                    }
                }
            }
        }
    }

    private func onDelete(_ id: RelationValue) -> Change? {

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

    private func onUpdate(rows: [Row], changes: inout [Change]) {
        for row in rows {
            if let change = self.onUpdate(row) {
                changes.append(change)
            }
        }
    }
    
    private func onUpdate(_ row: Row) -> Change? {
        let srcID = row[idAttr]
        guard let node = nodeForID(srcID) else {
            return nil
        }
        
        // Capture the old/new parent and order values
        let oldParentID = node.data[parentAttr]
        let newParentID = row[parentAttr]
        let oldOrder = node.data[orderAttr]
        let newOrder = row[orderAttr]
        
        // Update the node's row data
        node.data = node.data.rowWithUpdate(row)
        
        if newParentID != .notFound && newOrder != .notFound && (newParentID != oldParentID || newOrder != oldOrder) {
            // Treat this as a move
            return onMove(node, srcParentID: oldParentID, dstParentID: newParentID)
        } else {
            // Treat this as an update
            return pathForNode(node).map{ .update($0) }
        }
    }
    
    private func onMove(_ node: Node, srcParentID: RelationValue, dstParentID: RelationValue) -> Change {
        func parentForNullableID(_ id: RelationValue) -> Node? {
            if id == .null {
                return nil
            } else {
                return nodeForID(id)
            }
        }
        
        let optSrcParent = parentForNullableID(srcParentID)
        let optDstParent = parentForNullableID(dstParentID)

        let srcParent = optSrcParent ?? root
        let dstParent = optDstParent ?? root

        // Remove the node from its current parent
        let srcIndex = srcParent.children.index(where: { $0 === node })!
        srcParent.children.remove(at: srcIndex)
        
        // Insert the node in its new parent
        let dstIndex = dstParent.children.insertSorted(node, { $0.data[orderAttr] })

        // Prepare changes
        let newSrcPath = TreePath(parent: optSrcParent, index: srcIndex)
        let newDstPath = TreePath(parent: optDstParent, index: dstIndex)
        return .move(src: newSrcPath, dst: newDstPath)
    }

    private func adjacentNodesForIndex(_ index: Int, inParent parent: Node, notMatching node: Node) -> (Node?, Node?) {
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
    
    private func orderWithinParent(_ parent: Node, previous: Node?, next: Node?) -> Double {
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
        return lo + ((hi - lo) / 2.0)
    }
    
    private func orderForPos(_ pos: Pos) -> Double {
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
    
    override func orderForAppend(inParent parent: RelationValue?) -> Double {
        let parentNode: Node
        if let parentID = parent {
            // TODO: Handle case where node isn't present for some reason
            parentNode = nodeForID(parentID)!
        } else {
            parentNode = root
        }
        
        return orderWithinParent(parentNode, previous: nil, next: nil)
    }
    
    override func orderForInsert(after previous: RelationValue) -> (parentID: RelationValue?, order: Double) {
        // TODO: Handle case where node isn't present for some reason
        let previousNode = nodeForID(previous)!
        let parentID = previousNode.parentID
        let parentNode = parentForNode(previousNode) ?? root
        
        let nextNode: Node?
        if let indexOfPrevious = parentNode.children.index(where: {$0.id == previous}) {
            let indexOfNext = indexOfPrevious + 1
            if indexOfNext < parentNode.children.count {
                nextNode = parentNode.children[indexOfNext]
            } else {
                nextNode = nil
            }
        } else {
            nextNode = nil
        }
        
        let order = orderWithinParent(parentNode, previous: previousNode, next: nextNode)
        return (parentID, order)
    }
    
    override func orderForMove(srcPath: TreePath<RowTreeNode>, dstPath: TreePath<RowTreeNode>) -> (nodeID: RelationValue, dstParentID: RelationValue?, order: Double) {
        // Note: dstPath.index is relative to the state of the array *after* the item is removed
        
        let srcParent = srcPath.parent ?? root
        let dstParent = dstPath.parent ?? root

        let srcNode = srcParent.children[srcPath.index]
        let srcID = srcNode.id

        let dstParentID = dstPath.parent?.id

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

        return (nodeID: srcID, dstParentID: dstParentID, order: newOrder)
    }
    
    func relationWillChange(_ relation: Relation) {
        notify.valueWillChange()
    }
    
    func relationDidChange(_ relation: Relation, result: Result<NegativeSet<Row>, RelationError>) {
        switch result {
        case .Ok(let rows):
            // Compute tree changes
            let parts = partsOf(rows, idAttr: idAttr)
            if !parts.isEmpty {
                var treeChanges: [Change] = []
                self.onInsert(rows: parts.addedRows, changes: &treeChanges)
                self.onUpdate(rows: parts.updatedRows, changes: &treeChanges)
                self.onDelete(ids: parts.deletedIDs, changes: &treeChanges)
                if treeChanges.count > 0 {
                    self.notifyObservers(treeChanges: treeChanges)
                }
            }
            self.notify.valueDidChange()
            
        case .Err(let err):
            // TODO: actual handling
            fatalError("Got error for relation change: \(err)")
        }
    }
}

extension Relation {
    /// Returns a TreeProperty that gets its data from this relation.
    public func treeProperty(idAttr: Attribute, parentAttr: Attribute, orderAttr: Attribute, tag: AnyObject? = nil) -> TreeProperty<RowTreeNode> {
        return RelationTreeProperty(relation: self, idAttr: idAttr, parentAttr: parentAttr, orderAttr: orderAttr, tag: tag)
    }
}
