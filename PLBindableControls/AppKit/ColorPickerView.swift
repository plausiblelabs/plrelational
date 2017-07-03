//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

open class ColorPickerView: NSView {

    public lazy var color: ReadWriteProperty<CommonValue<Color>> = { [unowned self] in
        return self.model.color
    }()
    
    private let model: ColorPickerModel
    
    private let colorPopup: PopUpButton<ColorItem>
    private let opacityCombo: ComboBox<CGFloat>
    private let colorPanel: ColorPanel

    public init(defaultColor: Color) {
        // XXX: Using hardcoded sizing for the time being
        let frame = CGRect(x: 0, y: 0, width: 236, height: 26)
        
        self.model = ColorPickerModel(defaultColor: defaultColor)
        
        // Configure color popup button
        colorPopup = PopUpButton(frame: CGRect(x: 0, y: 0, width: 154, height: 26), pullsDown: false)
        _ = colorPopup.items <~ constantValueProperty(model.popupItems)
        _ = colorPopup.selectedObject <~> model.colorItem
        colorPopup.defaultItemContent = MenuItemContent(
            object: ColorItem.default,
            title: model.color.map{ $0.whenMulti("Multiple", otherwise: "Default") },
            image: model.color.map{ $0.whenMulti(multipleColorSwatchImage(), otherwise: unsetColorSwatchImage()) }
        )
        
        // Configure opacity combo box
        let opacityValues: [CGFloat] = stride(from: 0, through: 100, by: 10).map{ CGFloat($0) / 100.0 }
        opacityCombo = ComboBox(frame: CGRect(x: frame.width - 78, y: 0, width: 78, height: 26))
        opacityCombo.formatter = OpacityFormatter()
        _ = opacityCombo.items <~ constantValueProperty(opacityValues)
        _ = opacityCombo.value <~> model.opacityValue
        
        // Configure color panel
        colorPanel = ColorPanel()
//        _ = colorPanel.color <~> model.panelColor
//        _ = colorPanel.visible <~> model.panelVisible
        
        super.init(frame: frame)
        
        // Configure the layout
        self.addSubview(colorPopup)
        self.addSubview(opacityCombo)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private enum ColorItem: Equatable { case
    `default`,
    preset(Color),
    custom(Color),
    other
    
    var color: Color? {
        switch self {
        case .preset(let color):
            return color
        case .custom(let color):
            return color
        case .default, .other:
            return nil
        }
    }
}

private func ==(a: ColorItem, b: ColorItem) -> Bool {
    switch (a, b) {
    case let (.preset(acolor), .preset(bcolor)):
        return acolor == bcolor
    case (.custom, .custom):
        // This is a little unusual: we don't actually compare the custom color values, this way
        // the "Custom" menu item will be a match when setting any ColorItem.Custom value
        return true
    case (.other, .other):
        return true
    default:
        return false
    }
}

private class ColorPickerModel {
    
    /// The color to show in the color picker when there is no selected color.
    private let defaultColor: Color

    fileprivate let presetColors: [Color]
    fileprivate var popupItems: [MenuItem<ColorItem>]!
    
    fileprivate let color: ReadWriteProperty<CommonValue<Color>>
    
    fileprivate let colorItem: ReadWriteProperty<ColorItem?>
    fileprivate let opacityValue: ReadWriteProperty<CGFloat?>
    fileprivate let panelColor: ReadWriteProperty<Color>
    fileprivate let panelVisible: ReadWriteProperty<Bool>
    
    init(defaultColor: Color) {
        self.defaultColor = defaultColor
        self.color = mutableValueProperty(.one(defaultColor))

        // Initialize the internal properties
        // XXX: We use `valueChanging: { true }` so that binding observers are notified even
        // when the item is changing from .Custom to .Custom; this is all because of the funky
        // .Custom handling in `==` for ColorItem, need to revisit this...
        let colorItem: MutableValueProperty<ColorItem?> = mutableValueProperty(nil, valueChanging: { _ in true })
        let customColor: ReadableProperty<Color?> = colorItem.map{
            switch $0 {
            case .some(.custom(let color)):
                return color
            default:
                return nil
            }
        }
        let colorIsCustom: ReadableProperty<Bool> = customColor.map{ $0 != nil }
        self.colorItem = colorItem
        self.opacityValue = mutableValueProperty(nil)
        self.panelColor = mutableValueProperty(defaultColor)
        let panelVisible = mutableValueProperty(false)
        self.panelVisible = panelVisible
        
        // Configure color popup menu items
        var popupItems: [MenuItem<ColorItem>] = []
        var presets: [Color] = []
        
        func addPreset(_ name: String, _ color: Color) {
            let colorItem = ColorItem.preset(color)
            let content = MenuItemContent(
                object: colorItem,
                title: constantValueProperty(name),
                image: constantValueProperty(colorSwatchImage(color))
            )
            let menuItem = MenuItem(.normal(content))
            popupItems.append(menuItem)
            presets.append(color)
        }
        
        func addCustom() {
            // The "Custom" item and the separator above it are only visible when a custom color is defined
            popupItems.append(MenuItem(.separator, visible: colorIsCustom))
            let content = MenuItemContent(
                // TODO: Perhaps `object` should be a ReadableProperty so that it can change if needed
                object: ColorItem.custom(defaultColor),
                title: constantValueProperty("Custom"),
                image: customColor.map{ colorSwatchImage($0 ?? defaultColor) }
            )
            popupItems.append(MenuItem(.momentary(content, action: {}), visible: colorIsCustom))
        }
        
        func addOther() {
            // The "Other" item and the separator above it are always visible
            popupItems.append(MenuItem(.separator))
            let content = MenuItemContent(object: ColorItem.other, title: constantValueProperty("Other…"))
            popupItems.append(MenuItem(.momentary(content, action: { panelVisible.change(true, transient: true) })))
        }
        
        addPreset("Black", Color.black)
        addPreset("White", Color.white)
        addPreset("Red", Color.red)
        addPreset("Orange", Color.orange)
        addPreset("Yellow", Color.yellow)
        addPreset("Green", Color.green)
        addPreset("Blue", Color.blue)
        addPreset("Purple", Color.purple)
        self.presetColors = presets
        
        addCustom()
        addOther()
        
        self.popupItems = popupItems
        
        // Prepare the internal property connections
        
        // color <-> colorItem
        _ = self.color.connectBidi(
            self.colorItem,
            leftToRight: { [weak self] value, isInitial in
                // CommonValue<Color> -> ColorItem
                guard let strongSelf = self else { return .noChange }
                
                let newColorItem: ColorItem
                if let color = value.orNil() {
                    if strongSelf.presetColors.contains(color) {
                        newColorItem = ColorItem.preset(color)
                    } else {
                        newColorItem = ColorItem.custom(color)
                    }
                } else {
                    newColorItem = ColorItem.default
                }
                
                return .change(newColorItem)
            },
            rightToLeft: { value, isInitial in
                // ColorItem -> CommonValue<Color>
                guard !isInitial else { return .noChange }
                if let newColor = value?.color {
                    return .change(CommonValue.one(newColor))
                } else {
                    return .noChange
                }
            }
        )
        
        // color <-> opacityValue
        _ = self.color.connectBidi(
            self.opacityValue,
            leftToRight: { value, isInitial in
                // CommonValue<Color> -> Double?
                .change(value.orNil()?.components.a)
            },
            rightToLeft: { [weak self] value, isInitial in
                // Double? -> CommonValue<Color>
                guard let strongSelf = self else { return .noChange }
                guard let newOpacity = value else { return .noChange }
                guard !isInitial else { return .noChange }
                
                let currentColor: Color = strongSelf.color.value.orDefault(strongSelf.defaultColor)
                let newColor = currentColor.withAlpha(newOpacity)
                return .change(CommonValue.one(newColor))
            }
        )
        
        // color <-> panelColor
//        _ = self.color.connectBidi(
//            self.panelColor,
//            leftToRight: { value, isInitial in
//                // CommonValue<Color> -> Color
//                if let color = value.orNil() {
//                    return .change(color)
//                } else {
//                    return .noChange
//                }
//            },
//            rightToLeft: { value, isInitial in
//                // Color -> CommonValue<Color>
//                guard !isInitial else { return .noChange }
//                return .change(CommonValue.one(value))
//            }
//        )
    }
}

/// Returns a swatch image for the default/unset color case.
private func unsetColorSwatchImage() -> Image {
    return colorSwatchImage(Color.white, f: { rect in
        let topRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.minY)
        
        let path = NSBezierPath()
        path.move(to: topRight)
        path.line(to: bottomLeft)
        NSColor.red.setStroke()
        path.stroke()
    })
}

/// Returns a swatch image for the multiple color case.
private func multipleColorSwatchImage() -> Image {
    return colorSwatchImage(Color.white, f: { rect in
        NSColor.red.setStroke()
        NSBezierPath.strokeLine(from: NSMakePoint(rect.minX + 4, rect.midY), to: NSMakePoint(rect.maxX - 4, rect.midY))
    })
}

/// Returns a color swatch image.
private func colorSwatchImage(_ color: Color, f: ((NSRect) -> ())? = nil) -> Image {
    let size = NSMakeSize(20, 12)
    let rect = NSRect(origin: NSZeroPoint, size: size)
    let image = NSImage(size: size)
    image.lockFocusFlipped(false)
    drawSwatch(rect, color: color.nscolor)
    f?(rect)
    NSColor.black.setStroke()
    NSBezierPath.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
    image.unlockFocus()
    return Image(image)
}

/// Draws a color swatch into the current graphics context.
private func drawSwatch(_ rect: NSRect, color: NSColor) {
    NSColor.black.setFill()
    NSRectFill(rect)
    
    let path = NSBezierPath()
    path.move(to: NSMakePoint(rect.minX, rect.minY))
    path.line(to: NSMakePoint(rect.maxX, rect.minY))
    path.line(to: NSMakePoint(rect.maxX, rect.maxY))
    path.close()
    NSColor.white.setFill()
    path.fill()
    
    color.setFill()
    NSRectFillUsingOperation(rect, .sourceOver)
}

private class OpacityFormatter: NumberFormatter {
    
    override init() {
        super.init()
        
        numberStyle = .percent
        minimum = 0.0
        maximum = 1.0
        maximumFractionDigits = 0
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        // Include the '%' suffix if it wasn't already there, just to make the formatter happy;
        // this allows the user to go away from the combo box even if the user left off the '%' or
        // left the box empty
        var s = string
        // XXX: This is locale-sensitive
        if s.isEmpty {
            s = "100%"
        } else if !s.hasSuffix("%") {
            s = "\(string)%"
        }
        return super.getObjectValue(obj, for: s, errorDescription: error)
    }
    
    override func isPartialStringValid(_ partialString: String, newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        var s = partialString
        
        if s.isEmpty {
            return true
        }
        
        if s.hasSuffix("%") {
            s = s[s.startIndex..<s.characters.index(before: s.endIndex)]
        }
        
        if let intValue = Int(s) {
            if intValue >= 0 && intValue <= 100 {
                return true
            }
        }
        
        NSBeep()
        return false
    }
}
