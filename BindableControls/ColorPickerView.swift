//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class ColorPickerView: NSView {

    private let model: ColorPickerModel
    
    public var color: MutableObservableValue<CommonValue<Color>>? {
        didSet {
            if let color = color {
                setColorBinding(color)
            }
            model.color = color
        }
    }
    
    private let colorPopup: PopUpButton<ColorItem>
    private let opacityCombo: ComboBox<CGFloat>
    private let colorPanel: ColorPanel

    public init(defaultColor: Color) {
        self.model = ColorPickerModel(defaultColor: defaultColor)
        
        // Configure color popup button
        colorPopup = PopUpButton(frame: NSZeroRect, pullsDown: false)
        colorPopup.items <~ ObservableValue.constant(model.popupItems)
        colorPopup.selectedObject = model.colorItem
        
        // Configure opacity combo box
        let opacityValues: [CGFloat] = 0.stride(through: 100, by: 10).map{ CGFloat($0) / 100.0 }
        opacityCombo = ComboBox(frame: NSZeroRect)
        opacityCombo.formatter = OpacityFormatter()
        opacityCombo.items <~ ObservableValue.constant(opacityValues)
        opacityCombo.value = model.opacityValue
        
        // Configure color panel
        colorPanel = ColorPanel()
        colorPanel.color = model.panelColor
        colorPanel.visible = model.panelVisible
        
        super.init(frame: NSZeroRect)
        
        // Configure the layout
        let horizontalStack = NSStackView(views: [colorPopup, opacityCombo])
        horizontalStack.orientation = .Horizontal
        
        let verticalStack = NSStackView(views: [horizontalStack])
        verticalStack.orientation = .Vertical
        verticalStack.alignment = .Leading
        verticalStack.spacing = 2
        
//        if let label = label {
//            verticalStack.insertView(setupLabel(label), atIndex: 0, inGravity: .Leading)
//        }
        
        self.addSubview(verticalStack)
        self.addConstraints([
            NSLayoutConstraint(item: self, attribute: .Left, relatedBy: .Equal, toItem: verticalStack, attribute: .Left, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: self, attribute: .Right, relatedBy: .Equal, toItem: verticalStack, attribute: .Right, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: self, attribute: .Top, relatedBy: .Equal, toItem: verticalStack, attribute: .Top, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: self, attribute: .Bottom, relatedBy: .Equal, toItem: verticalStack, attribute: .Bottom, multiplier: 1, constant: 0),
        ])
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setColorBinding(binding: MutableObservableValue<CommonValue<Color>>) {
        // TODO: Perhaps defaultItemContent should be a ObservableValue so that we can move this
        // to the model
        colorPopup.defaultItemContent = MenuItemContent(
            object: ColorItem.Default,
            title: binding.map{ $0.whenMulti("Multiple", otherwise: "Default") },
            image: binding.map{ $0.whenMulti(multipleColorSwatchImage(), otherwise: unsetColorSwatchImage()) }
        )
    }
}

private enum ColorItem: Equatable { case
    Default,
    Preset(Color),
    Custom(Color),
    Other
    
    var color: Color? {
        switch self {
        case .Preset(let color):
            return color
        case .Custom(let color):
            return color
        case .Default, .Other:
            return nil
        }
    }
}

private func ==(a: ColorItem, b: ColorItem) -> Bool {
    switch (a, b) {
    case let (.Preset(acolor), .Preset(bcolor)):
        return acolor == bcolor
    case (.Custom, .Custom):
        // This is a little unusual: we don't actually compare the custom color values, this way
        // the "Custom" menu item will be a match when setting any ColorItem.Custom value
        return true
    case (.Other, .Other):
        return true
    default:
        return false
    }
}

private class ColorPickerModel {
    
    private let bindings = BindingSet()
    
    var color: MutableObservableValue<CommonValue<Color>>? {
        didSet {
            bindings.connect(
                color, "color",
                colorItem, "colorItem",
                forward: { [weak self] value in
                    // CommonValue<Color> -> ColorItem
                    guard let weakSelf = self else { return .NoChange }
                    
                    let newColorItem: ColorItem
                    if let color = value.orNil() {
                        if weakSelf.presetColors.contains(color) {
                            newColorItem = ColorItem.Preset(color)
                        } else {
                            newColorItem = ColorItem.Custom(color)
                        }
                    } else {
                        newColorItem = ColorItem.Default
                    }
                    
                    return .Change(newColorItem)
                },
                reverse: { value in
                    // ColorItem -> CommonValue<Color>
                    if let newColor = value?.color {
                        return .Change(CommonValue.One(newColor))
                    } else {
                        return .NoChange
                    }
                }
            )
            
            bindings.connect(
                color, "color",
                opacityValue, "opacityValue",
                forward: { value in
                    // CommonValue<Color> -> Double?
                    .Change(value.orNil()?.components.a)
                },
                reverse: { [weak self] value in
                    // Double? -> CommonValue<Color>
                    guard let weakSelf = self else { return .NoChange }
                    guard let newOpacity = value else { return .NoChange }
                    
                    let currentColor: Color
                    if let colorValue = weakSelf.color?.value {
                        currentColor = colorValue.orDefault(weakSelf.defaultColor)
                    } else {
                        currentColor = weakSelf.defaultColor
                    }
                    
                    let newColor = currentColor.withAlpha(newOpacity)
                    return .Change(CommonValue.One(newColor))
                }
            )
            
            bindings.connect(
                color, "color",
                panelColor, "panelColor",
                forward: { value in
                    // CommonValue<Color> -> Color
                    if let color = value.orNil() {
                        return .Change(color)
                    } else {
                        return .NoChange
                    }
                },
                reverse: { value in
                    // Color -> CommonValue<Color>
                    .Change(CommonValue.One(value))
                }
            )
        }
    }

