//
//  PopUpButton.swift
//  Relational
//
//  Created by Chris Campbell on 5/27/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

class PopUpButton<T: Equatable>: NSPopUpButton {

    private let bindings = BindingSet()
    
    var items: ValueBinding<[MenuItem<T>]>? {
        didSet {
            bindings.register("items", items, { [weak self] value in
                guard let weakSelf = self else { return }

                // Clear the menu
                weakSelf.removeAllItems()

                // Add the menu items
                let nativeItems = value.map{ NativeMenuItem(model: $0) }
                for item in nativeItems {
                    weakSelf.menu?.addItem(item.nsitem)
                }

                // Insert the default menu item, if we have one
                if let defaultMenuItem = weakSelf.defaultMenuItem {
                    weakSelf.menu?.insertItem(defaultMenuItem.nsitem, atIndex: 0)
                }
                
                // Set the selected item, if needed
                weakSelf.setSelectedItem(weakSelf.selectedObject?.value)
            })
        }
    }

    var selectedObject: BidiValueBinding<T?>? {
        didSet {
            bindings.register("selectedObject", selectedObject, { [weak self] value in
                self?.setSelectedItem(value)
            })
        }
    }

    var defaultItemContent: MenuItemContent<T>? {
        didSet {
            if let existingItem = defaultMenuItem?.nsitem {
                existingItem.menu?.removeItem(existingItem)
            }
            if let content = defaultItemContent {
                let model = MenuItem(.Normal(content))
                let nativeItem = NativeMenuItem(model: model)
                nativeItem.nsitem.hidden = true
                nativeItem.nsitem.enabled = false
                defaultMenuItem = nativeItem
                menu?.insertItem(nativeItem.nsitem, atIndex: 0)
            } else {
                defaultMenuItem = nil
            }
        }
    }

    private var defaultMenuItem: NativeMenuItem<T>?
    
    private var selfInitiatedSelectionChange = false
    private var selectedIndex = -1

    override init(frame: NSRect, pullsDown flag: Bool) {
        super.init(frame: frame, pullsDown: flag)
        
        autoenablesItems = false
        target = self
        action = #selector(selectionChanged(_:))
    }
    
    required init?(coder: NSCoder) {
        fatalError("NSCoding not supported")
    }
    
    private func setSelectedItem(object: T?) {
        selfInitiatedSelectionChange = true
        if let object = object, menu = menu {
            // Find menu item that matches given object
            let index = menu.itemArray.indexOf({
                let nativeItem = $0.representedObject as? NativeMenuItem<T>
                return nativeItem?.object == object
            })
            if let index = index {
                selectItemAtIndex(index)
                selectedIndex = index
            } else {
                selectItem(defaultMenuItem?.nsitem)
                selectedIndex = -1
            }
        } else {
            // Select the default item if one exists, otherwise clear selection
            selectItem(defaultMenuItem?.nsitem)
            selectedIndex = -1
        }
        selfInitiatedSelectionChange = false
    }
    
    @objc func selectionChanged(sender: NSPopUpButton) {
        if selfInitiatedSelectionChange { return }
        
        guard let selectedItem = sender.selectedItem else { return }
        guard let nativeItem = selectedItem.representedObject as? NativeMenuItem<T> else { return }
        
        switch nativeItem.model.type {
        case .Normal:
            guard let object = nativeItem.object else { return }
            selfInitiatedSelectionChange = true
            selectedObject?.commit(object)
            selfInitiatedSelectionChange = false
            
        case .Momentary(_, let action):
            selfInitiatedSelectionChange = true
            if selectedIndex >= 0 {
                selectItemAtIndex(selectedIndex)
            } else {
                selectItem(defaultMenuItem?.nsitem)
            }
            selfInitiatedSelectionChange = false
            action()
            
        case .Separator:
            break
        }
    }
}
