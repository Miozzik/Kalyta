import SwiftData
import SwiftUI

/// The Subscriptions tab: what recurring payments cost and when each is charged next.
struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subscription.name) private var subscriptions: [Subscription]
    @State private var isAdding = false
    /// The subscription open in the editor, or `nil` when none is being edited.
    @State private var editing: Subscription?
    /// The message after recording a charge, or `nil` when none is shown.
    @State private var recordedMessage: String?

    /// Subscriptions ordered by their next charge, soonest first.
    private var bySoonest: [(subscription: Subscription, next: Date)] {
        subscriptions.map { ($0, SubscriptionMath.nextCharge(firstCharge: $0.firstChargeDate, period: $0.period)) }
            .sorted { $0.next < $1.next }
    }

    var body: some View {
        NavigationStack {
            List {
                if !subscriptions.isEmpty {
                    Section {
                        LabeledContent("Per month") {
                            Text(
                                formattedHryvnias(
                                    SubscriptionMath.monthlyCost(of: subscriptions.map { ($0.amount, $0.period) }))
                            )
                            .font(.title3.bold())
                            .monospacedDigit()
                            .accessibilityIdentifier("subscriptionsMonthlyCost")
                        }
                    }
                }
                Section {
                    ForEach(bySoonest, id: \.subscription.key) { item in
                        Button {
                            editing = item.subscription
                        } label: {
                            SubscriptionRow(subscription: item.subscription, nextCharge: item.next)
                        }
                        .foregroundStyle(.primary)
                        // For tests only: VoiceOver skips the decorative icon, and identifiers are not spoken.
                        .accessibilityIdentifier(
                            item.subscription.iconData == nil ? "subscriptionRow" : "subscriptionRowWithIcon"
                        )
                        .swipeActions(edge: .leading) {
                            // Before the first charge there is nothing to record.
                            if SubscriptionMath.lastCharge(
                                firstCharge: item.subscription.firstChargeDate, period: item.subscription.period) != nil
                            {
                                Button("Record", systemImage: "checkmark.circle") { record(item.subscription) }
                                    .tint(.green)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(item.subscription) }
                        }
                    }
                }
            }
            .navigationTitle("Subscriptions")
            .toolbar {
                Button("Add Subscription", systemImage: "plus") { isAdding = true }
            }
            .overlay {
                if subscriptions.isEmpty {
                    ContentUnavailableView(
                        "No subscriptions yet", systemImage: "repeat.circle",
                        description: Text(
                            "Add what you pay for regularly to see the monthly cost and get a reminder the day before each charge."
                        ))
                }
            }
            .sheet(isPresented: $isAdding) { SubscriptionEditor() }
            .sheet(item: $editing) { SubscriptionEditor(subscription: $0) }
            .alert(
                "Recorded",
                isPresented: Binding(get: { recordedMessage != nil }, set: { if !$0 { recordedMessage = nil } }),
                presenting: recordedMessage
            ) { _ in
                Button("OK") {}
            } message: {
                Text($0)
            }
        }
    }

    /// Records the latest charge of a subscription as an expense, unless it already is.
    ///
    /// - Parameter subscription: The subscription that was charged.
    private func record(_ subscription: Subscription) {
        guard
            let date = SubscriptionMath.lastCharge(
                firstCharge: subscription.firstChargeDate, period: subscription.period)
        else { return }
        let category = Store.category(forKey: subscription.categoryKey, in: context)
        let name = subscription.name
        let sameNote = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.note == name }))) ?? []
        let charge = ExpenseRecord(
            date: date, amount: subscription.amount, categoryKey: category.key, categoryName: "", note: name)
        if SubscriptionMath.isAlreadyRecorded(charge, among: sameNote.map(ExpenseRecord.init)) {
            recordedMessage = String(
                localized: "Already recorded for \(date.formatted(date: .abbreviated, time: .omitted)).")
            return
        }
        context.insert(Expense(amount: subscription.amount, category: category, note: subscription.name, date: date))
        try? context.save()
        recordedMessage = String(
            localized:
                "\(subscription.name): \(formattedHryvnias(subscription.amount)) on \(date.formatted(date: .abbreviated, time: .omitted))"
        )
    }

    /// Deletes a subscription and its reminder.
    private func delete(_ subscription: Subscription) {
        context.delete(subscription)
        try? context.save()
        Task { await SubscriptionReminders.reschedule(from: context) }
    }
}

