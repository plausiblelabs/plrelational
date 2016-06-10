//
//  ColorPickerView.swift
//  Relational
//
//  Created by Chris Campbell on 6/8/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

class ColorPickerView: NSView {

    private let model: ColorPickerModel
    
    var color: BidiValueBinding<CommonValue<Color>>? {
        didSet {
            if let color = color {
                setColorBinding(color)
            }
            model.color = color
        }
    }
    
    private let colorPopup: PopUpButton<ColorItem>
    private let opacityCombo: ComboBox<CGFloat>

    private var ignorePanelUpdates = false
    
    init(defaultColor: Color) {
        self.model = ColorPickerModel(defaultColor: defaultColor)
        
        // Configure color popup button
        colorPopup = PopUpButton(frame: NSZeroRect, pullsDown: false)
        colorPopup.items = ValueBinding.constant(model.popupItems)
        colorPopup.selectedObject = model.colorItem
        
        // Configure opacity combo box
        let opacityValues: [CGFloat] = 0.stride(through: 100, by: 10).map{ CGFloat($0) / 100.0 }
        opacityCombo = ComboBox(frame: NSZeroRect)
        opacityCombo.formatter = OpacityFormatter()
        opacityCombo.items = ValueBinding.constant(opacityValues)
        opacityCombo.value = model.opacityValue
        
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
        
        model.onOther = self.onOther
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setColorBinding(binding: BidiValueBinding<CommonValue<Color>>) {
        // TODO: Perhaps defaultItemContent should be a ValueBinding so that we can move this
        // to the model
        colorPopup.defaultItemContent = MenuItemContent(
            object: ColorItem.Default,
            title: binding.map{ $0.whenMulti("Multiple", otherwise: "Default") },
            image: binding.map{ $0.whenMulti(multipleColorSwatchImage(), otherwise: unsetColorSwatchImage()) }
        )
    }
    
    /// Called when the "Other" item is selected.
    private func onOther() {
        updateColorPanel(makeVisible: true)
    }
    
    private func updateColorPanel(makeVisible makeVisible: Bool) {
        ignorePanelUpdates = true
        let colorPanel = NSColorPanel.sharedColorPanel()
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorPanelChanged(_:)))
        //colorPanel.color = color?.value.nscolor
        if makeVisible {
            colorPanel.orderFront(nil)
        }
        ignorePanelUpdates = false
    }
    
    /// Called when the color panel color has changed.
    @objc func colorPanelChanged(panel: NSColorPanel) {
        if ignorePanelUpdates {
            return
        }
        
        if let newColor = Color(panel.color) {
            // TODO: Use `update` while value is changing
            color?.commit(.One(newColor))
        }
    }
}

private enum ColorItem: Equatable { case
    Default,
    Preset(Color),
    Custom(Color),
    Other
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
    
    var color: BidiValueBinding<CommonValue<Color>>? {
        didSet {
            bindings.register("color", color, { [weak self] value in
                self?.setColorValue(value)
            })
        }
    }

    var onOther: (() -> Void)?
    
    /// The color to show in the color picker when there is no selected color.
    private let defaultColor: Color

    private let presetColors: [Color]
    private var popupItems: [MenuItem<ColorItem>]!
    
    private let colorItem: BidiValueBinding<ColorItem?>
    private let opacityValue: BidiValueBinding<CGFloat?>
    
    private var selfInitiatedColorItemChange = false
    private var selfInitiatedOpacityValueChange = false
    
