# Stage 15: UX fixes from the full-app audit

Source: the designer's audit of `main` at `482044c`, with screenshots in `designer/audit/`.
Line numbers are for `482044c`. Stage 9 will shift `ExpenseEditor.swift` and the catalog, so every change also names a code anchor to search for.
String rules: Ukrainian uses the «ти» form, the typographic apostrophe ’ (U+2019) and «» quotes.
Order (client): 1, 2, 8, 4, 5, 6, 3, 7, 9.

---

## 1. Record a subscription charge without a swipe

The only way to record a charge today is the leading swipe at `SubscriptionsView.swift:48`.

**Real fix: a Record button in the editor.** The editor gets the list's existing `record(_:)` as a closure, so no logic moves or is duplicated.

`SubscriptionsView.swift:77` (anchor `.sheet(item: $editing)`):
```swift
.sheet(item: $editing) { SubscriptionEditor(subscription: $0, onRecord: record) }
```
`SubscriptionEditor` (`:179`): add the property and an init parameter.
```swift
/// Records the latest charge; set only when editing an existing subscription.
var onRecord: ((Subscription) -> Void)? = nil
```
Place it in the `if let subscription { Section { … } }` at `:231`, above "Delete Subscription":
```swift
if let onRecord, SubscriptionMath.lastCharge(
    firstCharge: subscription.firstChargeDate, period: subscription.period) != nil
{
    Button("Record Charge", systemImage: "checkmark.circle") {
        dismiss()
        onRecord(subscription)
    }
}
```
It dismisses first, so the list's existing `recordedMessage` alert shows on the list.

**Optional: a context menu on the row** (`:57`, next to `.swipeActions(edge: .trailing)`). It mirrors both swipe actions:
```swift
.contextMenu {
    Button("Record Charge", systemImage: "checkmark.circle") { record(item.subscription) }
    Button("Delete", systemImage: "trash", role: .destructive) { delete(item.subscription) }
}
```
Put the same `lastCharge` guard around Record.

**Visible action on the row: not recommended.** It would add a second tap target inside a row that already opens the editor. A mis-tap would record money, and it clutters every row.

New strings:
- `Record Charge` | «Записати списання»

Keep `Record` («Записати») for the swipe action, or switch the swipe to "Record Charge" too so there is one term.

Verify: `SubscriptionUITests`. Open the subscription row, then check that `app.buttons["Record Charge"]` exists and that tapping it adds one expense with the subscription's note. Screenshot of the editor: the Record button is visible above Delete in light and uk.

## 2. Next charge shows "5 seconds ago"

Cause: `SubscriptionsView.swift:140` formats a date that includes a time with `.relative`. Fix: work at day granularity.

In `SubscriptionRow`:
```swift
/// The next charge by day: "Today", "Tomorrow", or the date.
private var nextChargeText: String {
    if Calendar.current.isDateInToday(nextCharge) { return String(localized: "Today") }
    if Calendar.current.isDateInTomorrow(nextCharge) { return String(localized: "Tomorrow") }
    return nextCharge.formatted(.dateTime.day().month())
}
```
Replace `:140`:
```swift
Text(nextChargeText)
```
New strings:
- `Tomorrow` | «Завтра»

`Today` / «Сьогодні» already exists.

Verify: add a subscription with its first charge today, then check `app.staticTexts["Today"]` in the row (uk: «Сьогодні»). No "seconds" or «секунд» anywhere in the tree dump.

## 8. The built-in category name looks empty

`CategoriesView.swift:106–109` shows the built-in title only as a grey placeholder.

Add a footer to that `Section`:
```swift
Section {
    TextField(namePlaceholder, text: $name)
        .accessibilityIdentifier("categoryName")
} footer: {
    if category?.isBuiltIn == true {
        Text("Leave empty to keep the built-in name.")
    }
}
```
New strings:
- `Leave empty to keep the built-in name.` | «Залиш порожнім, щоб лишилась стандартна назва.»

Verify: Settings → Categories → Food. The footer text is present in the screenshot and in the tree. A custom category shows no footer.

