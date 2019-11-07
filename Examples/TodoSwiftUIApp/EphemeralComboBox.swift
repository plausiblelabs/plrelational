//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import AppKit
import Combine
import SwiftUI
import PLRelational

struct ComboBoxItem: Identifiable {
    let id: RelationValue
    let string: String
}

/// A combo box control that clears the text field whenever an item is selected or new text
/// is committed.  This class is not generic and currently only supports string values.
struct EphemeralComboBox: NSViewRepresentable {

    let placeholder: String
    @Binding var items: [ComboBoxItem]
    
    var onCommitString: (String) -> Void = { _ in }
    var onItemSelected: (ComboBoxItem) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox(frame: .zero)
        comboBox.placeholderString = self.placeholder
        comboBox.delegate = context.coordinator
        comboBox.target = context.coordinator
        comboBox.action = #selector(Coordinator.stringCommitted(_:))
        return comboBox
    }
    
    func updateNSView(_ view: NSComboBox, context: Context) {
//        print("UPDATING COMBO")
        view.removeAllItems()
        view.addItems(withObjectValues: items.map{ $0.string })
    }
}

#if DEBUG
struct EphemeralComboBox_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            EphemeralComboBox(placeholder: "Placeholder", items: .constant([
                ComboBoxItem(id: 1, string: "hello"),
                ComboBoxItem(id: 2, string: "world")
            ]))
        }
            .padding()
            .previewLayout(.fixed(width: 200, height: 100))
    }
}
#endif

extension EphemeralComboBox {
    
    class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: EphemeralComboBox

        private var poppedUp = false

        init(_ parent: EphemeralComboBox) {
            self.parent = parent
        }
    
        @objc open func comboBoxWillPopUp(_ notification: Notification) {
            poppedUp = true
        }
    
        @objc open func comboBoxWillDismiss(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else {
                return
            }
            
            if poppedUp && comboBox.indexOfSelectedItem >= 0 {
                // An item was selected by clicking a popup item or by pressing enter after the item
                // was highlighted.  We immediately notify and deselect the item to prevent it from
                // appearing in the text field.
                notifyItemSelected(comboBox: comboBox, index: comboBox.indexOfSelectedItem)
            }
            poppedUp = false
        }
    
        private func notifyItemSelected(comboBox: NSComboBox, index: Int) {
            let item = parent.items[index]
            parent.onItemSelected(item)
            // TODO: Hrm, the following two lines seem to have no effect
            comboBox.stringValue = ""
            comboBox.deselectItem(at: index)
//            print("DESELECT: \(comboBox.indexOfSelectedItem) \(comboBox.stringValue)")
        }
    
        @objc func stringCommitted(_ sender: NSComboBox) {
            if sender.stringValue.isEmpty {
                // Nothing to do when the string is empty
                return
            }

            // Send the committed string value
            parent.onCommitString(sender.stringValue)
            
            // Clear the text field
            if sender.indexOfSelectedItem >= 0 {
                sender.deselectItem(at: sender.indexOfSelectedItem)
            }
            sender.stringValue = ""
        }
    }
}
