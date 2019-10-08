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
    
    var delegate: SectionedTreeViewModelDelegate? { get set }
    var selection: AsyncReadableProperty<Path?> { get }
    var selectionExclusiveMode: Bool { get set }
    
    func start()
    
    func indexPathForItemPath(_ itemPath: Path) -> IndexPath?

    func sectionCount() -> Int
    func rowCount(forSection section: Int) -> Int
    
    func title(forSection section: Int) -> String?
    
    func cellIndentationLevel(_ indexPath: IndexPath) -> Int
    func cellIdentifier(_ indexPath: IndexPath) -> String
    func cellText(_ indexPath: IndexPath) -> LabelText
    func cellIsGroupStyle(_ indexPath: IndexPath) -> Bool

    /// Called when a row at the given path has been selected.  If the model returns `true`,
    /// the row will remain selected in the view, otherwise it will be deselected (i.e., a
    /// momentary selection).
    func handleRowSelected(at indexPath: IndexPath) -> Bool
}

public protocol SectionedTreeViewDelegate: class {
    func willDisplayCell(_ cell: UITableViewCell, indexPath: IndexPath)
}

open class SectionedTreeView<M: SectionedTreeViewModel> {
    
    private let impl: Impl<M>
    
    public var viewDelegate: SectionedTreeViewDelegate? {
        get { return impl.viewDelegate }
        set { impl.viewDelegate = newValue }
    }

    public init(model: M, tableView: UITableView) {
        self.impl = Impl(model: model, tableView: tableView)
    }
    
    /// XXX: Apparently UITableView will not respond to selectRow() before the view has appeared, so this must be called from the
    /// parent UIViewController's viewWillAppear() in order to get the current selection to stick.
    public func refreshSelection() {
        impl.refreshSelection()
    }
}

/// Private implementation for SectionedTreeView.
fileprivate class Impl<M: SectionedTreeViewModel>: NSObject, UITableViewDataSource, UITableViewDelegate, SectionedTreeViewModelDelegate {
    
    private let model: M
    private let tableView: UITableView
    fileprivate weak var viewDelegate: SectionedTreeViewDelegate?
    
    private lazy var selection: MutableValueProperty<M.Path?> = mutableValueProperty(nil, { selectedPath, _ in
        self.selectItem(selectedPath, animated: true, scroll: false)
    })
    
    init(model: M, tableView: UITableView) {
        self.model = model
        self.tableView = tableView
        
        super.init()

        tableView.delegate = self
        tableView.dataSource = self
        
        model.delegate = self
        model.start()
        
        tableView.reloadData()
        
        self.selection <~ model.selection
    }
    
    func refreshSelection() {
        selectItem(self.selection.value, animated: false, scroll: true)
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

        // TODO: Labels in UITableViewCell do not automatically refresh (must be triggered by reloading the whole cell), so
        // we probably should make cellText return a constant string value rather than a property
        let text = model.cellText(indexPath)
        cell.textLabel?.set(text)

        // TODO: For now we disable selection for group-style items, but eventually we might want to allow expand/collapse
        cell.isUserInteractionEnabled = !model.cellIsGroupStyle(indexPath)
        
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
    
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if model.handleRowSelected(at: indexPath) {
            return indexPath
        } else {
            return nil
        }
    }
    
    /// Selects the row corresponding to the given item path.
    private func selectItem(_ itemPath: M.Path?, animated: Bool, scroll: Bool) {
        // XXX: Ignore external selection changes made while in exclusive mode
        if model.selectionExclusiveMode {
            return
        }

        let indexPath = itemPath.flatMap(self.model.indexPathForItemPath)
        self.tableView.selectRow(at: indexPath, animated: animated, scrollPosition: scroll ? .middle : .none)
    }
    
    // MARK: - SectionedTreeViewModelDelegate protocol
    
    func sectionedTreeViewModelTreeChanged(_ changes: [SectionedTreeChange]) {
        Swift.print("TREE CHANGED: \(changes)")
        
        // TODO: For now we just reload the whole thing
        self.tableView.reloadData()

        // XXX: Set the selection in case the selection property was updated before the tree changes came in
        refreshSelection()

//        self.tableView.beginUpdates()
//        
//        for change in changes {
//            switch change {
//            case .initial:
//                // TODO: Reload just this section
//                break
//            case .insert:
//                // TODO
//                if isSection {
//                    self.tableView.insertSections(sections, with: .automatic)
//                } else {
//                    self.tableView.insertRows(at: indexPaths, with: .automatic)
//                }
//            case .delete:
//                // TODO
//                if isSection {
//                    self.tableView.deleteSections(sections, with: .automatic)
//                } else {
//                    self.tableView.deleteRows(at: indexPaths, with: .automatic)
//                }
//            case .move:
//                // TODO
//                if isSection {
//                    self.tableView.moveSection(srcIndex, toSection: dstIndex)
//                } else {
//                    self.tableView.moveRow(at: srcPath, to: dstPath)
//                }
//            }
//        }
//        
//        self.tableView.endUpdates()
    }
}
