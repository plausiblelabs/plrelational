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
    let title: ValueBinding<String>?
    let image: ValueBinding<Image>?
    
    init(object: T, title: ValueBinding<String>?, image: ValueBinding<Image>? = nil) {
        self.object = object
        self.title = title
        self.image = image
    }
}

enum MenuItemType<T> { case
    Normal(MenuItemContent<T>),
    Separator
}

struct MenuItem<T> {
    let type: MenuItemType<T>
    let visible: ValueBinding<Bool>?
    
    init(_ type: MenuItemType<T>, visible: ValueBinding<Bool>? = nil) {
        self.type = type
        self.visible = visible
    }
}

func titledMenuItem(title: ValueBinding<String>, object: String = "Default") -> MenuItem<String> {
    return MenuItem(.Normal(MenuItemContent(object: object, title: title, image: nil)))
}

func titledMenuItem(title: String) -> MenuItem<String> {
    return titledMenuItem(ValueBinding.constant(title), object: title)
}

class NativeMenuItem<T> {
    private let bindings = BindingSet()
    
    var visible: ValueBinding<Bool>? {
        didSet {
        }
    }

    let model: MenuItem<T>
    let nsitem: NSMenuItem

    var object: T? {
        switch model.type {
        case .Normal(let content):
            return content.object
        case .Separator:
            return nil
        }
    }
    
    private init(model: MenuItem<T>, nsitem: NSMenuItem) {
        self.model = model
        self.nsitem = nsitem

        bindings.register("visible", model.visible, { [weak self] value in
            self?.nsitem.hidden = !value
        })

        switch model.type {
        case .Normal(let content):
            // TODO: Avoid cycle here
            nsitem.representedObject = self
            bindings.register("title", content.title, { [weak self] value in
                self?.nsitem.title = value
            })
            bindings.register("image", content.image, { [weak self] value in
                self?.nsitem.image = value.nsimage
            })
        case .Separator:
            break
        }
    }
    
    convenience init(model: MenuItem<T>) {
        let nsitem: NSMenuItem
        switch model.type {
        case .Normal:
            nsitem = NSMenuItem()
        case .Separator:
            nsitem = NSMenuItem.separatorItem()
        }
        self.init(model: model, nsitem: nsitem)
    }
}
