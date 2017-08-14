//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

/// :nodoc: Testing and debugging aids are hidden from "official" API for now; may be exposed in the future
public enum Async {
    private static let exclusiveRunloopMode = CFRunLoopMode("PLRelationalAsync exclusive mode" as CFString)
    
    /// Temporarily put the current AsyncManager into an exclusive runloop mode used only for
    /// waiting for async completion an tests. This ensures that activity only happens when we
    /// want it to, and doesn't start doing stuff when internal Cocoa stuff runs its own runloops.
    ///
    /// It returns a function which must be called when you're done with the exclusive mode. The
    /// easiest way to use it is to call it in a defer block, like:
    ///    let endMode = PLRelationalAsync.beginExclusiveRunloopMode()
    ///    defer { endMode() }
    ///
    /// Note: this function is optional, if you call awaitAsyncCompletion directly then it will
    /// run on the default mode, or whatever the AsyncManager is configured to run in.
    public static func beginExclusiveRunloopMode() -> (() -> ()) {
        let manager = AsyncManager.currentInstance
        let oldModes = manager.setRunloopModes([exclusiveRunloopMode])
        return { _ = manager.setRunloopModes(oldModes) }
    }
    
    /// Return the runloop mode that the AsyncManager wants to be run in, when we're
    /// running it manually. This is the first value in the AsyncManager's runloopModes
    /// array, or the default mode if that value is commonModes.
    public static func asyncManagerRunMode() -> CFRunLoopMode {
        let firstMode = AsyncManager.currentInstance.runloopModes[0]
        return (firstMode.rawValue == CFRunLoopMode.commonModes.rawValue) ? .defaultMode : firstMode
    }
    
    /// XXX: Blocks until all async updates/queries are processed by the AsyncManager.
    public static func awaitAsyncCompletion() {
        if AsyncManager.currentInstance.state == .idle {
            return
        }
        
        let runloop = CFRunLoopGetCurrent()
        let modeToRun = asyncManagerRunMode()
        var wentIdle = false
        let stateObserverRemover = AsyncManager.currentInstance.addStateObserver({
            if $0 == .idle {
                wentIdle = true
                CFRunLoopStop(runloop)
            }
        })
        
        // Add a dummy runloop source to prevent CFRunLoopRun from returning immediately if
        // we're running in a mode with no sources. AsyncManager doesn't count as a source.
        var dummySourceContext = CFRunLoopSourceContext()
        dummySourceContext.perform = { _ in }
        let dummySource = CFRunLoopSourceCreate(nil, 0, &dummySourceContext)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), dummySource, modeToRun)
        
        // XXX: Sometimes when opening a new document, Cocoa internals will process events on a new runloop
        // and some internally-called CFRunLoopStop() will cause our CFRunLoopRun() to exit before we've
        // seen the AsyncManager state change.  The workaround is to keep prodding the runloop into action
        // until the AsyncManager processes the async updates and goes idle.
        while !wentIdle {
            CFRunLoopRunInMode(modeToRun, .infinity, false)
        }
        stateObserverRemover()
        
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), dummySource, modeToRun)
    }
}
