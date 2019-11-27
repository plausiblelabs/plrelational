//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import UIKit
import PLRelationalBinding

public enum LabelText {
    case readOnly(ReadableProperty<String>)
    case asyncReadOnly(AsyncReadableProperty<String>)
    case readOnlyOpt(ReadableProperty<String?>)
    case asyncReadOnlyOpt(AsyncReadableProperty<String?>)
    case readOnlyAttributed(ReadableProperty<NSAttributedString>)
}

public class Label: UILabel {
    
    public private(set) lazy var bindable_visible: BindableProperty<Bool> = WriteOnlyProperty(set: { [weak self] value, _ in
        self?.isHidden = !value
    })
    
    public private(set) lazy var bindable_text: BindableProperty<String> = WriteOnlyProperty(set: { [weak self] value, _ in
        self?.text = value
    })
    
    public private(set) lazy var bindable_optText: BindableProperty<String?> = WriteOnlyProperty(set: { [weak self] value, _ in
        // This behavior is specific to optText: when `value` goes to nil, we keep the previous string value
        // in place.  This is mainly useful for the case where an table view cell is being deleted and the
        // relation associated with its Label is becoming empty (thus resulting in a nil string value).
        // Without this special behavior, the cell text will flash to the placeholder string as it fades out.
        if let value = value {
            self?.text = value
        }
    })
    
    public private(set) lazy var bindable_attributedText: BindableProperty<NSAttributedString> = WriteOnlyProperty(set: { [weak self] value, _ in
        self?.attributedText = value
    })
}

extension Label {
    public func bind(_ text: LabelText?) {
        if let text = text {
            switch text {
            case .readOnly(let prop):
                bindable_text <~ prop
            case .asyncReadOnly(let prop):
                bindable_text <~ prop
            case .readOnlyOpt(let prop):
                bindable_optText <~ prop
            case .asyncReadOnlyOpt(let prop):
                bindable_optText <~ prop
            case .readOnlyAttributed(let prop):
                bindable_attributedText <~ prop
            }
        }
    }
}

extension UILabel {
    public func set(_ text: LabelText?) {
        if let text = text {
            switch text {
            case .readOnly(let prop):
                self.text = prop.value
            case .asyncReadOnly(let prop):
                self.text = prop.value
            case .readOnlyOpt(let prop):
                self.text = prop.value
            case .asyncReadOnlyOpt(let prop):
                self.text = prop.value ?? nil
            case .readOnlyAttributed(let prop):
                self.attributedText = prop.value
            }
        }
    }
}
