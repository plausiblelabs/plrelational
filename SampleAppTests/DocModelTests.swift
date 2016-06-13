//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
import Binding
@testable import SampleApp

class DocModelTests: AppTestCase {
    
    func defaultModel(undoManager: UndoManager = UndoManager()) -> DocModel {
        let model = DocModel(undoManager: undoManager)
        
        func addCollection(name: String, _ type: ItemType, _ parentID: Int64?) {
            model.newCollection(name, type: type, parentID: parentID)
        }
        
        func addObject(name: String, _ type: ItemType, _ collectionID: Int64, _ order: Double) {
            model.newObject(name, type: type, collectionID: collectionID, order: order)
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
        
        return model
    }
    
    func testModel() {
        
        struct BindingVals {
            let itemSelected: Bool
            let selectedItemType: String
            let selectedItemName: String
            let selectedItemsOnlyText: Bool
            let selectedItemsOnlyImage: Bool
        }
        
        let model = defaultModel()
        let commit = ChangeMetadata(transient: false)

        func verifyBindings(expected: BindingVals, file: StaticString = #file, line: UInt = #line) {
            let propsModel = model.propertiesModel
            XCTAssertEqual(propsModel.itemSelected.value, expected.itemSelected, file: file, line: line)
            XCTAssertEqual(propsModel.itemNotSelected.value, !expected.itemSelected, file: file, line: line)
            XCTAssertEqual(propsModel.selectedItemTypesString.value, expected.selectedItemType, file: file, line: line)
            XCTAssertEqual(propsModel.selectedItemNames.value, expected.selectedItemName, file: file, line: line)
            XCTAssertEqual(propsModel.textObjectProperties.value != nil, expected.selectedItemsOnlyText, file: file, line: line)
            XCTAssertEqual(propsModel.imageObjectProperties.value != nil, expected.selectedItemsOnlyImage, file: file, line: line)
        }
        
        func docOutlinePath(parentID: Int64?, _ index: Int) -> TreePath<RowTreeNode> {
            return path(model.docOutlineTreeViewModel.data, parentID: parentID, index: index)
        }
        
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
            selectedItemsOnlyText: false,
            selectedItemsOnlyImage: false))

        // Select a page in the doc outline
        model.docOutlineTreeViewModel.selection.update([4], commit)
        