/// One subscription: icon, name, price and when it is charged next.
private struct SubscriptionRow: View {
    let subscription: Subscription
    let nextCharge: Date

    var body: some View {
        HStack(spacing: 12) {
            SubscriptionAvatar(subscription: subscription)
            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                // Both parts are already localized; joining them needs no catalog entry.
                Text(verbatim: "\(formattedHryvnias(subscription.amount)) · \(subscription.period.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(nextCharge, format: .relative(presentation: .named))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// The service icon, or a coloured circle with the first letter when there is no icon.
struct SubscriptionAvatar: View {
    let subscription: Subscription

    var body: some View {
        Group {
            if let data = subscription.iconData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
                    .accessibilityIdentifier("subscriptionIcon")
            } else {
                let color = (CategoryColor(rawValue: subscription.colorName) ?? .gray).color
                Text(subscription.name.first.map { String($0).uppercased() } ?? "?")
                    .font(.headline)
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(color.opacity(0.15), in: .rect(cornerRadius: 10))
                    .accessibilityIdentifier("subscriptionLetter")
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

/// The sheet for adding a subscription or editing one.
///
/// Edits copies and writes them back only on Save, like the other editors.
struct SubscriptionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subscription.name) private var subscriptions: [Subscription]
    @Query(sort: \ExpenseCategory.sortOrder) private var categories: [ExpenseCategory]

    /// The subscription being edited, or `nil` when adding one.
    private let subscription: Subscription?

    @State private var name: String
    @State private var amount: Double?
    @State private var period: BillingPeriod
    @State private var firstChargeDate: Date
    @State private var categoryKey: String

    /// Creates the sheet for a new subscription, or for editing `subscription`.
    ///
    /// - Parameter subscription: The subscription to edit, or `nil` to add one.
    init(subscription: Subscription? = nil) {
        self.subscription = subscription
        _name = State(initialValue: subscription?.name ?? "")
        _amount = State(initialValue: subscription?.amount)
        _period = State(initialValue: subscription?.period ?? .monthly)
        _firstChargeDate = State(initialValue: subscription?.firstChargeDate ?? .now)
        _categoryKey = State(initialValue: subscription?.categoryKey ?? Category.other.rawValue)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && (amount ?? 0) > 0 && (amount ?? 0).isFinite }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Service, for example Netflix", text: $name)
                        .accessibilityIdentifier("subscriptionName")
                    TextField("Amount", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("subscriptionAmount")
                    Picker("Period", selection: $period) {
                        ForEach(BillingPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("First charge", selection: $firstChargeDate, displayedComponents: .date)
                    Picker("Category", selection: $categoryKey) {
                        ForEach(categories.filter { !$0.isHidden || $0.key == categoryKey }) { item in
                            Text(item.title).tag(item.key)
                        }
                    }
                } footer: {
                    Text("The icon is looked up online by the service name, so the icon server learns that name.")
                }
                if let subscription {
                    Section {
                        Button("Delete Subscription", role: .destructive) {
                            context.delete(subscription)
                            try? context.save()
                            Task { await SubscriptionReminders.reschedule(from: context) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(subscription == nil ? "New Subscription" : "Edit Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave).fontWeight(.semibold)
                }
            }
        }
    }

    /// Writes the fields back, fetches the icon if the name changed, and updates reminders.
    private func save() {
        guard canSave, let amount else { return }
        let isFirstSubscription = subscriptions.isEmpty && subscription == nil
        let target: Subscription
        if let subscription {
            subscription.name = trimmedName
            subscription.amount = amount
            subscription.period = period
            subscription.firstChargeDate = firstChargeDate
            subscription.categoryKey = categoryKey
            target = subscription
        } else {
            target = Subscription(
                name: trimmedName, amount: amount, period: period, firstChargeDate: firstChargeDate,
                categoryKey: categoryKey)
            context.insert(target)
        }
        try? context.save()
        let context = context
        Task {
            // Ask in context, when the first subscription makes reminders meaningful.
            if isFirstSubscription { await SubscriptionReminders.requestPermission() }
            await SubscriptionIcons.refreshIcon(for: target, in: context)
            await SubscriptionReminders.reschedule(from: context)
        }
        dismiss()
    }
}
