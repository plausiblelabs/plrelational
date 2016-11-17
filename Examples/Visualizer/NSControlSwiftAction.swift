//
// Copyright (c) 2015 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import AppKit


private class ActionTrampoline: NSObject {
    var action: (NSControl) -> Void
    
    init(action: @escaping (NSControl) -> Void) {
        self.action = action
    }
    
    @objc func action(_ sender: NSControl) {
        action(sender)
    }
}

protocol NSActionSettingExtensionProtocol: class {
    var target: AnyObject? { get set }
    var action: Selector? { get set }
}

extension NSActionSettingExtensionProtocol {
    @discardableResult func setAction(_ action: @escaping (Self) -> Void) -> Self {
        let trampoline = ActionTrampoline(action: { sender in
            action(sender as! Self)
        })
        _ = attach(trampoline, to: self)
        self.target = trampoline
        self.action = #selector(ActionTrampoline.action(_:))
        
        return self
    }
}

extension NSControl: NSActionSettingExtensionProtocol {}
extension NSMenuItem: NSActionSettingExtensionProtocol {}
