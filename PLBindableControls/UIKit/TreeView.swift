//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelationalBinding

public struct TreeViewModel<N: TreeNode> {
    public let data: TreeProperty<N>
    public let allowsChildren: (N.Data) -> Bool
    public let isSection: (N.Data) -> Bool
    // Note: dstPath.index is relative to the state of the array *before* the item is removed.
    public let move: ((_ srcPath: TreePath<N>, _ dstPath: TreePath<N>) -> Void)?
    //public let selection: AsyncReadWriteProperty<Set<N.ID>>
    public let cellIdentifier: (N.Data) -> String
    public let cellText: (N.Data) -> LabelText
    
    public init(
        data: TreeProperty<N>,
        allowsChildren: @escaping (N.Data) -> Bool,
        isSection: @escaping (N.Data) -> Bool,
        move: ((_ srcPath: TreePath<N>, _ dstPath: TreePath<N>) -> Void)?,
        //selection: AsyncReadWriteProperty<Set<N.ID>>,
        cellIdentifier: @escaping (N.Data) -> String,
        cellText: @escaping (N.Data) -> LabelText)
    {
        self.data = data
        self.isSection = isSection
        self.allowsChildren = allowsChildren
        self.move = move
        //self.selection = selection
        self.cellIdentifier = cellIdentifier
        self.cellText = cellText
    }
}

open class TreeView<N: TreeNode>: NSObject, UITableViewDataSource, UITableViewDelegate {
    
    private let model: TreeViewModel<N>
    private let tableView: UITableView
    
    private lazy var selection: MutableValueProperty<Set<N.ID>> = mutableValueProperty(Set(), { selectedIDs, _ in
        self.selectItems(selectedIDs)
    })
    
    private var treeObserverRemoval: ObserverRemoval?
    private var selfInitiatedSelectionChange = false
    
    public init(model: TreeViewModel<N>, tableView: UITableView) {
        self.model = model
        self.tableView = tableView
        
        super.init()
        
        // TODO: Handle will/didChange
        treeObserverRemoval = model.data.signal.observe(SignalObserver(
            valueWillChange: {},
            valueChanging: { [weak self] changes, _ in self?.treeChanged(changes) },
            valueDidChange: {}
        ))
        //_ = selection <~> model.selection
        
        tableView.delegate = self
        tableView.dataSource = self
        
        // Load the initial data
        model.data.start()
    }
    
    deinit {
        treeObserverRemoval?()
    }

    /// Returns the node that corresponds to the given index path.
    private func node(for indexPath: IndexPath) -> N {
        // TODO: This is way inefficient; need to cache index -> node mappings
        let rowToFind = indexPath.row
        var index = 0
        
        func visit(_ node: N) -> N? {
            if index == rowToFind {
                return node
            }
            index += 1
            for child in node.children {
                if let found = visit(child) {
                    return found
                }
            }
            return nil
        }
        
        for node in model.data.root.children {
            if let found = visit(node) {
                return found
            }
        }
        
        fatalError("Invalid index path")
    }
    
    private func indexPath(for nodeID: N.ID) -> IndexPath? {
        // TODO: This is way inefficient; need to cache node -> index mappings
        var row = 0
        
        func visit(_ node: N) -> IndexPath? {
            if node.id == nodeID {
                return IndexPath(row: row, section: 0)
            }
            row += 1
            for child in node.children {
                if let found = visit(child) {
                    return found
                }
            }
            return nil
        }
        
        for node in model.data.root.children {
            if let found = visit(node) {
                return found
            }
        }

        return nil
    }
    
    // MARK: - UITableViewDataSource

    open func numberOfSections(in tableView: UITableView) -> Int {
        // TODO: Divide into sections if isSection() returns true for any top-level item
        return 1
    }
    
    open func tableView(_ tableView: UITableView, numberOfRowsInSection: Int) -> Int {
        // TODO: Coordinate with numberOfSections; for now we just get the total number of nodes in the tree
        // TODO: Cache this somewhere
        var rowCount = 0
        
        func visit(_ node: N) {
            rowCount += 1
            
            for child in node.children {
                visit(child)
            }
        }
        
        for node in model.data.root.children {
            visit(node)
        }
        
        return rowCount
    }
    
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let node = self.node(for: indexPath)
        let identifier = model.cellIdentifier(node.data)
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        
        let text = model.cellText(node.data)
        cell.textLabel?.bind(text)
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    open func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        // TODO: This is way inefficient; need to cache index -> level mappings
        let rowToFind = indexPath.row
        var index = 0
        var level = 0
        
