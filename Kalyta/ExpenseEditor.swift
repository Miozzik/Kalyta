import AVFoundation
import SwiftData
import SwiftUI
import VisionKit

/// The sheet for entering a new expense or editing a saved one.
///
/// The fields edit copies of the expense's values, which are written back only on
/// Save. Binding them to the model directly would let autosave persist every
/// keystroke, and Cancel could not discard the changes.
struct ExpenseEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// The expense being edited, or `nil` when entering a new one.
    ///
    /// A scanned receipt can switch a new entry to the expense it matches.
    @State private var expense: Expense?
    /// Whether the sheet was opened for a new entry; only then does a scan look for a match.
    private let isNew: Bool
    /// The time of the expense a scanned receipt matched, shown so a wrong match is noticed.
    @State private var matchedDate: Date?
    /// Set by "Save as New" so a repeated scan does not match again.
    @State private var savesAsNew = false
    /// The category and note a scan's match replaced, put back when the match is dropped.
    @State private var fieldsBeforeMatch: (category: ExpenseCategory?, note: String)?
    @State private var isScanning = false
    @State private var isNotFiscal = false
    @State private var isCameraDenied = false
    /// Deletes the edited expense through the list's deferred deletion, so the undo banner appears.
    private let onDelete: ((Expense) -> Void)?
    /// Whether the scanner opens as soon as the sheet appears.
    private let startsScanning: Bool

    @Query(sort: \ExpenseCategory.sortOrder) private var categories: [ExpenseCategory]
    @State private var amount: Double?
    /// The picked category, or `nil` until one is picked for a new expense.
    @State private var category: ExpenseCategory?
    @State private var isCreatingCategory = false
    /// Whether the entry is income; the grid then offers income categories only.
    @State private var isIncome: Bool
    @State private var note: String
    @State private var date: Date
    @FocusState private var isAmountFocused: Bool

    /// Creates the sheet for a new expense, or for editing `expense`.
    ///
    /// - Parameters:
    ///   - expense: The expense to edit, or `nil` to enter a new one.
    ///   - onDelete: Called with the edited expense when the person taps Delete.
    ///   - startsScanning: Whether to open the receipt scanner at once, as a shortcut or widget asks.
    init(expense: Expense? = nil, onDelete: ((Expense) -> Void)? = nil, startsScanning: Bool = false) {
        _expense = State(initialValue: expense)
        isNew = expense == nil
        self.onDelete = onDelete
        self.startsScanning = startsScanning
        _amount = State(initialValue: expense?.amount)
        _category = State(initialValue: expense?.assignedCategory)
        _isIncome = State(initialValue: expense?.isIncome ?? false)
        _note = State(initialValue: expense?.note ?? "")
        _date = State(initialValue: expense?.date ?? .now)
    }

    private var canSave: Bool { amount.map(isValidAmount) == true && category != nil }

    /// The categories offered in the grid: visible ones, plus the current one even if hidden,
    /// so editing an old expense never silently changes its category.
    private var pickableCategories: [ExpenseCategory] {
        categories.filter { $0.isIncome == isIncome && (!$0.isHidden || $0 == category) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("Kind", selection: $isIncome) {
                        Text("Expense").tag(false)
                        Text("Income").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 8)
                    .onChange(of: isIncome) {
                        if category?.isIncome != isIncome { category = pickableCategories.first }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                            .multilineTextAlignment(.trailing)
                            .fixedSize()
                            .accessibilityIdentifier("amountField")
                        Text(verbatim: "₴").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    if canScan && !isIncome { scanControls }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(pickableCategories) { item in
                            Button {
                                category = item
                            } label: {
                                CategoryChip(
                                    title: item.title, icon: item.icon, color: item.color, isSelected: item == category)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(item == category ? .isSelected : [])
                        }
                        Button {
                            isCreatingCategory = true
                        } label: {
                            CategoryChip(
                                title: String(localized: "New"), icon: "plus", color: .secondary, isSelected: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New Category")
                    }

                    VStack(spacing: 0) {
                        TextField("Note", text: $note)
                            .textFieldStyle(.plain)
                            .padding(14)
                        Divider().padding(.leading, 14)
                        // People record money already spent; a future date would inflate the current period.
                        DatePicker(
                            "Date", selection: $date, in: ...Date.now, displayedComponents: [.date, .hourAndMinute]
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))

                    if let expense, let onDelete {
                        Button("Delete Expense", role: .destructive) {
                            onDelete(expense)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    }
                }
                .padding(.horizontal)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(expense == nil ? "New Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if category == nil { category = pickableCategories.first }
                if startsScanning && canScan {
                    startScan()
                } else {
                    isAmountFocused = expense == nil
                }
            }
            .fullScreenCover(isPresented: $isScanning) { scanner }
            .sheet(isPresented: $isCreatingCategory) {
                CategoryEditor(isIncome: isIncome) { created in category = created }
            }
        }
    }

    /// Whether the device can scan receipts; the button is hidden rather than left doing nothing.
    private var canScan: Bool {
        #if DEBUG
            if scanPayloadArgument != nil { return true }
        #endif
        return DataScannerViewController.isSupported
    }

    #if DEBUG
        /// A payload given with `-scanPayload <text>`, fed to ``scan(_:)`` instead of the camera,
        /// so UI tests on the simulator (which has no scanner) exercise the same path.
        private var scanPayloadArgument: String? { UserDefaults.standard.string(forKey: "scanPayload") }
        /// How many times Scan Receipt was tapped; `-scanPayload "A|B"` feeds A, then B, then A again.
        @State private var scanCount = 0
    #endif

    /// The Scan Receipt button, and a way to Settings when camera access is off.
    private var scanControls: some View {
        VStack(spacing: 8) {
            Button("Scan Receipt", systemImage: "qrcode.viewfinder", action: startScan)
                .buttonStyle(.bordered)
            if isCameraDenied {
                Text("Camera access is off")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                    .font(.footnote)
            }
            if let matchedDate {
                // Naming the matched entry lets a wrong match be noticed without opening it.
                let time = matchedDate.formatted(.dateTime.hour().minute())
                let matchedNote = expense?.note.trimmingCharacters(in: .whitespaces) ?? ""
                Group {
                    if matchedNote.isEmpty {
                        Text("Matches the entry recorded at \(time)")
                    } else {
                        Text("Matches “\(matchedNote)”, recorded at \(time)")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("receiptMatch")
                Button("Save as New") {
                    expense = nil
                    self.matchedDate = nil
                    savesAsNew = true
                    restoreFieldsBeforeMatch()
                }
                .font(.footnote)
            }
        }
    }

    /// The full-screen camera, showing a hint while it sees a code that is not a receipt.
    private var scanner: some View {
        NavigationStack {
            ReceiptScannerView { payload in isNotFiscal = !scan(payload) }
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    if isNotFiscal {
                        Text("Not a fiscal receipt")
                            .padding()
                            .background(.regularMaterial, in: .capsule)
                            .padding(.bottom, 40)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isScanning = false }
                    }
                }
        }
        .onDisappear { isNotFiscal = false }
    }

    /// Opens the camera, asking for access first; manual entry stays available whatever the answer.
    private func startScan() {
        #if DEBUG
            if let scanPayloadArgument {
                let payloads = scanPayloadArgument.split(separator: "|", omittingEmptySubsequences: false).map(
                    String.init)
                _ = scan(payloads[scanCount % payloads.count])
                scanCount += 1
                return
            }
        #endif
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isScanning = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                isScanning = granted
                isCameraDenied = !granted
            }
        default:
            isCameraDenied = true
        }
    }

    /// Fills the fields from a scanned receipt, switching a new entry to the expense it matches.
    ///
    /// - Parameter payload: The text of the scanned code.
    /// - Returns: `false` if the code is not a fiscal receipt, so scanning goes on.
    private func scan(_ payload: String) -> Bool {
        guard let receipt = FiscalReceipt(payload: payload) else { return false }
        isScanning = false
        // The keyboard would cover the note and date the scan filled in.
        isAmountFocused = false
        isIncome = false
        amount = receipt.amount
        date = receipt.date
        // Matched again on every scan, so scanning a different receipt drops a match that no longer fits.
        if isNew && !savesAsNew {
            expense = receipt.matchingExpense(in: context)
            matchedDate = expense?.date
            if let expense {
                if fieldsBeforeMatch == nil { fieldsBeforeMatch = (category, note) }
                category = expense.assignedCategory
                note = expense.note
            } else {
                restoreFieldsBeforeMatch()
            }
        }
        return true
    }

    /// Puts back the category and note the person had before a scan matched an entry.
    private func restoreFieldsBeforeMatch() {
        guard let fields = fieldsBeforeMatch else { return }
        category = fields.category
        note = fields.note
        fieldsBeforeMatch = nil
    }

    /// Writes the fields to the edited expense, or inserts a new one, and closes the sheet.
    ///
    /// Saves at once instead of waiting for autosave, which runs later: an app killed
    /// right after Save would otherwise lose the expense.
    private func save() {
        guard let amount, isValidAmount(amount), let category else { return }
        if let expense {
            expense.amount = amount
            expense.assignedCategory = category
            expense.legacyCategory = Category(rawValue: category.key) ?? .other
            expense.note = note
            expense.date = date
            expense.isIncome = isIncome
        } else {
            context.insert(Expense(amount: amount, category: category, note: note, date: date, isIncome: isIncome))
        }
        try? context.save()
        dismiss()
    }
}

/// A tile for one category, outlined in the category color when selected.
private struct CategoryChip: View {
    let title: String
    /// The SF Symbol name.
    let icon: String
    let color: Color
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? .white : color)
                .frame(width: 48, height: 48)
                .background(isSelected ? color : color.opacity(0.15), in: .circle)
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? color : .clear, lineWidth: 2)
        }
        .animation(.snappy(duration: 0.15), value: isSelected)
    }
}
