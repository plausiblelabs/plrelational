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

//    func testTextField() {
//        // TODO
//    }
//
    func testCheckbox() {
        let window = XCUIApplication().windows["BindableControlsApp"]
        
        // Tree View
        let fred = window.outlines.childrenMatchingType(.OutlineRow).elementBoundByIndex(0).textFields["PageName"]
        let wilma = window.outlines.childrenMatchingType(.OutlineRow).elementBoundByIndex(1).textFields["PageName"]
        
        func verifyCheckbox(expected: String) {
            XCTAssertEqual(window.checkBoxes["Editable"].value as? String, expected)
        }
        
        func clickCheckbox() {
            window.checkBoxes["Editable"].click()
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
