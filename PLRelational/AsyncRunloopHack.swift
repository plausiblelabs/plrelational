//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


fileprivate let runloopMode = CFRunLoopMode("coop.plausible.AsyncRunloopHack" as CFString)

fileprivate let timeToWait: TimeInterval = 0.1

// Comment this out to get the debug logs to show up.
private func debugLog(_: String) {}

/// :nodoc: Experimental, not part of the "official" API
/// This class observes runloop activity and blocks the runloop when it's about to return to
/// an idle state while AsyncManager is running. It will block until AsyncManager completes,
/// or after 0.1 seconds, whichever comes first. The purpose is to make quick things happen
/// synchronously, from the point of view of the UI.
///
/// To use, call AsyncRunloopHack.hack() on the main thread. Only do this once.
public class AsyncRunloopHack {
    /// Install the hack on the current runloop.
    public class func hack() {
        AsyncRunloopHack().hack()
    }
    
    let manager: AsyncManager
    
    var didSpin = false
    
    init() {
        manager = AsyncManager.currentInstance
    }
    
    private func hack() {
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0, { _, _ in self.beforeWaiting() })
        CFRunLoopAddObserver(CFRunLoopGetCurrent(), observer, CFRunLoopMode.commonModes)
        manager.addRunloopMode(runloopMode)
        
        _ = manager.addStateObserver({
            debugLog("Changing to state \($0)")
            if $0 == .idle {
                self.didSpin = false
            }
        })
        
        // Make a dummy runloop source and add it to our private mode, so that CFRunLoopRun doesn't return immediately.
        var dummySourceContext = CFRunLoopSourceContext()
        dummySourceContext.perform = { _ in }
        let dummySource = CFRunLoopSourceCreate(nil, 0, &dummySourceContext)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), dummySource, runloopMode)
    }
    
    private func beforeWaiting() {
        let state = manager.state
        
        if state != .idle && !didSpin {
            debugLog("Spinning \(state)")
        
            didSpin = true
            
            let startTime = now()
            while manager.state != .idle {
                let remainingTime = timeToWait - (now() - startTime)
                if remainingTime <= 0 {
                    break
                }
                debugLog("Waiting for \(remainingTime)s")
                let result = CFRunLoopRunInMode(runloopMode, remainingTime, true)
                debugLog("Result of waiting is \(result.rawValue)")
            }
            debugLog("Leaving")
        }
    }
    
    private func now() -> TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }
}
