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

open class ListView<M: ListViewModel>: NSObject, UITableViewDataSource, UITableViewDelegate {
    
    public let model: M
    private let tableView: UITableView
    
    private lazy var selection: MutableValueProperty<M.Element.ID?> = mutableValueProperty(nil, { selectedID, _ in
        self.selectItem(selectedID)
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
    
    open func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        let element = self.model.data.elements[indexPath.row]
        if self.model.rowSelected(element.data) {
            return indexPath
        } else {
            return nil
        }
    }
    
    /// Selects the row corresponding to the given element ID.
    private func selectItem(_ id: M.Element.ID?) {
        let rowIndex = id.flatMap(self.model.data.indexForID)
        let indexPath = rowIndex.map{ IndexPath(row: $0, section: 0) }
        self.tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
    }
    
    // MARK: - Property observers
    
    private func arrayChanged(_ changes: [ArrayChange<M.Element>]) {
        // TODO
        Swift.print("ARRAY CHANGED: \(changes)")
        self.tableView.reloadData()
    }
}
