//
//  MenuItem.swift
//  Relational
//
//  Created by Chris Campbell on 6/8/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

struct MenuItemContent<T> {
    let object: T
    let title: ObservableValue<String>?
    let image: ObservableValue<Image>?
    
    init(object: T, title: ObservableValue<String>?, image: ObservableValue<Image>? = nil) {
        self.object = object
        self.title = title
        self.image = image
    }
}

enum MenuItemType<T> { case
    Normal(MenuItemContent<T>),
    Momentary(MenuItemContent<T>, action: () -> Void),
    Separator
}

struct MenuItem<T> {
    let type: MenuItemType<T>
    let visible: ObservableValue<Bool>?
    
    init(_ type: MenuItemType<T>, visible: ObservableValue<Bool>? = nil) {
        self.type = type
        self.visible = visible
    }
}

func titledMenuItem(title: ObservableValue<String>, object: String = "Default") -> MenuItem<String> {
    return MenuItem(.Normal(MenuItemContent(object: object, title: title, image: nil)))
}

func titledMenuItem(title: String) -> MenuItem<String> {
    return titledMenuItem(ObservableValue.constant(title), object: title)
}

class NativeMenuItem<T> {
    private let bindings = BindingSet()
    
    let model: MenuItem<T>
    let nsitem: NSMenuItem

    var object: T? {
        switch model.type {
        case .Normal(let content):
            return content.object
        case .Momentary(let content, _):
            return content.object
        case .Separator:
            return nil
        }
    }
    
    private init(model: MenuItem<T>, nsitem: NSMenuItem) {
        self.model = model
        self.nsitem = nsitem

        let content: MenuItemContent<T>?
        switch model.type {
        case .Normal(let c):
            content = c
        case .Momentary(let c, _):
            content = c
        case .Separator:
            content = nil
        }
        
        bindings.observe(model.visible, "visible", { [weak self] value in
            self?.nsitem.hidden = !value
        })

        if let content = content {
            // TODO: Avoid cycle here
            nsitem.representedObject = self
            bindings.observe(content.title, "title", { [weak self] value in
                self?.nsitem.title = value
            })
            bindings.observe(content.image, "image", { [weak self] value in
                self?.nsitem.image = value.nsimage
            })
        }
    }
    
    convenience init(model: MenuItem<T>) {
        let nsitem: NSMenuItem
        switch model.type {
        case .Normal, .Momentary:
            nsitem = NSMenuItem()
        case .Separator:
            nsitem = NSMenuItem.separatorItem()
        }
        self.init(model: model, nsitem: nsitem)
    }
}
