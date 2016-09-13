//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
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
        
        let fred = window.outlines.children(matching: .outlineRow).element(boundBy: 0).textFields["PageName"]
        let wilma = window.outlines.children(matching: .outlineRow).element(boundBy: 1).textFields["PageName"]

        func verifyText(_ element: XCUIElement, _ expected: String, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(element.value as? String, expected, file: file, line: line)
        }
        
        func verifyPlaceholder(_ element: XCUIElement, _ expected: String, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(element.placeholderValue, expected, file: file, line: line)
        }
        
        func clickText(_ element: XCUIElement, _ dx: CGFloat, _ dy: CGFloat) {
            let coordinate = element
                .coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: dx, dy: dy))
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
        XCUIElement.perform(withKeyModifiers: .shift) {
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
        let fred = window.outlines.children(matching: .outlineRow).element(boundBy: 0).textFields["PageName"]
        let wilma = window.outlines.children(matching: .outlineRow).element(boundBy: 1).textFields["PageName"]
        
        func verifyCheckbox(_ expected: String) {
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
        XCUIElement.perform(withKeyModifiers: .shift) {
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
        let fred = window.outlines.children(matching: .outlineRow).element(boundBy: 0).textFields["PageName"]
        let wilma = window.outlines.children(matching: .outlineRow).element(boundBy: 1).textFields["PageName"]
        let popup = window.popUpButtons["Day"]
        
        func verifyItem(_ expected: String) {
            XCTAssertEqual(popup.value as? String, expected)
        }

        // Select Fred in outline view
        fred.click()
        
        // Verify that popup button is initially set to "Default"
        verifyItem("Default")
        
        // Click on popup button and select "Saturday"; verify new Fred state
        popup.click()
        window.menuItems["Saturday"].click()
        verifyItem("Saturday")
        
        // Select Wilma in outline view
        wilma.click()
        
        // Verify that popup button is set to "Friday"
        verifyItem("Friday")

        // Click on popup button and select "Saturday"; verify new Wilma state
        popup.click()
        window.menuItems["Saturday"].click()
        verifyItem("Saturday")

        // Select both Fred and Wilma in outline view
        XCUIElement.perform(withKeyModifiers: .shift) {
            fred.click()
        }
        
        // Verify that popup button is set to "Saturday"
        verifyItem("Saturday")
        
        // Click on popup button and select "Tuesday"; verify new state for both Fred and Wilma
        popup.click()
        window.menuItems["Tuesday"].click()
        verifyItem("Tuesday")
        
        // Deselect Wilma in outline view
        XCUIElement.perform(withKeyModifiers: .command) {
            wilma.click()
        }
        
        // Verify that popup button is still set to "Tuesday" for Fred
        verifyItem("Tuesday")
        
        // Click on popup button and select "Sunday"; verify new state for Fred
        popup.click()
        window.menuItems["Sunday"].click()
        verifyItem("Sunday")
        
        // Select Wilma in outline view
        wilma.click()
        
        // Verify that popup button is still set to "Tuesday" for Wilma
        verifyItem("Tuesday")
        
        // Select both Fred and Wilma in outline view
        XCUIElement.perform(withKeyModifiers: .shift) {
            fred.click()
        }
        
        // Verify that popup button shows "Multiple" placeholder
        verifyItem("Multiple")
        
        // Click on popup button and select "Monday"; verify new state for both Fred and Wilma
        popup.click()
        window.menuItems["Monday"].click()
        verifyItem("Monday")
    }
    
//    func testStepper() {
//        // TODO
//    }
}
