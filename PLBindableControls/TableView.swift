//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding

public protocol TableColumnModel {
    associatedtype ID
    var identifier: ID { get }
    var identifierString: String { get }
    var title: String { get }
}

public struct TableViewModel<C: TableColumnModel, E: ArrayElement> {
    public let columns: [C]
    public let data: ArrayProperty<E>
    public let cellText: (C.ID, E.Data) -> TextProperty
    
    public init(
        columns: [C],
        data: ArrayProperty<E>,
        cellText: @escaping (C.ID, E.Data) -> TextProperty)
    {
        self.columns = columns
        self.data = data
        self.cellText = cellText
    }
}

public class TableView<C: TableColumnModel, E: ArrayElement>: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    
    public let model: TableViewModel<C, E>
    private let tableView: NSTableView
    
    private var elements: [E] {
        return model.data.elements
    }
    
    private var arrayObserverRemoval: ObserverRemoval?
    
    /// Whether to animate insert/delete changes with a fade.
    public var animateChanges = false

    public init(model: TableViewModel<C, E>, tableView: NSTableView) {
        self.model = model
        self.tableView = tableView
        
        super.init()
        
        for column in tableView.tableColumns {
            tableView.removeTableColumn(column)
        }
        for columnModel in model.columns {
            let column = TableColumn(model: columnModel)
            column.width = 80
            column.resizingMask = .userResizingMask
            column.headerCell.stringValue = columnModel.title
            tableView.addTableColumn(column)
        }
        tableView.sizeLastColumnToFit()

        // TODO: Handle will/didChange
        arrayObserverRemoval = model.data.signal.observe(SignalObserver(
            valueWillChange: {},
            valueChanging: { [weak self] stateChange, _ in self?.arrayChanged(stateChange) },
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

    // MARK: NSTableViewDataSource

    public func numberOfRows(in tableView: NSTableView) -> Int {
        return elements.count
    }
    
    @objc(tableView:viewForTableColumn:row:) public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn as? TableColumn<C> else {
            return nil
        }
        
        var cellView = tableView.make(withIdentifier: column.identifier, owner: nil) as? CellView
        if cellView == nil {
            let cell = CellView(frame: NSMakeRect(0, 0, column.width, tableView.rowHeight))
            cell.identifier = column.identifier
            cellView = cell
        }
        
        let element = elements[row]
//        let relationValue = relationRow[column.attribute]
//        Swift.print("\(column.attribute): \(relationValue)")
        if let textField = cellView?.textField as? TextField {
            let cellText = model.cellText(column.model.identifier, element.data)
            textField.bind(cellText)
        }
        return cellView
    }

    // MARK: NSTableViewDataSource
    
    // TODO
    
    // MARK: Property observers
    
    private func arrayChanged(_ arrayChanges: [ArrayChange<E>]) {
        let animation: NSTableViewAnimationOptions = animateChanges ? [.effectFade] : []
        
        tableView.beginUpdates()
        
        // Record changes that were made to the array relative to its previous state
        for change in arrayChanges {
            switch change {
            case .initial(_):
                tableView.reloadData()
                
            case let .insert(index):
                let rows = IndexSet(integer: index)
                tableView.insertRows(at: rows, withAnimation: animation)
                
            case let .delete(index):
                let rows = IndexSet(integer: index)
                // TODO: Allow animation to be customized
                tableView.removeRows(at: rows, withAnimation: animation)
                
            case .update:
                // TODO: For now we will ignore updates and assume that the cell contents will
                // be updated individually in response to the change.  We should make this
                // configurable to allow for optionally calling reloadData() to refresh the
                // entire row on any non-trivial update.
                break
                
            case let .move(srcIndex, dstIndex):
                tableView.moveRow(at: srcIndex, to: dstIndex)
            }
        }
        
        tableView.endUpdates()
    }
}

private class TableColumn<M: TableColumnModel>: NSTableColumn {
    
    fileprivate let model: M
    
    fileprivate init(model: M) {
        self.model = model
        super.init(identifier: model.identifierString)
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class CellView: NSTableCellView {
    
    private var _textField: TextField!
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        
        _textField = TextField(frame: self.bounds)
        _textField.isEditable = false
        _textField.isSelectable = false
        _textField.isBezeled = false
        _textField.drawsBackground = false
        _textField.autoresizingMask = [.viewWidthSizable]
        addSubview(_textField)
        
        self.textField = _textField
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
