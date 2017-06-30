//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import AppKit
import PLRelationalBinding

open class SegmentedControl<T: Equatable>: NSSegmentedControl {

    public struct Segment {
        public let value: T
        public let image: NSImage
        
        public init(value: T, image: NSImage) {
            self.value = value
            self.image = image
        }
    }

    private let segments: [Segment]
    
    private lazy var _selectedValue: MutableValueProperty<T?> = mutableValueProperty(nil, { [weak self] value, _ in
        self?.setSelectedValue(value)
    })
    public var selectedValue: ReadWriteProperty<T?> { return _selectedValue }

    public init(frame: NSRect, segments: [Segment]) {
        self.segments = segments
        
        super.init(frame: frame)

        // XXX: NSSegmentedControl has borders that make it annoying to determine how to wide to make the segments, so fudge it
        let width = round((frame.width - 8) / CGFloat(segments.count))

        segmentCount = segments.count
        for (index, segment) in segments.enumerated() {
            setImage(segment.image, forSegment: index)
            setWidth(width, forSegment: index)
        }
        
        target = self
        action = #selector(selectionChanged(_:))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("NSCoding not supported")
    }
    
    func selectionChanged(_ control: Any?) {
        let value: T?
        if selectedSegment >= 0 {
            value = segments[selectedSegment].value
        } else {
            value = nil
        }
        _selectedValue.change(value, transient: false)
    }
    
    private func setSelectedValue(_ value: T?) {
        if let index = segments.index(where: { $0.value == value }) {
            setSelected(true, forSegment: index)
        } else {
            for index in 0..<segments.count {
                setSelected(false, forSegment: index)
            }
        }
    }
    
    /// Convenience for binding `selectedValue` to a ReadWriteProperty<CommonValue<T>>, because models tend to use the latter.
    public func connect(_ property: ReadWriteProperty<CommonValue<T>>) {
        _ = property.connectBidi(
            self.selectedValue,
            leftToRight: { commonValue, isInitial in
                // CommonValue<T> -> T?
                .change(commonValue.orNil())
            },
            rightToLeft: { value, isInitial in
                // T? -> CommonValue<T>
                guard !isInitial else { return .noChange }
                if let value = value {
                    return .change(.one(value))
                } else {
                    return .change(.none)
                }
            }
        )
    }
}
