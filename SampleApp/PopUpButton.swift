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

    var titles: ValueBinding<[String]>? {
        didSet {
            titlesBindingRemoval?()
            titlesBindingRemoval = nil
            if let titles = titles {
                func updateTitles(button: PopUpButton) {
                    button.removeAllItems()
                    button.addItemsWithTitles(titles.value)
                    button.menu?.insertItem(button.defaultMenuItem, atIndex: 0)
                    button.setSelectedTitle(button.selectedTitle?.value)
                }
                
                updateTitles(self)
                
                titlesBindingRemoval = titles.addChangeObserver({ [weak self] in
                    guard let weakSelf = self else { return }
                    updateTitles(weakSelf)
                })
            } else {
                removeAllItems()
            }
        }
    }

    var selectedTitle: BidiValueBinding<String?>? {
        didSet {
            selectedTitleBindingRemoval?()
            selectedTitleBindingRemoval = nil
            if let selectedTitle = selectedTitle {
                setSelectedTitle(selectedTitle.value)
                selectedTitleBindingRemoval = selectedTitle.addChangeObserver({ [weak self] in
                    self?.setSelectedTitle(selectedTitle.value)
                })
            } else {
                setSelectedTitle(nil)
            }
        }
    }

    var placeholderTitle: ValueBinding<String>? {
        didSet {
            placeholderTitleBindingRemoval?()
            placeholderTitleBindingRemoval = nil
            if let placeholderTitle = placeholderTitle {
                defaultMenuItem.title = placeholderTitle.value
                placeholderTitleBindingRemoval = placeholderTitle.addChangeObserver({ [weak self] in
                    guard let weakSelf = self else { return }
                    weakSelf.defaultMenuItem.title = placeholderTitle.value
                })
            } else {
                defaultMenuItem.title = ""
            }
        }
    }

    private var defaultMenuItem: NSMenuItem!
    
    private var selfInitiatedSelectionChange = false

    private var titlesBindingRemoval: ObserverRemoval?
    private var selectedTitleBindingRemoval: ObserverRemoval?
    private var placeholderTitleBindingRemoval: ObserverRemoval?

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
    
    deinit {
        titlesBindingRemoval?()
        selectedTitleBindingRemoval?()
        placeholderTitleBindingRemoval?()
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