        // Verify that the inspector is updated to show the selected page
        verifyTree(model.inspectorTreeViewModel.data, [
            "Page2"
        ])

        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Page",
            selectedItemName: "Page2",
            selectedItemsOnlyText: false,
            selectedItemsOnlyImage: false))

        // Select a page in the doc outline that contains objects
        model.docOutlineTreeViewModel.selection.update([3], commit)

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
            selectedItemsOnlyText: false,
            selectedItemsOnlyImage: false))
        
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
            selectedItemsOnlyText: false,
            selectedItemsOnlyImage: false))
        
        // Select a single object in the inspector
        model.inspectorTreeViewModel.selection.update([9], commit)
        
        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Text",
            selectedItemName: "Object1",
            selectedItemsOnlyText: true,
            selectedItemsOnlyImage: false))

        // Select two objects (of the same type) in the inspector
        model.inspectorTreeViewModel.selection.update([10, 11], commit)

        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Multiple Images",
            selectedItemName: "",
            selectedItemsOnlyText: false,
            selectedItemsOnlyImage: true))
        
        // Select two objects (of differing type) in the inspector
        model.inspectorTreeViewModel.selection.update([9, 10], commit)
        
        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Multiple Items",
            selectedItemName: "",
            selectedItemsOnlyText: false,
            selectedItemsOnlyImage: false))
        
        // Select a single text object in the inspector (again)
        model.inspectorTreeViewModel.selection.update([9], commit)

        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Text",
            selectedItemName: "Object1",
            selectedItemsOnlyText: true,
            selectedItemsOnlyImage: false))
        
        // Select a different page in the doc outline
        model.docOutlineTreeViewModel.selection.update([4], commit)
        
        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Page",
            selectedItemName: "Page2",
            selectedItemsOnlyText: false,
            selectedItemsOnlyImage: false))
    }
    
    func testDocOutlineSelectionSpeedUnbound() {
        let model = defaultModel()

        // Toggle back and forth between two pages
        let commit = ChangeMetadata(transient: false)
        let page1: Set<RelationValue> = [3]
        let page2: Set<RelationValue> = [4]
        var first = true
        measureBlock({
            model.docOutlineTreeViewModel.selection.update(first ? page1 : page2, commit)
            first = !first
        })
    }
    
    func testDocOutlineSelectionSpeedOneBound() {
        let model = defaultModel()

        // Observe the selected item names binding
        let propsModel = model.propertiesModel
        var changeCount = 0
        _ = propsModel.selectedItemNames.addChangeObserver({ _ in changeCount += 1 })

        // Toggle back and forth between two pages
        let commit = ChangeMetadata(transient: false)
        let page1: Set<RelationValue> = [3]
        let page2: Set<RelationValue> = [4]
        var first = true
        measureBlock({
            model.docOutlineTreeViewModel.selection.update(first ? page1 : page2, commit)
            first = !first
        })
    }

    func testDocOutlineSelectionSpeedAllBound() {
        let model = defaultModel()
        
        // Observe a number of related bindings
        let propsModel = model.propertiesModel
        var changeCount = 0
        _ = propsModel.itemSelected.addChangeObserver({ _ in changeCount += 1 })
        _ = propsModel.itemNotSelected.addChangeObserver({ _ in changeCount += 1 })
        _ = propsModel.selectedItemTypesString.addChangeObserver({ _ in changeCount += 1 })
        _ = propsModel.selectedItemNames.addChangeObserver({ _ in changeCount += 1 })
        _ = propsModel.selectedItemNamesPlaceholder.addChangeObserver({ _ in changeCount += 1 })
        
        // Toggle back and forth between two pages
        let commit = ChangeMetadata(transient: false)
        let page1: Set<RelationValue> = [3]
        let page2: Set<RelationValue> = [4]
        var first = true
        measureBlock({
            model.docOutlineTreeViewModel.selection.update(first ? page1 : page2, commit)
            first = !first
        })
    }

    func testInspectorSelectionSpeedUnbound() {
        let model = defaultModel()

        // Select the first page
        let commit = ChangeMetadata(transient: false)
        model.docOutlineTreeViewModel.selection.update([3], commit)
        
        // Toggle back and forth between two objects (of differing type)
        let obj1: Set<RelationValue> = [9]
        let obj2: Set<RelationValue> = [10]
        var first = true
        measureBlock({
            model.inspectorTreeViewModel.selection.update(first ? obj1 : obj2, commit)
            first = !first
        })
    }

    func testInspectorSelectionSpeedBound() {
        let model = defaultModel()
        
        // Select the first page
        let commit = ChangeMetadata(transient: false)
        model.docOutlineTreeViewModel.selection.update([3], commit)
        
        // Observe the text object properties binding
        let propsModel = model.propertiesModel
        var changeCount = 0
        _ = propsModel.textObjectProperties.addChangeObserver({ _ in changeCount += 1 })

        // Toggle back and forth between two objects (of differing type)
        let obj1: Set<RelationValue> = [9]
        let obj2: Set<RelationValue> = [10]
        var first = true
        measureBlock({
            model.inspectorTreeViewModel.selection.update(first ? obj1 : obj2, commit)
            first = !first
        })
    }

    struct SelectedItemNamePerfTestData {
        let model: DocModel
        var changeCount: Int = 0
        
        init(model: DocModel) {
            self.model = model
            let commit = ChangeMetadata(transient: false)
            
            // Select the first page
            model.docOutlineTreeViewModel.selection.update([3], commit)
            
            // Select the first text object
            model.inspectorTreeViewModel.selection.update([9], commit)
            
            // Observe a number of bindings
            let propsModel = model.propertiesModel
            _ = model.docOutlineTreeViewModel.data.addChangeObserver({ _ in self.changeCount += 1 })
            _ = model.inspectorTreeViewModel.data.addChangeObserver({ _ in self.changeCount += 1 })
            _ = propsModel.itemSelected.addChangeObserver({ _ in self.changeCount += 1 })
            _ = propsModel.itemNotSelected.addChangeObserver({ _ in self.changeCount += 1 })
            _ = propsModel.selectedItemTypesString.addChangeObserver({ _ in self.changeCount += 1 })
            _ = propsModel.selectedItemNames.addChangeObserver({ _ in self.changeCount += 1 })
            _ = propsModel.selectedItemNamesPlaceholder.addChangeObserver({ _ in self.changeCount += 1 })
        }
    }
    
    func testSelectedItemNameUpdateSpeed() {
        let data = SelectedItemNamePerfTestData(model: defaultModel())

        // Toggle back and forth between two different names
        let s1 = "Hello"
        let s2 = "Hallo"
        var first = true
        let propsModel = data.model.propertiesModel
        let transient = ChangeMetadata(transient: true)
        measureBlock({
            propsModel.selectedItemNames.update(first ? s1 : s2, transient)
            first = !first
        })
    }
    
    func testSelectedItemNameCommitSpeed() {
        let data = SelectedItemNamePerfTestData(model: defaultModel())
        
        // Toggle back and forth between two different names
        let s1 = "Hello"
        let s2 = "Hallo"
        var first = true
        let propsModel = data.model.propertiesModel
        let commit = ChangeMetadata(transient: false)
        measureBlock({
            propsModel.selectedItemNames.update(first ? s1 : s2, commit)
            first = !first
        })
    }
    
    func testSelectedItemNameUndoRedoSpeed() {
        let undoManager = UndoManager()
        let data = SelectedItemNamePerfTestData(model: defaultModel(undoManager))
        
        // Toggle back and forth between two different names (via undo/redo)
        let propsModel = data.model.propertiesModel
        let commit = ChangeMetadata(transient: false)
        propsModel.selectedItemNames.update("Hello", commit)
        propsModel.selectedItemNames.update("Hallo", commit)
        var first = true
        measureBlock({
            if first {
                undoManager.undo()
            } else {
                undoManager.redo()
            }
            first = !first
        })
    }
}
