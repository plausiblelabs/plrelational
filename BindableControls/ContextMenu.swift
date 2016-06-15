//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa

public struct ContextMenu {
    
    // TODO: Remove this in favor of MenuItem
    public enum Item { case
        Titled(title: String, action: () -> Void),
        Separator
    }
    
    public let items: [Item]
    
    public init(items: [Item]) {
        self.items = items
    }
}

extension ContextMenu {
    
    var nsmenu: NSMenu {
        let menu = NSMenu()

        for item in items {
            let nsitem: NSMenuItem
            switch item {
            case let .Titled(title, action):
                nsitem = ClosureMenuItem(title: title, actionClosure: action, keyEquivalent: "")
                break
            case .Separator:
                nsitem = NSMenuItem.separatorItem()
            }
            menu.addItem(nsitem)
        }
        
        return menu
    }
}

private class ClosureMenuItem: NSMenuItem {

    private var actionClosure: () -> Void
    
    init(title: String, actionClosure: () -> Void, keyEquivalent: String) {
        self.actionClosure = actionClosure
        super.init(title: title, action: #selector(ClosureMenuItem.action(_:)), keyEquivalent: keyEquivalent)
        self.target = self
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func action(sender: NSMenuItem) {
        self.actionClosure()
    }
}