    /// The color to show in the color picker when there is no selected color.
    private let defaultColor: Color

    private let presetColors: [Color]
    private var popupItems: [MenuItem<ColorItem>]!
    
    private let colorItem: MutableObservableValue<ColorItem?>
    private let opacityValue: MutableObservableValue<CGFloat?>
    private let panelColor: MutableObservableValue<Color>
    private let panelVisible: MutableObservableValue<Bool>
    
    init(defaultColor: Color) {
        self.defaultColor = defaultColor
        
        // Initialize the internal bindings
        // XXX: We use `valueChanging: { true }` so that binding observers are notified even
        // when the item is changing from .Custom to .Custom; this is all because of the funky
        // .Custom handling in `==` for ColorItem, need to revisit this...
        let colorItem: MutableObservableValue<ColorItem?> = mutableObservableValue(nil, valueChanging: { _ in true })
        let customColor: ObservableValue<Color?> = colorItem.map{
            switch $0 {
            case .Some(.Custom(let color)):
                return color
            default:
                return nil
            }
        }
        let colorIsCustom: ObservableValue<Bool> = customColor.map{ $0 != nil }
        self.colorItem = colorItem
        self.opacityValue = mutableObservableValue(nil)
        self.panelColor = mutableObservableValue(defaultColor)
        self.panelVisible = mutableObservableValue(false)

        // Configure color popup menu items
        var popupItems: [MenuItem<ColorItem>] = []
        var presets: [Color] = []
        
        func addPreset(name: String, _ color: Color) {
            let colorItem = ColorItem.Preset(color)
            let content = MenuItemContent(
                object: colorItem,
                title: ObservableValue.constant(name),
                image: ObservableValue.constant(colorSwatchImage(color))
            )
            let menuItem = MenuItem(.Normal(content))
            popupItems.append(menuItem)
            presets.append(color)
        }
        
        func addCustom() {
            // The "Custom" item and the separator above it are only visible when a custom color is defined
            popupItems.append(MenuItem(.Separator, visible: colorIsCustom))
            let content = MenuItemContent(
                // TODO: Perhaps `object` should be a ObservableValue so that it can change if needed
                object: ColorItem.Custom(defaultColor),
                title: ObservableValue.constant("Custom"),
                image: customColor.map{ colorSwatchImage($0 ?? defaultColor) }
            )
            popupItems.append(MenuItem(.Momentary(content, action: {}), visible: colorIsCustom))
        }
        
        func addOther() {
            // The "Other" item and the separator above it are always visible
            popupItems.append(MenuItem(.Separator))
            let content = MenuItemContent(object: ColorItem.Other, title: ObservableValue.constant("Other…"))
            popupItems.append(MenuItem(.Momentary(content, action: { self.bindings.update(self.panelVisible, newValue: true) })))
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
    }
}

/// Returns a swatch image for the default/unset color case.
private func unsetColorSwatchImage() -> Image {
    return colorSwatchImage(Color.white, f: { rect in
        let topRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.minY)
        
        let path = NSBezierPath()
        path.moveToPoint(topRight)
        path.lineToPoint(bottomLeft)
        NSColor.redColor().setStroke()
        path.stroke()
    })
}

/// Returns a swatch image for the multiple color case.
private func multipleColorSwatchImage() -> Image {
    return colorSwatchImage(Color.white, f: { rect in
        NSColor.redColor().setStroke()
        NSBezierPath.strokeLineFromPoint(NSMakePoint(rect.minX + 4, rect.midY), toPoint: NSMakePoint(rect.maxX - 4, rect.midY))
    })
}

/// Returns a color swatch image.
private func colorSwatchImage(color: Color, f: ((NSRect) -> ())? = nil) -> Image {
    let size = NSMakeSize(20, 12)
    let rect = NSRect(origin: NSZeroPoint, size: size)
    let image = NSImage(size: size)
    image.lockFocusFlipped(false)
    drawSwatch(rect, color: color.nscolor)
    f?(rect)
    NSColor.blackColor().setStroke()
    NSBezierPath.strokeRect(rect.insetBy(dx: 0.5, dy: 0.5))
    image.unlockFocus()
    return Image(image)
}

/// Draws a color swatch into the current graphics context.
private func drawSwatch(rect: NSRect, color: NSColor) {
    NSColor.blackColor().setFill()
    NSRectFill(rect)
    
    let path = NSBezierPath()
    path.moveToPoint(NSMakePoint(rect.minX, rect.minY))
    path.lineToPoint(NSMakePoint(rect.maxX, rect.minY))
    path.lineToPoint(NSMakePoint(rect.maxX, rect.maxY))
    path.closePath()
    NSColor.whiteColor().setFill()
    path.fill()
    
    color.setFill()
    NSRectFillUsingOperation(rect, .CompositeSourceOver)
}

private class OpacityFormatter: NSNumberFormatter {
    
    override init() {
        super.init()
        
        numberStyle = .PercentStyle
        minimum = 0.0
        maximum = 1.0
        maximumFractionDigits = 0
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func getObjectValue(obj: AutoreleasingUnsafeMutablePointer<AnyObject?>, forString string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>) -> Bool {
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
        return super.getObjectValue(obj, forString: s, errorDescription: error)
    }
    
    override func isPartialStringValid(partialString: String, newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>) -> Bool {
        var s = partialString
        
        if s.isEmpty {
            return true
        }
        
        if s.hasSuffix("%") {
            s = s[s.startIndex..<s.endIndex.predecessor()]
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