        func visit(_ node: N) -> Int? {
            if index == rowToFind {
                return level
            }
            index += 1
            level += 1
            for child in node.children {
                if let found = visit(child) {
                    return found
                }
            }
            level -= 1
            return nil
        }
        
        for node in model.data.root.children {
            if let found = visit(node) {
                return found
            }
        }
        
        return 0
    }
    
    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        Swift.print("SELECTED: \(indexPath.row)")
        if selfInitiatedSelectionChange {
            return
        }
        
        selfInitiatedSelectionChange = true
        selection.change(selectedItemIDs(), transient: false)
        selfInitiatedSelectionChange = false
    }
    
    /// Returns the set of node IDs corresponding to the view's current selection state.
    private func selectedItemIDs() -> Set<N.ID> {
        var itemIDs: [N.ID] = []
        if let indexPaths = self.tableView.indexPathsForSelectedRows {
            for indexPath in indexPaths {
                let node = self.node(for: indexPath)
                itemIDs.append(node.id)
            }
        }
        return Set(itemIDs)
    }
    
    /// Selects the rows corresponding to the given set of node IDs.
    private func selectItems(_ ids: Set<N.ID>) {
        var indexPaths: [IndexPath] = []
        for id in ids {
            if let indexPath = self.indexPath(for: id) {
                indexPaths.append(indexPath)
            }
        }
        // TODO: The selectRow() spec says calling it does not cause the delegate to receive didSelect events,
        // so probably the selfInitiatedSelectionChange guards are not needed for UIKit
        selfInitiatedSelectionChange = true
        // TODO: Is this a valid way to handle multiple selection?
        self.tableView.selectRow(at: nil, animated: false, scrollPosition: .none)
        for indexPath in indexPaths {
            self.tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        }
        selfInitiatedSelectionChange = false
    }
    
    // MARK: - Property observers
    
    private func treeChanged(_ changes: [TreeChange<N>]) {
        // TODO
        Swift.print("TREE CHANGED: \(changes)")
        self.tableView.reloadData()
        
//        let animation: NSTableViewAnimationOptions = animateChanges ? [.effectFade] : []
//        
//        // Get the current set of IDs from the `selection` property and then use those to restore
//        // the selection state after the changes are processed; this ensures that we select items
//        // that were both inserted and marked for selection in a single (relational) transaction
//        let itemsToSelect = selection.value
//        
//        outlineView.beginUpdates()
//        
//        // TODO: Use a Set instead
//        var itemsToReload: [N] = []
//        var itemsToExpand: [N] = []
//        
//        for change in changes {
//            switch change {
//            case .initial(_):
//                outlineView.reloadData()
//                
//            case let .insert(path):
//                let rows = IndexSet(integer: path.index)
//                outlineView.insertItems(at: rows, inParent: path.parent, withAnimation: animation)
//                if autoExpand, let node = model.data.nodeAtPath(path) {
//                    itemsToExpand.append(node)
//                }
//                
//            case let .delete(path):
//                let rows = IndexSet(integer: path.index)
//                outlineView.removeItems(at: rows, inParent: path.parent, withAnimation: animation)
//                
//            case .update:
//                // TODO: For now we will ignore updates and assume that the cell contents will
//                // be updated individually in response to the change.  We should make this
//                // configurable to allow for optionally calling reloadItem() to refresh the
//                // entire cell on any non-trivial update.
//                break
//                
//            case let .move(srcPath, dstPath):
//                outlineView.moveItem(at: srcPath.index, inParent: srcPath.parent, to: dstPath.index, inParent: dstPath.parent)
//                // XXX: NSOutlineView doesn't appear to hide/show the disclosure triangle in the case where
//                // the parent's emptiness is changing, so we have to do that manually
//                if let srcParent = srcPath.parent {
//                    if srcParent.children.count == 0 {
//                        itemsToReload.append(srcParent)
//                    }
//                }
//                if let dstParent = dstPath.parent {
//                    if dstParent.children.count == 1 {
//                        itemsToReload.append(dstParent)
//                        itemsToExpand.append(dstParent)
//                    }
//                }
//            }
//        }
//        
//        // Note: we need to wait until all insert/remove calls are processed above before
//        // reloadItem() and/or expandItem() are called, otherwise NSOutlineView will get confused
//        itemsToReload.forEach(outlineView.reloadItem)
//        itemsToExpand.forEach(outlineView.expandItem)
//        
//        selectItems(itemsToSelect)
//        
//        // TODO: We put a guard here as well so that no further selection changes are made when the
//        // updates are committed
//        selfInitiatedSelectionChange = true
//        outlineView.endUpdates()
//        selfInitiatedSelectionChange = false
    }
}
