//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa

public struct ContextMenu {
    
    // TODO: Remove this in favor of MenuItem
    public enum Item { case
        titled(title: String, enabled: Bool, action: () -> Void),
        separator
    }
    
    public let items: [Item]
    
    public init(items: [Item]) {
        self.items = items
    }
}

extension ContextMenu {
    
    public var nsmenu: NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for item in items {
            let nsitem: NSMenuItem
            switch item {
            case let .titled(title, enabled, action):
                nsitem = ClosureMenuItem(title: title, actionClosure: action, keyEquivalent: "")
                nsitem.isEnabled = enabled
                break
            case .separator:
                nsitem = NSMenuItem.separator()
            }
            menu.addItem(nsitem)
        }
        
        return menu
    }
}

private class ClosureMenuItem: NSMenuItem {

    private var actionClosure: () -> Void
    
    init(title: String, actionClosure: @escaping () -> Void, keyEquivalent: String) {
        self.actionClosure = actionClosure
        super.init(title: title, action: #selector(ClosureMenuItem.action(_:)), keyEquivalent: keyEquivalent)
        self.target = self
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func action(_ sender: NSMenuItem) {
        self.actionClosure()
    }
}
