//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public struct MenuItemContent<T> {
    public let object: T
    public let title: ReadableProperty<String>?
    public let image: ReadableProperty<Image>?
    
    public init(object: T, title: ReadableProperty<String>?, image: ReadableProperty<Image>? = nil) {
        self.object = object
        self.title = title
        self.image = image
    }
}

public enum MenuItemType<T> { case
    normal(MenuItemContent<T>),
    momentary(MenuItemContent<T>, action: () -> Void),
    separator
}

public struct MenuItem<T> {
    public let type: MenuItemType<T>
    public let visible: ReadableProperty<Bool>?
    
    public init(_ type: MenuItemType<T>, visible: ReadableProperty<Bool>? = nil) {
        self.type = type
        self.visible = visible
    }
}

public func titledMenuItem(_ title: ReadableProperty<String>, object: String = "Default") -> MenuItem<String> {
    return MenuItem(.normal(MenuItemContent(object: object, title: title, image: nil)))
}

public func titledMenuItem(_ title: String) -> MenuItem<String> {
    return titledMenuItem(constantValueProperty(title), object: title)
}

class NativeMenuItem<T> {
    let model: MenuItem<T>
    let nsitem: NSMenuItem

    var object: T? {
        switch model.type {
        case .normal(let content):
            return content.object
        case .momentary(let content, _):
            return content.object
        case .separator:
            return nil
        }
    }
    
    private lazy var visible: BindableProperty<Bool> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.nsitem.isHidden = !value
    })

    private lazy var title: BindableProperty<String> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.nsitem.title = value
    })

    private lazy var image: BindableProperty<Image> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.nsitem.image = value.nsimage
    })

    private init(model: MenuItem<T>, nsitem: NSMenuItem) {
        self.model = model
        self.nsitem = nsitem

        let content: MenuItemContent<T>?
        switch model.type {
        case .normal(let c):
            content = c
        case .momentary(let c, _):
            content = c
        case .separator:
            content = nil
        }
        
        if let v = model.visible {
            _ = visible <~ v
        }
        
        if let content = content {
            // TODO: Avoid cycle here
            nsitem.representedObject = self
            if let t = content.title {
                _ = title <~ t
            }
            if let i = content.image {
                _ = image <~ i
            }
        }
    }
    
    convenience init(model: MenuItem<T>) {
        let nsitem: NSMenuItem
        switch model.type {
        case .normal, .momentary:
            nsitem = NSMenuItem()
        case .separator:
            nsitem = NSMenuItem.separator()
        }
        self.init(model: model, nsitem: nsitem)
    }
}
