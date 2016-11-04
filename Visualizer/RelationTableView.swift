//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import Binding
import BindableControls

class RelationTableView: NSObject {

    private let tableView: NSTableView
    fileprivate let relation: Relation
    fileprivate let rows: [Row]
    
    init(relation: Relation, orderAttr: Attribute, orderedAttrs: [Attribute], tableView: NSTableView) {
        precondition(relation.scheme.attributes == Set(orderedAttrs))
        
        self.tableView = tableView
        self.relation = relation
        
        var rows = Array(relation.okRows)
        rows.sort(by: { $0[orderAttr] < $1[orderAttr] })
        self.rows = rows
        
        super.init()

        for column in tableView.tableColumns {
            tableView.removeTableColumn(column)
        }
        for attr in orderedAttrs {
            let column = TableColumn(attribute: attr)
            column.width = 80
            column.resizingMask = .userResizingMask
            column.headerCell.stringValue = attr.name
            tableView.addTableColumn(column)
        }
        tableView.sizeLastColumnToFit()

        tableView.dataSource = self
        tableView.delegate = self
    }
}

extension RelationTableView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }
    
    @objc(tableView:viewForTableColumn:row:) func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn as? TableColumn else {
            return nil
        }
        
        var cellView = tableView.make(withIdentifier: column.identifier, owner: nil) as? CellView
        if cellView == nil {
            let cell = CellView(frame: NSMakeRect(0, 0, column.width, tableView.rowHeight))
            cell.identifier = column.identifier
            cellView = cell
        }

        let relationRow = rows[row]
        let relationValue = relationRow[column.attribute]
        Swift.print("\(column.attribute): \(relationValue)")
        cellView?.textField?.stringValue = relationValue.description
        return cellView
    }
}

extension RelationTableView: NSTableViewDelegate {
    
}

private class TableColumn: NSTableColumn {
    
    fileprivate let attribute: Attribute
    
    fileprivate init(attribute: Attribute) {
        self.attribute = attribute
        super.init(identifier: attribute.name)
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
