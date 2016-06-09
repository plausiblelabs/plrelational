//
//  AppDelegate.swift
//  SampleApp
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa

import libRelational

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application
    }
    
    @IBAction func dumpRelationOnClipboard(sender: AnyObject) {
        func fail(text: String) {
            let alert = NSAlert()
            alert.messageText = text
            alert.informativeText = "To use this debugging facility, copy an address to the clipboard that points to a valid Relation object."
        }
        
        guard let string = NSPasteboard.generalPasteboard().stringForType(NSPasteboardTypeString) else {
            return fail("No string found on pasteboard")
        }
        
        let scanner = NSScanner(string: string)
        var pointerU64: UInt64 = 0
        guard scanner.scanHexLongLong(&pointerU64) else {
            return fail("Could not parse pointer from string \"\(string)\"")
        }
        
        let object = unsafeBitCast(UInt(pointerU64), AnyObject.self)
        guard let relation = object as? Relation else {
            return fail("The object at \(string) is not a Relation")
        }
        
        relation.graphvizDumpAndOpen(showContents: true)
    }
}