## 4. Sheet titles truncate: icon buttons on iOS 26

Decision: on iOS 26, use label-less `Button(role:action:)` with `.cancel` and `.confirm`. On iOS 17–25, keep the text buttons.

Apple docs, checked through the documentation JSON:
- `ButtonRole.confirm` is new in iOS 26.0.
- `Button.init(role:action:)` is new in iOS 26.0: "Creates a button that displays a default label."
- `ButtonRole.cancel` has been available since iOS 15.

So `#available(iOS 26, *)` guards the init, not the role.

There are 3 editors behind 6 sheets: `ExpenseEditor.swift:128–135`, `SubscriptionsView.swift:245–248` and `CategoriesView.swift:168–175`. Put one shared toolbar in a new file, `Kalyta/SheetToolbar.swift`, to avoid three copies:
```swift
import SwiftUI

/// Cancel and Save for an editor sheet: system icon buttons on iOS 26, text before.
struct SheetToolbar: ToolbarContent {
    let canSave: Bool
    let onCancel: () -> Void
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
```
Each editor's toolbar then becomes:
```swift
.toolbar { SheetToolbar(canSave: canSave, onCancel: { dismiss() }, onSave: save) }
```
- `SubscriptionEditor` defines `canSave` already.
- `ExpenseEditor` and `CategoryEditor` define it as well.
- If one of them has its toolbar inside `.toolbar { … }` alongside other items, add `SheetToolbar` next to them.

**UI tests.** On iOS 26+ the icon buttons carry system accessibility labels, not "Save"/"Cancel". The tests use `app.buttons["Save"]` / `["Cancel"]` 13 times (Category 4, Editing 3, Import 2, Receipt 2, Income 1, Subscription 1; counted on stage 9). Switch them to `app.buttons["saveButton"]` / `["cancelButton"]`. The tests run on the iOS 27 simulator, so without this they fail.

**Stage 9 carry-over.** Set the `Edit Expense` uk value back to «Редагування». On stage 9 it is «Редагування витрати», which truncates to «Редагу…» at AX-XXL (`audit/s9-crop.png`).

Out of scope: the full-screen scanner's Cancel (stage 9 `scanner`). It is not a sheet with a title.

Verify, on the iOS 27 simulator with uk at the default size and at AccessibilityXXL, for the 6 sheets (New/Edit Expense, New/Edit Subscription, New/Edit Category):
- The screenshot shows ✕ and ✓ glass buttons.
- The title is not truncated. The tree `StaticText` label equals the navigation bar identifier, and the crop shows no "…".
- The en title is unchanged.

The iOS 17 text fallback compiles but can't be seen without an iOS 17–25 runtime. Say so rather than claim it.

## 5. VoiceOver: icon picker and colour names

- `CategoriesView.swift:122`: delete `.accessibilityLabel(item)`. `Image(systemName:)` then gives the system's localized symbol description. The tree already shows "Food" and "Bus" for the same symbols in the rows.
- `CategoriesView.swift:141`: `.accessibilityLabel(item.rawValue)` → `.accessibilityLabel(Text(item.title))`.

`Models.swift:59` (`enum CategoryColor`), add:
```swift
/// The colour's name for VoiceOver.
var title: LocalizedStringResource {
    switch self {
    case .red: "Red"
    case .orange: "Orange"
    case .yellow: "Yellow"
    case .green: "Green"
    case .mint: "Mint"
    case .teal: "Teal"
    case .cyan: "Cyan"
    case .blue: "Blue"
    case .indigo: "Indigo"
    case .purple: "Purple"
    case .pink: "Pink"
    case .brown: "Brown"
    case .gray: "Grey"
    }
}
```
New strings (the English uses British spelling, matching the existing "Colour" key):

| en | uk |
|---|---|
| Red | Червоний |
| Orange | Помаранчевий |
| Yellow | Жовтий |
| Green | Зелений |
| Mint | М’ятний |
| Teal | Бірюзовий |
| Cyan | Блакитний |
| Blue | Синій |
| Indigo | Індиго |
| Purple | Фіолетовий |
| Pink | Рожевий |
| Brown | Коричневий |
| Grey | Сірий |

