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

class DocModelTests: AppTestCase {
    
    func testModel() {
        
        struct BindingVals {
            let itemSelected: Bool
            let selectedItemType: String
            let selectedItemName: String
            let selectedItemsOnlyText: Bool
        }
        
        let model = DocModel(undoManager: UndoManager())
        
        func addCollection(name: String, _ type: ItemType, _ parentID: Int64?) {
            model.newCollection(name, type: type, parentID: parentID)
        }
        
        func addObject(name: String, _ type: ItemType, _ collectionID: Int64, _ order: Double) {
            model.newObject(name, type: type, collectionID: collectionID, order: order)
        }
        
        func verifyBindings(expected: BindingVals, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(model.itemSelected.value, expected.itemSelected, file: file, line: line)
            XCTAssertEqual(model.itemNotSelected.value, !expected.itemSelected, file: file, line: line)
            XCTAssertEqual(model.selectedItemTypesString.value, expected.selectedItemType, file: file, line: line)
            XCTAssertEqual(model.selectedItemNames.value, expected.selectedItemName, file: file, line: line)
            XCTAssertEqual(model.selectedItemsOnlyText.value, expected.selectedItemsOnlyText, file: file, line: line)
        }
        
        func docOutlinePath(parentID: Int64?, _ index: Int) -> TreePath<Row> {
            return path(model.docOutlineTreeViewModel.data, parentID: parentID, index: index)
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
        addObject("Object3", .Image, 3, 8.0)

        // Verify the initial doc outline structure
        verifyTree(model.docOutlineTreeViewModel.data, [
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
        verifyTree(model.inspectorTreeViewModel.data, [])
        
        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: false,
            selectedItemType: "",
            selectedItemName: "",
            selectedItemsOnlyText: false))
        
        // Select a page in the doc outline
        model.docOutlineTreeViewModel.selection.commit([3])

        // Verify that the inspector is updated to show the selected page and its objects
        verifyTree(model.inspectorTreeViewModel.data, [
            "Page1",
            "  Object1",
            "  Object2",
            "  Object3"
        ])
        
        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Page",
            selectedItemName: "Page1",
            selectedItemsOnlyText: false))
        
        // Reorder a page in the doc outline
        model.docOutlineTreeViewModel.move?(srcPath: docOutlinePath(1, 1), dstPath: docOutlinePath(1, 3))
        
        // Verify the new doc outline structure
        verifyTree(model.docOutlineTreeViewModel.data, [
            "Group1",
            "  Collection1",
            "    Child1",
            "    Child2",
            "    Child3",
            "  Page2",
            "  Page1",
            "Group2"
        ])

        // Verify that the inspector contents remain unchanged
        verifyTree(model.inspectorTreeViewModel.data, [
            "Page1",
            "  Object1",
            "  Object2",
            "  Object3"
        ])
        
        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Page",
            selectedItemName: "Page1",
            selectedItemsOnlyText: false))
        
        // Select a single object in the inspector
        model.inspectorTreeViewModel.selection.commit([9])
        
        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Text",
            selectedItemName: "Object1",
            selectedItemsOnlyText: true))

        // Select two objects (of the same type) in the inspector
        model.inspectorTreeViewModel.selection.commit([10, 11])

        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Multiple Images",
            selectedItemName: "",
            selectedItemsOnlyText: false))
        
        // Select two objects (of differing type) in the inspector
        model.inspectorTreeViewModel.selection.commit([9, 10])
        
        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Multiple Items",
            selectedItemName: "",
            selectedItemsOnlyText: false))
    }
}
