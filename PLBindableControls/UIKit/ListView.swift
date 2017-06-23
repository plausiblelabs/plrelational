//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelationalBinding

public protocol ListViewModel: class {
    associatedtype Element: ArrayElement

    var data: ArrayProperty<Element> { get }
    var selection: AsyncReadableProperty<Element.ID?> { get }
    
    func start()
    
    func cellIdentifier(_ data: Element.Data) -> String
    func cellText(_ data: Element.Data) -> LabelText
    
    /// Called when a row with the given data has been selected.  If the model returns `true`,
    /// the row will remain selected in the view, otherwise it will be deselected (i.e., a
    /// momentary selection).
    func rowSelected(_ data: Element.Data) -> Bool
}

public protocol ListViewDelegate: class {
    func willDisplayCell(_ cell: UITableViewCell, indexPath: IndexPath)
}

open class ListView<M: ListViewModel>: NSObject, UITableViewDataSource, UITableViewDelegate {
    
    public let model: M
    private let tableView: UITableView
    
    public weak var delegate: ListViewDelegate?

    private lazy var selection: MutableValueProperty<M.Element.ID?> = mutableValueProperty(nil, { selectedID, _ in
        self.selectItem(selectedID, animated: true, scroll: false)
    })
    
    private var arrayObserverRemoval: ObserverRemoval?
    
    public init(model: M, tableView: UITableView) {
        self.model = model
        self.tableView = tableView
        
        super.init()
        
        self.selection <~ model.selection

        // TODO: Handle Begin/EndPossibleAsync events?
        arrayObserverRemoval = model.data.signal.observeValueChanging{ [weak self] changes, _ in
            self?.arrayChanged(changes)
        }
        
        tableView.delegate = self
        tableView.dataSource = self
        
        // Load the initial data
        model.data.start()
    }
    
    deinit {
        arrayObserverRemoval?()
    }
    
    /// XXX: Apparently UITableView will not respond to selectRow() before the view has appeared, so this must be called from the
    /// parent UIViewController's viewWillAppear() in order to get the current selection to stick.
    public func refreshSelection() {
        selectItem(self.selection.value, animated: false, scroll: true)
    }

    // MARK: - UITableViewDataSource
    
    open func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    open func tableView(_ tableView: UITableView, numberOfRowsInSection: Int) -> Int {
        return model.data.elements.count
    }
    
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let element = self.model.data.elements[indexPath.row]
        let identifier = model.cellIdentifier(element.data)
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)

        let text = model.cellText(element.data)
        cell.textLabel?.bind(text)

        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    open func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        delegate?.willDisplayCell(cell, indexPath: indexPath)
    }

    open func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        let element = self.model.data.elements[indexPath.row]
        if self.model.rowSelected(element.data) {
            return indexPath
        } else {
            return nil
        }
    }
    
    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    }
    
    /// Selects the row corresponding to the given element ID.
    private func selectItem(_ id: M.Element.ID?, animated: Bool, scroll: Bool) {
        let rowIndex = id.flatMap(self.model.data.indexForID)
        let indexPath = rowIndex.map{ IndexPath(row: $0, section: 0) }
        self.tableView.selectRow(at: indexPath, animated: animated, scrollPosition: scroll ? .middle : .none)
    }
    
    // MARK: - Property observers
    
    private func arrayChanged(_ changes: [ArrayChange<M.Element>]) {
        Swift.print("ARRAY CHANGED: \(changes)")
        
        // XXX: Unlike NSTableView, UITableView does not seem to like reloadData inside
        // the begin/endUpdates section.  We will do the initial reloadData outside
        // a begin/end and then subsequent modifications will be done inside begin/end.
        var didBegin = false
        
        func beginUpdates() {
            if !didBegin {
                tableView.beginUpdates()
                didBegin = true
            }
        }
        
        func endUpdates() {
            if didBegin {
                tableView.endUpdates()
                didBegin = false
            }
        }
        
        for change in changes {
            switch change {
            case .initial(_):
                tableView.reloadData()
                
            case let .insert(index):
                let indexPath = IndexPath(row: index, section: 0)
                beginUpdates()
                tableView.insertRows(at: [indexPath], with: .automatic)
                
            case let .delete(index):
                let indexPath = IndexPath(row: index, section: 0)
                beginUpdates()
                tableView.deleteRows(at: [indexPath], with: .automatic)
                
            case let .update(index):
                let indexPath = IndexPath(row: index, section: 0)
                beginUpdates()
                tableView.reloadRows(at: [indexPath], with: .automatic)
                
            case let .move(srcIndex, dstIndex):
                let srcIndexPath = IndexPath(row: srcIndex, section: 0)
                let dstIndexPath = IndexPath(row: dstIndex, section: 0)
                beginUpdates()
                tableView.moveRow(at: srcIndexPath, to: dstIndexPath)
            }
        }

        endUpdates()
        
        // XXX: Set the selection in case the selection property was updated before the array changes came in
        refreshSelection()
    }
}