Verify with a tree dump of the category editor (en and uk):
- None of the 44 icon buttons has a label containing "." (`grep -c "label: '[a-z.]*\.[a-z.]*'"` → 0).
- The colour buttons read «Червоний»… in uk.
- Some symbols may lack a system description. List any empty labels; those need a hand-written label.

## 6. VoiceOver: donut sectors

`ContentView.swift:383` (anchor `SectorMark(angle:`):
```swift
SectorMark(angle: .value("Amount", row.total), innerRadius: .ratio(0.62), angularInset: 2)
    .foregroundStyle(row.color)
    .cornerRadius(4)
    .accessibilityLabel(row.title)
    .accessibilityValue(formattedHryvnias(row.total))
```
No new strings.

Verify: the tree for the Expenses tab shows sector elements with a label, e.g. label 'Home', value 'UAH 1,450', instead of a bare `value: 1,450`.

## 3. Summary card contrast (client: YES, card only, icon unchanged)

`ContentView.swift:368`:
```swift
LinearGradient(
    colors: [Color(red: 0.12, green: 0.45, blue: 0.51), .indigo],
    startPoint: .topLeading, endPoint: .bottomTrailing),
```
Computed WCAG contrast, white on the new start colour:
- Full white: 5.5:1.
- The 0.85-opacity texts at `:342`, `:356`, `:362`: 4.5:1.

The old start was 2.57:1 and 2.25:1. The indigo end is 5.65:1.

Fallback, if the client finds it muddy: keep `.teal` and darken only behind the text by adding this under the card content (before `.background`):
```swift
.background(
    LinearGradient(colors: [.black.opacity(0.25), .clear], startPoint: .topLeading, endPoint: .center),
    in: .rect(cornerRadius: 24))
```
This one needs a contrast re-measure.

Verify:
- Screenshot the Expenses tab in light and dark.
- Sample the background pixel under "Spent this month" and compute the contrast against white: must be ≥ 4.5:1 (script: `designer/audit` Python helper, or any WCAG checker).
- Check the app icon is unchanged (`Kalyta/AppIcon.icon` untouched).

## 7. Empty states with an action: SKIP (condition not met)

The client allowed this only if it is one line. The current `ContentUnavailableView(_:systemImage:description:)` convenience init has no `actions:` parameter. Adding a button means switching to the builder init `ContentUnavailableView { Label } description: { Text } actions: { Button }`, about 6 lines per screen (`SubscriptionsView.swift:69`, `ContentView.swift:241`). So: skip, unless the client accepts 6 lines.

## 9. XXL: the subscription row wraps with a leading "·"

`SubscriptionsView.swift:135`: replace the single `Text(verbatim:)` with:
```swift
ViewThatFits(in: .horizontal) {
    Text(verbatim: "\(formattedHryvnias(subscription.amount)) · \(subscription.period.title)")
    VStack(alignment: .leading, spacing: 0) {
        Text(verbatim: formattedHryvnias(subscription.amount))
        Text(subscription.period.title)
    }
}
.font(.caption)
.foregroundStyle(.secondary)
```
No new strings.

Verify: screenshot the Subscriptions tab at `extra-extra-large`. It shows "UAH 199" and "Monthly" on separate lines, with no line starting with "·". At the default size it is still one line.

---

## New String Catalog keys (all)

| key (en) | uk |
|---|---|
| Record Charge | Записати списання |
| Tomorrow | Завтра |
| Leave empty to keep the built-in name. | Залиш порожнім, щоб лишилась стандартна назва. |
| Red … Grey (13) | see #5 |

Changed: `Edit Expense` uk → «Редагування» (#4).

Estimate: #1 30 min, #2 15, #8 10, #4 45 (including the 13 test edits), #5 20, #6 5, #3 5, #9 10. About 2.5 h plus the verification runs.
