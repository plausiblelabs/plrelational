//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

public enum MenuItemTitle {
    case sync(ReadableProperty<String>)
    case async(AsyncReadableProperty<String>)
}

extension MenuItemTitle {
    public var value: String? {
        switch self{
        case .sync(let p): return p.value
        case .async(let p): return p.value
        }
    }
}

public struct MenuItemContent<T> {
    public let object: T
    public let title: MenuItemTitle?
    public let image: ReadableProperty<Image>?
    
    public init(object: T, title: MenuItemTitle?, image: ReadableProperty<Image>? = nil) {
        self.object = object
        self.title = title
        self.image = image
    }
    
    public init(object: T, title: ReadableProperty<String>, image: ReadableProperty<Image>? = nil) {
        self.init(object: object, title: .sync(title), image: image)
    }
    
    public init(object: T, title: AsyncReadableProperty<String>, image: ReadableProperty<Image>? = nil) {
        self.init(object: object, title: .async(title), image: image)
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
    
    /// Returns the content object if this is a `normal` or `momentary` item, otherwise returns nil.
    public var object: T? {
        switch type {
        case .normal(let content):
            return content.object
        case .momentary(let content, _):
            return content.object
        case .separator:
            return nil
        }
    }
}

extension MenuItem: CustomStringConvertible {
    public var description: String {
        switch type {
        case .normal(let content):
            return "MenuItem[normal: '\(content.title?.value ?? "")']"
        case .momentary(let content, _):
            return "MenuItem[momentary: '\(content.title?.value ?? "")']"
        case .separator:
            return "MenuItem[----]"
        }
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
            switch content.title {
            case .sync(let prop)?:
                _ = title <~ prop
            case .async(let prop)?:
                _ = title <~ prop
            default: break
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
