//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


fileprivate let runloopMode = CFRunLoopMode("coop.plausible.AsyncRunloopHack" as CFString)

fileprivate let timeToWait: TimeInterval = 0.1

// Comment this out to get the debug logs to show up.
private func debugLog(_: String) {}

/// This class observes runloop activity and blocks the runloop when it's about to return to
/// an idle state while AsyncManager is running. It will block until AsyncManager completes,
/// or after 0.1 seconds, whichever comes first. The purpose is to make quick things happen
/// synchronously, from the point of view of the UI.
///
/// To use, call AsyncRunloopHack.hack() on the main thread. Only do this once.
public class AsyncRunloopHack {
    public class func hack() {
        AsyncRunloopHack().hack()
    }
    
    let manager: AsyncManager
    
    var didSpin = false
    
    init() {
        manager = AsyncManager.currentInstance
    }
    
    private func hack() {
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0, { _ in self.beforeWaiting() })
        CFRunLoopAddObserver(CFRunLoopGetCurrent(), observer, CFRunLoopMode.commonModes)
        manager.addRunloopMode(runloopMode)
        
        _ = manager.addStateObserver({
            debugLog("Changing to state \($0)")
            if $0 == .idle {
                self.didSpin = false
            }
        })
    }
    
    private func beforeWaiting() {
        let state = manager.state
        
        if state != .idle && !didSpin {
            debugLog("Spinning \(state)")
        
            didSpin = true
            
            let startTime = now()
            while manager.state != .idle && (0 ..< timeToWait).contains(now() - startTime) {
                CFRunLoopRunInMode(runloopMode, timeToWait, true)
            }
            debugLog("Leaving")
        }
    }
    
    private func now() -> TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }
}
