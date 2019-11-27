Requirements:

1. A text field at top-left that allows the user to enter new to-do items.  When the user types a
non-empty string, a new pending item should be added at the top of the list, and the text field
should be cleared.

2. A list view on the left side that contains all to-do items.  The list should be sorted such
that the first part of the list contains pending items, and the second part contains completed
items.  Pending items should be sorted with most recently added items at top.  Completed items
should be sorted with most recently completed at top.

3. Each list cell will have a checkbox on the left side indicating whether the item is pending
(unchecked) or completed (checked).  If the user clicks the checkbox such that it becomes checked,
the item should animate down the list to sit at the top of the completed section.  If the user
clicks the checkbox such that it becomes unchecked, the item should animate to the top of the list.

4. Each list cell will have the to-do item title to the right of the checkbox.  The user should
be able to change the title by clicking in the list cell's text field.  The title field should
be updated if the user changes it in the detail view, and vice versa.

5. Each list cell will have a read-only label containing applied tags on the right side.  The
tags should be comma-separated and in alphabetical order.  The label should be updated whenever
the user adds or removes a tag for that item in the detail view.

6. A detail view on the right side that allows the user to change information about the to-do
item that is currently selected in the list.  If there is no selection, the detail view should
be hidden and replaced by a gray "No Selection" label.

7. A checkbox at the top-left of the detail view.  This should reflect whether the selected
to-do item is pending (unchecked) or completed (checked).  The behavior of this checkbox is the
same as described in (3), except that it controls the selected items position in the list.

8. A text field to the right of the checkbox in the detail view.  This should reflect the title
of the selected to-do item.  If the user changes the title in the detail view and presses enter,
the title should also be updated in the selected list cell.

9. A combo box with placeholder "Assign a tag".  The pull-down menu should include a list of
available tags (all tags that haven't yet been applied; if a tag *has* been applied it should not
appear in the menu).  The user can also type in an existing tag or new tag.  If the user clicks
or enters a tag, that tag should be added to the set of applied tags for the selected to-do item.

10. A list of tags that have been applied to the selected to-do item.

11. A text view that allows the user to type in notes about the selected to-do item.

12. A read-only label that shows when the selected to-do item was created, e.g.
"Created on Sep 1, 2017".

13. A delete button.  If the user clicks this button, the selected item should be deleted
(removed from the list entirely) and the list selection should be cleared (no item selected).

14. Every single change made by the user (including selection changes, because why not?)
should be undoable/redoable.

15. Changes should be written out to disk automatically so that the user can close the app,
reopen it later, and see everything in its previous state.
