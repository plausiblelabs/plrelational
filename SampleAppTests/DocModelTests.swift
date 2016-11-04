//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import Binding
import BindableControls
@testable import SampleApp

extension DocModel {
    func selectDocOutlineItem(id: RelationValue, _ metadata: ChangeMetadata = ChangeMetadata(transient: false)) {
        docOutlineTreeViewModel.selection.setValue([id], metadata)
    }

    func selectDocOutlineItem(ids: Set<RelationValue>, _ metadata: ChangeMetadata = ChangeMetadata(transient: false)) {
        docOutlineTreeViewModel.selection.setValue(ids, metadata)
    }

    func selectInspectorItems(ids: Set<RelationValue>, _ metadata: ChangeMetadata = ChangeMetadata(transient: false)) {
        inspectorTreeViewModel.selection.setValue(ids, metadata)
    }
}

extension PropertiesModel {
    func updateSelectedItemName(name: String, _ metadata: ChangeMetadata) {
        selectedItemNames.setValue(name, metadata)
    }
}

class DocModelTests: AppTestCase {
    
    func defaultModel(undoManager: UndoManager = UndoManager()) -> DocModel {
        
        let model = DocModel(undoManager: undoManager)

        func addCollection(collectionID: Int64, name: String, type: ItemType, parentID: Int64?, order: Double) {
            model.addCollection(collectionID, name: name, type: type, parentID: parentID, order: order)
        }

        func addObject(objectID: Int64, name: String, type: ItemType, collectionID: Int64, order: Double) {
            model.addObject(objectID, name: name, type: type, collectionID: collectionID, order: order)
        }

        addCollection(1, name: "Group1", type: .Group, parentID: nil, order: 5.0)
        addCollection(2, name: "Collection1", type: .Collection, parentID: 1, order: 5.0)
        addCollection(3, name: "Page1", type: .Page, parentID: 1, order: 7.0)
        addCollection(4, name: "Page2", type: .Page, parentID: 1, order: 8.0)
        addCollection(5, name: "Child1", type: .Page, parentID: 2, order: 5.0)
        addCollection(6, name: "Child2", type: .Page, parentID: 2, order: 7.0)
        addCollection(7, name: "Child3", type: .Page, parentID: 2, order: 8.0)
        addCollection(8, name: "Group2", type: .Group, parentID: nil, order: 7.0)
        
        addObject(9, name: "Object1", type: .Text, collectionID: 3, order: 5.0)
        addObject(10, name: "Object2", type: .Image, collectionID: 3, order: 7.0)
        addObject(11, name: "Object3", type: .Image, collectionID: 3, order: 8.0)

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
        model.selectDocOutlineItem(4)
        
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
        model.selectDocOutlineItem(3)

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
        
        // Select the page item in the inspector
        model.selectInspectorItems([3])

        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Page",
            selectedItemName: "Page1",
            selectedItemsOnlyText: false,
            selectedItemsOnlyImage: false))

        // Select a single object in the inspector
        model.selectInspectorItems([9])
        
        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Text",
            selectedItemName: "Object1",
            selectedItemsOnlyText: true,
            selectedItemsOnlyImage: false))

        // Select two objects (of the same type) in the inspector
        model.selectInspectorItems([10, 11])

        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Multiple Images",
            selectedItemName: "",
            selectedItemsOnlyText: false,
            selectedItemsOnlyImage: true))
        
        // Select two objects (of differing type) in the inspector
        model.selectInspectorItems([9, 10])
        
        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Multiple Items",
            selectedItemName: "",
            selectedItemsOnlyText: false,
            selectedItemsOnlyImage: false))
        
        // Select a single text object in the inspector (again)
        model.selectInspectorItems([9])

        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Text",
            selectedItemName: "Object1",
            selectedItemsOnlyText: true,
            selectedItemsOnlyImage: false))
        
        // Select a different page in the doc outline
        model.selectDocOutlineItem(4)
        
        // Verify properties-related bindings
        verifyBindings(BindingVals(
            itemSelected: true,
            selectedItemType: "Page",
            selectedItemName: "Page2",
            selectedItemsOnlyText: false,
            selectedItemsOnlyImage: false))
    }
    
