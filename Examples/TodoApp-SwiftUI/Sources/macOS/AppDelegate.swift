//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import SwiftUI
import PLRelational
import PLRelationalCombine

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    private var undoManager: PLRelationalCombine.UndoManager!
    private var model: Model!
    private var contentViewModel: ContentViewModel!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Prepare the undo manager
        undoManager = UndoManager()

        // Initialize our model
        model = Model(undoManager: undoManager, path: "/tmp/TodoApp-SwiftUI.db")
        if !model.dbAlreadyExisted {
            _ = model.addDefaultData()
        }

        // Create the SwiftUI view that provides the window contents
        contentViewModel = ContentViewModel(model: model)
        let contentView = ContentView(model: contentViewModel)

        // Create the window and set the content view
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }
}
    
extension AppDelegate: NSWindowDelegate {
    func windowWillReturnUndoManager(_ window: NSWindow) -> Foundation.UndoManager? {
        return undoManager.native
    }
}
