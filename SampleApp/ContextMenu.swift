//
//  ContextMenu.swift
//  Relational
//
//  Created by Chris Campbell on 5/11/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa

struct ContextMenu {
    
    enum Item { case
        Titled(title: String, action: () -> Void),
        Separator
    }
    
    let items: [Item]
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