//    func testDocOutlineSelectionSpeedUnbound() {
//        let model = defaultModel()
//
//        // Toggle back and forth between two pages
//        let commit = ChangeMetadata(transient: false)
//        let page1: Set<RelationValue> = [3]
//        let page2: Set<RelationValue> = [4]
//        var first = true
//        measureBlock({
//            model.selectDocOutlineItem(first ? page1 : page2, commit)
//            first = !first
//        })
//    }
//    
//    func testDocOutlineSelectionSpeedOneBound() {
//        let model = defaultModel()
//
//        // Observe the selected item names property
//        let propsModel = model.propertiesModel
//        var changeCount = 0
//        _ = propsModel.selectedItemNames.signal.observe({ _ in changeCount += 1 })
//
//        // Toggle back and forth between two pages
//        let commit = ChangeMetadata(transient: false)
//        let page1: Set<RelationValue> = [3]
//        let page2: Set<RelationValue> = [4]
//        var first = true
//        measureBlock({
//            model.selectDocOutlineItem(first ? page1 : page2, commit)
//            first = !first
//        })
//    }
//
//    func testDocOutlineSelectionSpeedAllBound() {
//        let model = defaultModel()
//        
//        // Observe a number of related bindings
//        let propsModel = model.propertiesModel
//        var changeCount = 0
//        _ = propsModel.itemSelected.signal.observe({ _ in changeCount += 1 })
//        _ = propsModel.itemNotSelected.signal.observe({ _ in changeCount += 1 })
//        _ = propsModel.selectedItemTypesString.signal.observe({ _ in changeCount += 1 })
//        _ = propsModel.selectedItemNames.signal.observe({ _ in changeCount += 1 })
//        _ = propsModel.selectedItemNamesPlaceholder.signal.observe({ _ in changeCount += 1 })
//        
//        // Toggle back and forth between two pages
//        let commit = ChangeMetadata(transient: false)
//        let page1: Set<RelationValue> = [3]
//        let page2: Set<RelationValue> = [4]
//        var first = true
//        measureBlock({
//            model.selectDocOutlineItem(first ? page1 : page2, commit)
//            first = !first
//        })
//    }
//
//    func testInspectorSelectionSpeedUnbound() {
//        let model = defaultModel()
//
//        // Select the first page
//        let commit = ChangeMetadata(transient: false)
//        model.selectDocOutlineItem(3, commit)
//        
//        // Toggle back and forth between two objects (of differing type)
//        let obj1: Set<RelationValue> = [9]
//        let obj2: Set<RelationValue> = [10]
//        var first = true
//        measureBlock({
//            model.selectInspectorItems(first ? obj1 : obj2, commit)
//            first = !first
//        })
//    }
//
//    func testInspectorSelectionSpeedBound() {
//        let model = defaultModel()
//        
//        // Select the first page
//        let commit = ChangeMetadata(transient: false)
//        model.selectDocOutlineItem(3, commit)
//        
//        // Observe the text object properties binding
//        let propsModel = model.propertiesModel
//        var changeCount = 0
//        _ = propsModel.textObjectProperties.signal.observe({ _ in changeCount += 1 })
//
//        // Toggle back and forth between two objects (of differing type)
//        let obj1: Set<RelationValue> = [9]
//        let obj2: Set<RelationValue> = [10]
//        var first = true
//        measureBlock({
//            model.selectInspectorItems(first ? obj1 : obj2, commit)
//            first = !first
//        })
//    }
//
//    struct SelectedItemNamePerfTestData {
//        let model: DocModel
//        var changeCount: Int = 0
//        
//        init(model: DocModel) {
//            self.model = model
//            let commit = ChangeMetadata(transient: false)
//            
//            // Select the first page
//            model.selectDocOutlineItem(3, commit)
//            
//            // Select the first text object
//            model.selectInspectorItems([9], commit)
//            
//            // Observe a number of bindings
//            let propsModel = model.propertiesModel
//            _ = model.docOutlineTreeViewModel.data.signal.observe({ _ in self.changeCount += 1 })
//            _ = model.inspectorTreeViewModel.data.signal.observe({ _ in self.changeCount += 1 })
//            _ = propsModel.itemSelected.signal.observe({ _ in self.changeCount += 1 })
//            _ = propsModel.itemNotSelected.signal.observe({ _ in self.changeCount += 1 })
//            _ = propsModel.selectedItemTypesString.signal.observe({ _ in self.changeCount += 1 })
//            _ = propsModel.selectedItemNames.signal.observe({ _ in self.changeCount += 1 })
//            _ = propsModel.selectedItemNamesPlaceholder.signal.observe({ _ in self.changeCount += 1 })
//        }
//    }
//    
//    func testSelectedItemNameUpdateSpeed() {
//        let data = SelectedItemNamePerfTestData(model: defaultModel())
//
//        // Toggle back and forth between two different names
//        let s1 = "Hello"
//        let s2 = "Hallo"
//        var first = true
//        let propsModel = data.model.propertiesModel
//        let transient = ChangeMetadata(transient: true)
//        measureBlock({
//            propsModel.updateSelectedItemName(first ? s1 : s2, transient)
//            first = !first
//        })
//    }
//    
//    func testSelectedItemNameCommitSpeed() {
//        let data = SelectedItemNamePerfTestData(model: defaultModel())
//        
//        // Toggle back and forth between two different names
//        let s1 = "Hello"
//        let s2 = "Hallo"
//        var first = true
//        let propsModel = data.model.propertiesModel
//        let commit = ChangeMetadata(transient: false)
//        measureBlock({
//            propsModel.updateSelectedItemName(first ? s1 : s2, commit)
//            first = !first
//        })
//    }
//    
//    func testSelectedItemNameUndoRedoSpeed() {
//        let undoManager = UndoManager()
//        let data = SelectedItemNamePerfTestData(model: defaultModel(undoManager))
//        
//        // Toggle back and forth between two different names (via undo/redo)
//        let propsModel = data.model.propertiesModel
//        let commit = ChangeMetadata(transient: false)
//        propsModel.updateSelectedItemName("Hello", commit)
//        propsModel.updateSelectedItemName("Hallo", commit)
//        var first = true
//        measureBlock({
//            if first {
//                undoManager.undo()
//            } else {
//                undoManager.redo()
//            }
//            first = !first
//        })
//    }
}
