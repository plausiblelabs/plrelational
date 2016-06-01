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
        
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        // UI tests must launch the application that they test. Doing this in setup will make sure it happens for each test method.
        XCUIApplication().launch()

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

//    func testTextField() {
//        // TODO
//    }
//
//    func testCheckbox() {
//        // TODO
//    }
    
    func testPopUpButton() {
        let window = XCUIApplication().windows["BindableControlsApp"]
        
        // Select "Fred" in outline view
        window.outlines.childrenMatchingType(.OutlineRow).elementBoundByIndex(0).textFields["PageName"].click()
        
        // TODO: Verify that popup button is initially set to "Default"
        
        // Click on popup button and select "Green"
        window.popUpButtons["Default"].click()
        window.menuItems["Green"].click()
        
        // TODO: Verify that popup button is set to "Green"
        
        // Select "Wilma" in outline view
        window.outlines.childrenMatchingType(.OutlineRow).elementBoundByIndex(1).textFields["PageName"].click()
        
        // TODO: Verify that popup button is set to "Blue"
        
        // TODO: Select both "Fred" and "Wilma" in outline view
        
        // TODO: Verify that popup button is set to "Multiple"
    }
    
//    func testStepper() {
//        // TODO
//    }
}
