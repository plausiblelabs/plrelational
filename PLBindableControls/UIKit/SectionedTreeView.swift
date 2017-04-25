//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelational
import PLRelationalBinding

public struct SectionedTreePath {
    public let parent: AnyObject?
    public let index: Int
    
    public init(parent: AnyObject?, index: Int) {
        self.parent = parent
        self.index = index
    }
}

extension SectionedTreePath: Equatable {}
public func ==(a: SectionedTreePath, b: SectionedTreePath) -> Bool {
    return a.parent === b.parent && a.index == b.index
}

public struct SectionedTreeSectionID {
    public let rawID: Int64
    
    public init(rawID: Int64) {
        self.rawID = rawID
    }
}

extension SectionedTreeSectionID: Equatable {}
public func ==(a: SectionedTreeSectionID, b: SectionedTreeSectionID) -> Bool {
    return a.rawID == b.rawID
}

public enum SectionedTreeChange { case
    initial(sectionID: SectionedTreeSectionID, path: SectionedTreePath?),
    insert(SectionedTreePath),
    delete(SectionedTreePath),
    move(src: SectionedTreePath, dst: SectionedTreePath)
}

extension SectionedTreeChange: Equatable {}
public func ==(a: SectionedTreeChange, b: SectionedTreeChange) -> Bool {
    switch (a, b) {
    case let (.initial(aid, apath), .initial(bid, bpath)): return aid == bid && apath == bpath
    case let (.insert(a), .insert(b)): return a == b
    case let (.delete(a), .delete(b)): return a == b
    case let (.move(asrc, adst), .move(bsrc, bdst)): return asrc == bsrc && adst == bdst
    default: return false
    }
}

public protocol SectionedTreeViewModelDelegate: class {
    func sectionedTreeViewModelTreeChanged(_ changes: [SectionedTreeChange])
}

public protocol SectionedTreeViewModel: class {
    associatedtype Path: Hashable
    
    weak var delegate: SectionedTreeViewModelDelegate? { get set }
    var selection: AsyncReadWriteProperty<Set<Path>> { get }
    var selectionExclusiveMode: Bool { get set }
    
    func start()
    
    func indexPathForItemPath(_ itemPath: Path) -> IndexPath?

    /// Called when a row at the given path has been selected.  The view will update the
    /// `selection` property using the value returned by this function.  This gives the model
    /// an opportunity to handle momentary-style cell selection.  For example, the model can
    /// initiate some action when a cell is selected then return `nil` to prevent `selection`
    /// being set to that item's path.
    func itemPathForSelectedRow(_ indexPath: IndexPath) -> Path?
    
    func sectionCount() -> Int
    func rowCount(forSection section: Int) -> Int
    
    func title(forSection section: Int) -> String?
    
    func cellIndentationLevel(_ indexPath: IndexPath) -> Int
    func cellIdentifier(_ indexPath: IndexPath) -> String
    func cellText(_ indexPath: IndexPath) -> LabelText
}

public protocol SectionedTreeViewDelegate: class {
    func willDisplayCell(_ cell: UITableViewCell, indexPath: IndexPath)
}

open class SectionedTreeView<M: SectionedTreeViewModel> {
    
    private let impl: Impl<M>
    private weak var delegate: SectionedTreeViewDelegate?
    
    public var viewDelegate: SectionedTreeViewDelegate? {
        get { return impl.viewDelegate }
        set { impl.viewDelegate = newValue }
    }

    public init(model: M, tableView: UITableView) {
        self.impl = Impl(model: model, tableView: tableView)
    }
}

/// Private implementation for SectionedTreeView.
fileprivate class Impl<M: SectionedTreeViewModel>: NSObject, UITableViewDataSource, UITableViewDelegate, SectionedTreeViewModelDelegate {
    
    private let model: M
    private let tableView: UITableView
    fileprivate weak var viewDelegate: SectionedTreeViewDelegate?
    
    private lazy var selection: MutableValueProperty<Set<M.Path>> = mutableValueProperty(Set(), { selectedPaths, _ in
        self.selectItems(selectedPaths)
    })
    
    private var selfInitiatedSelectionChange = false
    
    init(model: M, tableView: UITableView) {
        self.model = model
        self.tableView = tableView
        
        super.init()
        
        self.model.delegate = self
        self.selection <~> model.selection
        
        tableView.delegate = self
        tableView.dataSource = self
        
        model.start()
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return model.sectionCount()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return model.rowCount(forSection: section)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // TODO: Rework this so that the model doesn't need to do two separate lookups (first identifier then cell text
        // and eventually other things)
        let identifier = model.cellIdentifier(indexPath)
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        
        let text = model.cellText(indexPath)
        cell.textLabel?.bind(text)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return model.title(forSection: section)
    }

    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        return model.cellIndentationLevel(indexPath)
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        viewDelegate?.willDisplayCell(cell, indexPath: indexPath)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if selfInitiatedSelectionChange {
            return
        }
        
        let paths = selectedItemPaths()
        selfInitiatedSelectionChange = true
        selection.change(paths, transient: false)
        selfInitiatedSelectionChange = false
    }
    
    /// Returns the set of item paths corresponding to the view's current selection state.
    /// Note that the model may return nil for one or more index paths, indicating that it
    /// handled the selection event but does not want that path included when changing
    /// the state of the `selection` property.
    private func selectedItemPaths() -> Set<M.Path> {
        var itemPaths: [M.Path] = []
        if let indexPaths = self.tableView.indexPathsForSelectedRows {
            for indexPath in indexPaths {
                if let itemPath = self.model.itemPathForSelectedRow(indexPath) {
                    itemPaths.append(itemPath)
                }
            }
        }
        return Set(itemPaths)
    }
    
    /// Selects the rows corresponding to the given set of item paths.
    private func selectItems(_ itemPaths: Set<M.Path>) {
        // XXX: Ignore external selection changes made while in exclusive mode
        if model.selectionExclusiveMode {
            return
        }

        var indexPaths: [IndexPath] = []
        for itemPath in itemPaths {
            if let indexPath = self.model.indexPathForItemPath(itemPath) {
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
    
    // MARK: - SectionedTreeViewModelDelegate protocol
    
    func sectionedTreeViewModelTreeChanged(_ changes: [SectionedTreeChange]) {
        // TODO
        Swift.print("TREE CHANGED: \(changes)")
        self.tableView.reloadData()
    }
}