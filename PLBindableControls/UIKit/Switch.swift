//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelationalBinding

open class Switch: UISwitch, UITextFieldDelegate {
    
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

    private lazy var _bindable_on: ExternalValueProperty<Bool> = ExternalValueProperty(
        get: { [weak self] in
            self?.isOn ?? false
        },
        set: { [weak self] newValue, _ in
            self?.setOn(newValue, animated: false)
        },
        changeHandler: self.changeHandler
    )
    public var bindable_on: ReadWriteProperty<Bool> { return _bindable_on }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.addTarget(self, action: #selector(updatedState(_:)), for: .valueChanged)
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.addTarget(self, action: #selector(updatedState(_:)), for: .valueChanged)
    }
    
    func updatedState(_ sender: Switch) {
        _bindable_on.changed(transient: false)
    }
}
