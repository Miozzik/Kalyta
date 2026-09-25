import SwiftUI

/// Cancel and Save for an editor sheet: system icon buttons on iOS 26, text before.
///
/// The icons leave room for a long localized title at large text sizes.
struct SheetToolbar: ToolbarContent {
    /// Whether Save is enabled.
    let canSave: Bool
    /// Closes the sheet without saving.
    let onCancel: () -> Void
    /// Saves the edits and closes the sheet.
    let onSave: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if #available(iOS 26, *) {
                Button(role: .cancel, action: onCancel).accessibilityIdentifier("cancelButton")
            } else {
                Button("Cancel", action: onCancel).accessibilityIdentifier("cancelButton")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if #available(iOS 26, *) {
                Button(role: .confirm, action: onSave)
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveButton")
            } else {
                Button("Save", action: onSave)
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("saveButton")
            }
        }
    }
}
