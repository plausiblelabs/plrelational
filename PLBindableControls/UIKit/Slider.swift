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
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.addTarget(self, action: #selector(updatedState(_:)), for: .valueChanged)
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.addTarget(self, action: #selector(updatedState(_:)), for: .valueChanged)
    }
    
    func updatedState(_ sender: Slider) {
        // TODO
    }
}
