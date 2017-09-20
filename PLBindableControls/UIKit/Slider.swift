//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelationalBinding

open class Slider: UISlider {
    
    private lazy var changeHandler: ChangeHandler = ChangeHandler(
        onLock: { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.isUserInteractionEnabled = false
        },
        onUnlock: { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.isUserInteractionEnabled = true
        }
    )
    
    private lazy var _bindable_value: ExternalValueProperty<Float> = ExternalValueProperty(
        get: { [weak self] in
            self?.value ?? 0.0
        },
        set: { [weak self] newValue, _ in
            self?.value = newValue
        },
        changeHandler: self.changeHandler
    )
    public var bindable_value: ReadWriteProperty<Float> { return _bindable_value }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.addTarget(self, action: #selector(updatedState(_:)), for: .valueChanged)
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.addTarget(self, action: #selector(updatedState(_:)), for: .valueChanged)
    }
    
    @objc func updatedState(_ sender: Slider) {
        // TODO: Use transient: true if isContinuous==true and the value is still changing?
        _bindable_value.changed(transient: false)
    }
}
