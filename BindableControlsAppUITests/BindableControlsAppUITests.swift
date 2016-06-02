//
//  BindableControlsAppUITests.swift
//  BindableControlsAppUITests
//
//  Created by Chris Campbell on 5/31/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import XCTest

class BindableControlsAppUITests: XCTestCase {
        
    override func setUp() {
        super.setUp()
        
        continueAfterFailure = false
        XCUIApplication().launch()
    }
    
    override func tearDown() {
        super.tearDown()
    }

    func testTextField() {
        let window = XCUIApplication().windows["BindableControlsApp"]
        let field = window.textFields["NameField"]
        
        let fred = window.outlines.childrenMatchingType(.OutlineRow).elementBoundByIndex(0).textFields["PageName"]
        let wilma = window.outlines.childrenMatchingType(.OutlineRow).elementBoundByIndex(1).textFields["PageName"]

        func verifyText(element: XCUIElement, _ expected: String, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(element.value as? String, expected, file: file, line: line)
        }
        
        func verifyPlaceholder(element: XCUIElement, _ expected: String, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(element.placeholderValue, expected, file: file, line: line)
        }
        
        func clickText(element: XCUIElement, _ dx: CGFloat, _ dy: CGFloat) {
            let coordinate = element
                .coordinateWithNormalizedOffset(CGVector(dx: 0, dy: 0))
                .coordinateWithOffset(CGVector(dx: dx, dy: dy))
            coordinate.click()
        }
        
        // Click on Fred cell and verify that text field contains "Fred"
        fred.click()
        verifyText(field, "Fred")

        // Click on text field to give it focus, append some text, and verify that the updated
        // name is reflected in the outline cell
        field.click()
        field.typeText("d")
        verifyText(field, "Fredd")
        verifyText(fred, "Fredd")
        verifyText(wilma, "Wilma")

        // TODO: Editing the cell text here makes the test framework unable to locate the cell's
        // text field in later steps, so we'll skip this part for now (and just add the 'o' in
        // the text field rather than the cell)
        field.typeText("o")
//        // Click on Fredd cell (has to be within the text bounds) and wait for focus, update the
//        // text, and verify that the updated name is reflected in the text field
//        clickText(fred, 10, 10)
//        clickText(fred, 10, 10)
//        fred.typeKey("e", modifierFlags: .Control)
//        fred.typeText("o")
        verifyText(field, "Freddo")
        verifyText(fred, "Freddo")
        
        // Click on Wilma cell and verify that text field contains "Wilma"
        wilma.click()
        verifyText(field, "Wilma")
        
        // Click on text field to give it focus, append some text, and verify that the updated
        // name is reflected in the outline cell
        field.click()
        field.typeText("x")
        verifyText(field, "Wilmax")
        verifyText(fred, "Freddo")
        verifyText(wilma, "Wilmax")
        
        // Shift-select both Fred and Wilma cells; verify the placeholder text
        XCUIElement.performWithKeyModifiers(.Shift) {
            fred.click()
        }
        verifyText(field, "")
        verifyPlaceholder(field, "Multiple Values")
        
        // Click on text field to give it focus, type a new name, and verify that both cells
        // are updated
        field.click()
        field.typeText("Barney")
        verifyText(field, "Barney")
        verifyText(fred, "Barney")
        verifyText(wilma, "Barney")
    }

    func testCheckbox() {
        let window = XCUIApplication().windows["BindableControlsApp"]
        let checkbox = window.checkBoxes["Editable"]
        
        // Tree View
        let fred = window.outlines.childrenMatchingType(.OutlineRow).elementBoundByIndex(0).textFields["PageName"]
        let wilma = window.outlines.childrenMatchingType(.OutlineRow).elementBoundByIndex(1).textFields["PageName"]
        
        func verifyCheckbox(expected: String) {
            XCTAssertEqual(checkbox.value as? String, expected)
        }
        
        func clickCheckbox() {
            checkbox.click()
        }
        
        // Verify fred's initial state
        fred.click()
        verifyCheckbox("Off")
        
        // Toggle checkbox on and off
        clickCheckbox()
        verifyCheckbox("On")
        clickCheckbox()
        verifyCheckbox("Off")
        
        // Verify wilma's initial state
        wilma.click()
        verifyCheckbox("On")
        
        // Shift-select both fred and wilma; verify mixed state
        XCUIElement.performWithKeyModifiers(.Shift) {
            fred.click()
        }
        verifyCheckbox("Mixed")
        
        // Toggle the mixed-state checkbox
        clickCheckbox()
        
        // Verify both fred and wilma register the new state
        fred.click()
        verifyCheckbox("On")
        wilma.click()
        verifyCheckbox("On")
    }
    
    func testPopUpButton() {
        let window = XCUIApplication().windows["BindableControlsApp"]
        let fred = window.outlines.childrenMatchingType(.OutlineRow).elementBoundByIndex(0).textFields["PageName"]
        let wilma = window.outlines.childrenMatchingType(.OutlineRow).elementBoundByIndex(1).textFields["PageName"]
        let colorPopup = window.popUpButtons["Color"]
        
        // Select "Fred" in outline view
        fred.click()
        
        // TODO: Verify that popup button is initially set to "Default"
        
        // Click on popup button and select "Green"
        colorPopup.click()
        window.menuItems["Green"].click()
        
        // TODO: Verify that popup button is set to "Green"
        
        // Select "Wilma" in outline view
        wilma.click()
        
        // TODO: Verify that popup button is set to "Blue"
        
        // TODO: Select both "Fred" and "Wilma" in outline view
        
        // TODO: Verify that popup button is set to "Multiple"
    }
    
//    func testStepper() {
//        // TODO
//    }
}
