//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import AppKit
import Combine
import SwiftUI

protocol ComboBoxItem {
    var string: String { get }
}

extension String: ComboBoxItem {
    var string: String { self }
}

/// A combo box control that clears the text field whenever an item is selected or new text
/// is committed.
struct EphemeralComboBox<Item: ComboBoxItem>: NSViewRepresentable {

    let placeholder: String
    @Binding var items: [Item]
    
    var onCommitString: (String) -> Void = { _ in }
    var onItemSelected: (Item) -> Void = { _ in }

    func makeCoordinator() -> EphemeralComboBoxCoordinator {
        Coordinator(
            onItemSelected: {
                self.onItemSelected(self.items[$0])
            },
            onCommitString: {
                self.onCommitString($0)
            }
        )
    }
    
    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox(frame: .zero)
        comboBox.placeholderString = self.placeholder
        comboBox.delegate = context.coordinator
        comboBox.target = context.coordinator
        comboBox.action = #selector(EphemeralComboBoxCoordinator.stringCommitted(_:))
        return comboBox
    }
    
    func updateNSView(_ view: NSComboBox, context: Context) {
        view.stringValue = ""
        view.removeAllItems()
        view.addItems(withObjectValues: items.map{ $0.string })
    }
}

class EphemeralComboBoxCoordinator: NSObject, NSComboBoxDelegate {
    let onItemSelected: (Int) -> Void
    let onCommitString: (String) -> Void

    private var poppedUp = false

    init(onItemSelected: @escaping (Int) -> Void, onCommitString: @escaping (String) -> Void) {
        self.onItemSelected = onItemSelected
        self.onCommitString = onCommitString
    }
    
    @objc func comboBoxWillPopUp(_ notification: Notification) {
        poppedUp = true
    }

    @objc func comboBoxWillDismiss(_ notification: Notification) {
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
        // TODO: Ideally we would deselect the item and/or clear the string
        // right away here so that it doesn't appear briefly, but that doesn't
        // seem to work, so instead we clear the string in `updateNSView`.
        // It seems NSComboBox sets the string directly on its cell behind
        // the scenes and there's no easy way to intervene :(
        onItemSelected(index)
    }

    @objc func stringCommitted(_ sender: NSComboBox) {
        if sender.stringValue.isEmpty {
            // Nothing to do when the string is empty
            return
        }

        // Send the committed string value
        onCommitString(sender.stringValue)
        
        // Clear the text field
        if sender.indexOfSelectedItem >= 0 {
            sender.deselectItem(at: sender.indexOfSelectedItem)
        }
        sender.stringValue = ""
    }
}

#if DEBUG
struct EphemeralComboBox_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            EphemeralComboBox(placeholder: "Placeholder",
                              items: .constant(["hello", "world"]))
        }
            .padding()
            .previewLayout(.fixed(width: 200, height: 100))
    }
}
#endif
