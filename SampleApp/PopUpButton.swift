//
//  PopUpButton.swift
//  Relational
//
//  Created by Chris Campbell on 5/27/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

class PopUpButton: NSPopUpButton {

    private let bindings = BindingSet()
    
    var titles: ValueBinding<[String]>? {
        didSet {
            bindings.register("titles", titles, { [weak self] value in
                guard let weakSelf = self else { return }
                weakSelf.removeAllItems()
                weakSelf.addItemsWithTitles(value)
                weakSelf.menu?.insertItem(weakSelf.defaultMenuItem, atIndex: 0)
                weakSelf.setSelectedTitle(weakSelf.selectedTitle?.value)
            })
        }
    }

    var selectedTitle: BidiValueBinding<String?>? {
        didSet {
            bindings.register("selectedTitle", selectedTitle, { [weak self] value in
                self?.setSelectedTitle(value)
            })
        }
    }

    var placeholderTitle: ValueBinding<String>? {
        didSet {
            bindings.register("placeholderTitle", placeholderTitle, { [weak self] value in
                self?.defaultMenuItem.title = value
            })
        }
    }

    private var defaultMenuItem: NSMenuItem!
    
    private var selfInitiatedSelectionChange = false

    override init(frame: NSRect, pullsDown flag: Bool) {
        super.init(frame: frame, pullsDown: flag)
        
        autoenablesItems = false
        target = self
        action = #selector(selectionChanged(_:))
        
        // Create the default menu item, which is shown when there is no selection
        defaultMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        defaultMenuItem.enabled = false
        defaultMenuItem.hidden = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("NSCoding not supported")
    }
    
    private func setSelectedTitle(title: String?) {
        selfInitiatedSelectionChange = true
        if let title = title {
            let index = indexOfItemWithTitle(title)
            if index >= 0 {
                selectItemAtIndex(index)
            } else {
                selectItem(defaultMenuItem)
            }
        } else {
            selectItem(defaultMenuItem)
        }
        selfInitiatedSelectionChange = false
    }
    
    @objc func selectionChanged(sender: NSPopUpButton) {
        if selfInitiatedSelectionChange { return }
        
        guard let newTitle = sender.titleOfSelectedItem else { return }
        
        selfInitiatedSelectionChange = true
        selectedTitle?.commit(newTitle)
        selfInitiatedSelectionChange = false
    }
}
