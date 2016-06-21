//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public struct MenuItemContent<T> {
    public let object: T
    public let title: ObservableValue<String>?
    public let image: ObservableValue<Image>?
    
    public init(object: T, title: ObservableValue<String>?, image: ObservableValue<Image>? = nil) {
        self.object = object
        self.title = title
        self.image = image
    }
}

public enum MenuItemType<T> { case
    Normal(MenuItemContent<T>),
    Momentary(MenuItemContent<T>, action: () -> Void),
    Separator
}

public struct MenuItem<T> {
    public let type: MenuItemType<T>
    public let visible: ObservableValue<Bool>?
    
    public init(_ type: MenuItemType<T>, visible: ObservableValue<Bool>? = nil) {
        self.type = type
        self.visible = visible
    }
}

public func titledMenuItem(title: ObservableValue<String>, object: String = "Default") -> MenuItem<String> {
    return MenuItem(.Normal(MenuItemContent(object: object, title: title, image: nil)))
}

public func titledMenuItem(title: String) -> MenuItem<String> {
    return titledMenuItem(ObservableValue.constant(title), object: title)
}

class NativeMenuItem<T> {
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
    
    private lazy var visible: Property<Bool> = Property { [unowned self] value, _ in
        self.nsitem.hidden = !value
    }

    private lazy var title: Property<String> = Property { [unowned self] value, _ in
        self.nsitem.title = value
    }

    private lazy var image: Property<Image> = Property { [unowned self] value, _ in
        self.nsitem.image = value.nsimage
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
        
        if let v = model.visible {
            visible <~ v
        }
        
        if let content = content {
            // TODO: Avoid cycle here
            nsitem.representedObject = self
            if let t = content.title {
                title <~ t
            }
            if let i = content.image {
                image <~ i
            }
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
