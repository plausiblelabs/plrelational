//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelationalBinding

public struct ListViewModel<E: ArrayElement> {
    public let data: ArrayProperty<E>
    // Note: dstIndex is relative to the state of the array *before* the item is removed.
    public let move: ((_ srcPath: Int, _ dstPath: Int) -> Void)?
    public let cellIdentifier: (E.Data) -> String
    public let cellText: (E.Data) -> LabelText
    
    public init(
        data: ArrayProperty<E>,
        move: ((_ srcIndex: Int, _ dstIndex: Int) -> Void)?,
        cellIdentifier: @escaping (E.Data) -> String,
        cellText: @escaping (E.Data) -> LabelText)
    {
        self.data = data
        self.move = move
        self.cellIdentifier = cellIdentifier
        self.cellText = cellText
    }
}

open class ListView<E: ArrayElement>: NSObject, UITableViewDataSource, UITableViewDelegate {
    
    private let model: ListViewModel<E>
    private let tableView: UITableView
    
    private lazy var selection: MutableValueProperty<Set<E.ID>> = mutableValueProperty(Set(), { selectedIDs, _ in
        self.selectItems(selectedIDs)
    })
    
    private var arrayObserverRemoval: ObserverRemoval?
    private var selfInitiatedSelectionChange = false
    
    public init(model: ListViewModel<E>, tableView: UITableView) {
        self.model = model
        self.tableView = tableView
        
        super.init()
        
        // TODO: Handle will/didChange
        arrayObserverRemoval = model.data.signal.observe(SignalObserver(
            valueWillChange: {},
            valueChanging: { [weak self] changes, _ in self?.arrayChanged(changes) },
            valueDidChange: {}
        ))
        
        tableView.delegate = self
        tableView.dataSource = self
        
        // Load the initial data
        model.data.start()
    }
    
    deinit {
        arrayObserverRemoval?()
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
    
    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if selfInitiatedSelectionChange {
            return
        }
        
        selfInitiatedSelectionChange = true
        selection.change(selectedItemIDs(), transient: false)
        selfInitiatedSelectionChange = false
    }
    
    /// Returns the set of element IDs corresponding to the view's current selection state.
    private func selectedItemIDs() -> Set<E.ID> {
        var itemIDs: [E.ID] = []
        if let indexPaths = self.tableView.indexPathsForSelectedRows {
            for indexPath in indexPaths {
                let element = self.model.data.elements[indexPath.row]
                itemIDs.append(element.id)
            }
        }
        return Set(itemIDs)
    }
    
    /// Selects the rows corresponding to the given set of element IDs.
    private func selectItems(_ ids: Set<E.ID>) {
        var indexPaths: [IndexPath] = []
        for id in ids {
            if let index = self.model.data.indexForID(id) {
                indexPaths.append(IndexPath(row: index, section: 0))
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
    
    private func arrayChanged(_ changes: [ArrayChange<E>]) {
        // TODO
        Swift.print("ARRAY CHANGED: \(changes)")
        self.tableView.reloadData()
    }
}
