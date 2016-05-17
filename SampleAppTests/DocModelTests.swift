//
//  DocModelTests.swift
//  Relational
//
//  Created by Chris Campbell on 5/15/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import XCTest
import libRelational
@testable import SampleApp

class DocModelTests: XCTestCase {
    
    func pretty(node: OrderedTreeBinding.Node, inout _ accum: [String], _ indent: Int) {
        let pad = Array(count: indent, repeatedValue: "  ").joinWithSeparator("")
        accum.append("\(pad)\(node.data["name"])")
        for child in node.children {
            pretty(child, &accum, indent + 1)
        }
    }
    
    func prettyRoot(binding: OrderedTreeBinding) -> [String] {
        var accum: [String] = []
        for node in binding.root.children {
            pretty(node, &accum, 0)
        }
        return accum
    }
    
    func testModel() {
        let model = DocModel(undoManager: UndoManager())
        
        func addCollection(name: String, _ type: ItemType, _ parentID: Int64?) {
            model.newCollection(name, type: type, parentID: parentID)
        }
        
        func addObject(name: String, _ type: ItemType, _ collectionID: Int64, _ order: Double) {
            model.newObject(name, type: type, collectionID: collectionID, order: order)
        }
        
        func verifyTree(binding: OrderedTreeBinding, _ expected: [String]) {
            XCTAssertEqual(prettyRoot(binding), expected)
        }
        
        func verifyBindings(itemSelected itemSelected: Bool, selectedItemType: String?, selectedItemName: String?) {
            XCTAssertEqual(model.itemSelected.value, itemSelected)
            XCTAssertEqual(model.itemNotSelected.value, !itemSelected)
            XCTAssertEqual(model.selectedItemType.value, selectedItemType)
            XCTAssertEqual(model.selectedItemName.value, selectedItemName)
        }
        
        // Insert some collections
        addCollection("Group1", .Group, nil)
        addCollection("Collection1", .Collection, 1)
        addCollection("Page1", .Page, 1)
        addCollection("Page2", .Page, 1)
        addCollection("Child1", .Page, 2)
        addCollection("Child2", .Page, 2)
        addCollection("Child3", .Page, 2)
        addCollection("Group2", .Group, nil)
        
        // Insert some objects
        addObject("Object1", .Text, 3, 5.0)
        addObject("Object2", .Image, 3, 7.0)

        // Verify the initial doc outline structure
        verifyTree(model.docOutlineTreeViewModel.data.binding, [
            "Group1",
            "  Collection1",
            "    Child1",
            "    Child2",
            "    Child3",
            "  Page1",
            "  Page2",
            "Group2"
        ])
        
        // Verify that the inspector is empty initially
        verifyTree(model.inspectorTreeViewModel.data.binding, [])
        
        // Verify properties-related bindings
        verifyBindings(itemSelected: false, selectedItemType: nil, selectedItemName: nil)
        
        // Select a page in the doc outline
        model.docOutlineTreeViewModel.selection.set(id: 3)

        // Verify that the inspector is updated to show the selected page and its objects
        verifyTree(model.inspectorTreeViewModel.data.binding, [
            "Page1",
            "  Object1",
            "  Object2"
        ])
        
        // Verify properties-related bindings
        verifyBindings(itemSelected: true, selectedItemType: "Page", selectedItemName: "Page1")
    }
}