    init(defaultColor: Color) {
        self.defaultColor = defaultColor
        
        // Initialize the internal bindings
        let colorItem: BidiValueBinding<ColorItem?> = bidiValueBinding(nil)
        let customColor: ValueBinding<Color?> = colorItem.map{
            switch $0 {
            case .Some(.Custom(let color)):
                return color
            default:
                return nil
            }
        }
        let colorIsCustom: ValueBinding<Bool> = customColor.map{ $0 != nil }
        self.colorItem = colorItem
        self.opacityValue = bidiValueBinding(nil)

        // Configure color popup menu items
        var popupItems: [MenuItem<ColorItem>] = []
        var presets: [Color] = []
        
        func addPreset(name: String, _ color: Color) {
            let colorItem = ColorItem.Preset(color)
            let content = MenuItemContent(
                object: colorItem,
                title: ValueBinding.constant(name),
                image: ValueBinding.constant(colorSwatchImage(color))
            )
            let menuItem = MenuItem(.Normal(content))
            popupItems.append(menuItem)
            presets.append(color)
        }
        
        func addCustom() {
            // The "Custom" item and the separator above it are only visible when a custom color is defined
            popupItems.append(MenuItem(.Separator, visible: colorIsCustom))
            let content = MenuItemContent(
                // TODO: Perhaps `object` should be a ValueBinding so that it can change if needed
                object: ColorItem.Custom(defaultColor),
                title: ValueBinding.constant("Custom"),
                image: customColor.map{ colorSwatchImage($0 ?? defaultColor) }
            )
            popupItems.append(MenuItem(.Normal(content), visible: colorIsCustom))
        }
        
        func addOther() {
            // The "Other" item and the separator above it are always visible
            popupItems.append(MenuItem(.Separator))
            let content = MenuItemContent(object: ColorItem.Other, title: ValueBinding.constant("Other…"))
            popupItems.append(MenuItem(.Momentary(content, { self.onOther?() })))
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
        
        // Configure the internal bindings
        bindings.register("colorItem", colorItem, { [weak self] value in
            Swift.print("COLOR ITEM CHANGING: \(value)")
            
            guard let weakSelf = self else { return }
            guard let newColorItem = value else { return }
            if weakSelf.selfInitiatedColorItemChange { return }
            
            let newColor: Color?
            switch newColorItem {
            case .Default:
                return
            case let .Preset(color):
                newColor = color
            case let .Custom(color):
                newColor = color
            case .Other:
                // TODO: Open NSColorPanel
                return
            }
            
            if let newColor = newColor {
                weakSelf.selfInitiatedColorItemChange = true
                // TODO: RelationBidiValueBinding doesn't notify observers in commit(),
                // so we have to manually call setColorValue() here; we should make the
                // existing behavior in RelationBidiValueBinding optional or something
                let newValue = CommonValue.One(newColor)
                weakSelf.color?.commit(newValue)
                weakSelf.setColorValue(newValue)
                weakSelf.selfInitiatedColorItemChange = false
            }
        })
        
        bindings.register("opacityValue", opacityValue, { [weak self] value in
            Swift.print("OPACITY VALUE CHANGING: \(value)")
            
            guard let weakSelf = self else { return }
            guard let newOpacity = value else { return }
            if weakSelf.selfInitiatedOpacityValueChange { return }
            
            let currentColor: Color
            if let colorValue = weakSelf.color?.value {
                currentColor = colorValue.orDefault(defaultColor)
            } else {
                currentColor = defaultColor
            }
            
            weakSelf.selfInitiatedOpacityValueChange = true
            let newValue = CommonValue.One(currentColor.withAlpha(newOpacity))
            weakSelf.color?.commit(newValue)
            weakSelf.setColorValue(newValue)
            weakSelf.selfInitiatedOpacityValueChange = false
        })
    }
    
    private func setColorValue(value: CommonValue<Color>) {
        Swift.print("COLOR CHANGING: \(value)")
        
        if !selfInitiatedColorItemChange {
            // Set the selected item in the color popup button
            let newColorItem: ColorItem?
            if let color = value.orNil() {
                if presetColors.contains(color) {
                    newColorItem = ColorItem.Preset(color)
                } else {
                    newColorItem = ColorItem.Custom(color)
                }
            } else {
                newColorItem = ColorItem.Default
            }
            Swift.print("  POKING COLOR ITEM: \(newColorItem)")
            colorItem.commit(newColorItem)
        }
        
        if !selfInitiatedOpacityValueChange {
            // Set the value in the opacity combo box
            let newOpacity = value.orNil()?.components.a
            Swift.print("  POKING OPACITY: \(newOpacity)")
            opacityValue.commit(newOpacity)
        }
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
