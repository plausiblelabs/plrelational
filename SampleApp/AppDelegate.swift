//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa

import libRelational

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // By default, NSColor is set to "ignore alpha" which means that color wells
        // strip alpha, dragged-and-dropped colors lose alpha, and other assorted
        // whatever. We turn this off here, because we actually want our color wells
        // and such to work with alpha values. It's a global setting because Apple,
        // so we set it once here at app startup.
        NSColor.setIgnoresAlpha(false)
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
