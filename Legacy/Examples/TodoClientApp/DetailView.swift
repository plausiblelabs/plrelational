//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

class DetailView: BackgroundView {
    
    @IBOutlet var view: NSView!
    @IBOutlet var checkbox: Checkbox!
    @IBOutlet var titleField: TextField!
    @IBOutlet var tagComboBox: EphemeralComboBox!
    @IBOutlet var tagsOutlineView: NSOutlineView!
    @IBOutlet var notesTextView: TextView!
    @IBOutlet var createdOnLabel: Label!
    @IBOutlet var deleteButton: Button!
    
    private var tagsListView: ListView<RowArrayElement>!
    
    private let model: DetailViewModel
    
    init(frame: NSRect, model: DetailViewModel) {
        self.model = model
        
        super.init(frame: frame)
        
        // Load the xib and bind to it
        Bundle.main.loadNibNamed(NSNib.Name("DetailView"), owner: self, topLevelObjects: nil)
        view.frame = self.bounds
        addSubview(view)
        
        // Configure the background
        self.backgroundColor = .white
        self.wantsLayer = true
        self.layer!.cornerRadius = 4

        // Make the text field resign first responder on enter
        titleField.onCommand = { command in
            if command == #selector(self.insertNewline(_:)) {
                self.window?.makeFirstResponder(nil)
                return true
            } else {
                return false
            }
        }
        
        // Add some padding to our notes text view
        notesTextView.textContainerInset = NSMakeSize(0, 4)

        // Bind to our view model
        checkbox.checkState <~> model.itemCompleted
        
        titleField.string <~> model.itemTitle
        
        tagComboBox.items <~ model.availableTags
        tagComboBox.selectedItemID ~~> model.addExistingTagToSelectedItem
        tagComboBox.committedString ~~> model.addNewTagToSelectedItem
        
        tagsListView = ListView(model: model.tagsListViewModel,
                                outlineView: tagsOutlineView)
        tagsListView.selection <~> model.selectedTagID
        tagsListView.configureCell = { view, row in
            let textField = view.textField as! TextField
            textField.string.unbindAll()
            textField.string <~> model.tagName(for: row)
        }

        notesTextView.text <~> model.itemNotes
        
        createdOnLabel.string <~ model.createdOn
        
        deleteButton.clicks ~~> model.deleteItem
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
