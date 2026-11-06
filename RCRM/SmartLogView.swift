import SwiftUI

struct SmartLogPresentation: Identifiable {
    let id = UUID()
    var initialContact: ImportedContact?
    var openContactPickerOnAppear = false
}

struct SmartLogView: View {
    let userID: String
    var initialContact: ImportedContact? = nil
    var initialPhone: String = ""
    var openContactPickerOnAppear = false
    var onDismiss: () -> Void = {}

    @EnvironmentObject private var store: LeadsStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    // Contact Profile fields
    @State private var name: String
    @State private var phone: String
    @State private var email: String
    @State private var company: String
    @State private var jobTitle: String
    @State private var address: String
    @State private var category: String = "Prospect"
    @State private var quickNote: String = ""
    @State private var didImportFromAddressBook = false

    // Follow-up and Reminder
    @State private var selectedPreset: SmartLogPlanner.SmartPreset? = .todayPreset
    @State private var followUpDate: Date? = SmartLogPlanner.presetFollowUpDate(preset: .todayPreset)
    @State private var actionType: ActionType = .call
    @State private var actionTitle: String = "Call"
    @State private var showingCustomDatePicker = false

    // Intro SMS
    @State private var introSmsText: String
    @State private var userEditedSms = false

    init(
        userID: String,
        initialContact: ImportedContact? = nil,
        initialPhone: String = "",
        openContactPickerOnAppear: Bool = false,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.userID = userID
        self.initialContact = initialContact
        self.initialPhone = initialPhone
        self.openContactPickerOnAppear = openContactPickerOnAppear
        self.onDismiss = onDismiss

        let contact = initialContact
        let resolvedName = contact?.fullName ?? ""
        let resolvedPhone = contact?.phone ?? initialPhone
        _name = State(initialValue: resolvedName)
        _phone = State(initialValue: resolvedPhone)
        _email = State(initialValue: contact?.email ?? "")
        _company = State(initialValue: contact?.company ?? "")
        _jobTitle = State(initialValue: contact?.jobTitle ?? "")
        _address = State(initialValue: contact?.address ?? "")
        _introSmsText = State(initialValue: SmartLogPlanner.renderIntroSms(template: nil, contactName: resolvedName))
        _didImportFromAddressBook = State(initialValue: contact != nil)
    }

    // Contact Picker
    @State private var showingContactPicker = false

    // Saving state
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    private var matchedExistingLead: Lead? {
        let contact = ImportedContact(
            givenName: "",
            familyName: "",
            fullName: name,
            phone: phone,
            email: email
        )
        return ContactSyncService.leadAlreadyExists(contact, in: store.leads)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackgroundView()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header / Badge
                        if didImportFromAddressBook {
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundStyle(Color.neonGreen)
                                Text("Imported from Apple Contacts. Add notes, follow-up, and category, then save.")
                                    .font(.footnote)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.neonGreen.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.neonGreen.opacity(0.45), lineWidth: 1))
                        }

                        HStack {
                            Label("Quick Smart Log", systemImage: "sparkles")
                                .font(.title3.bold())
                                .foregroundStyle(Color.neonCyan)
                            Spacer()
                            Button {
                                showingContactPicker = true
                            } label: {
                                Label("Import Contact", systemImage: "person.crop.circle.badge.plus")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.neonCyan)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.neonCyan.opacity(0.12), in: Capsule())
                                    .overlay(Capsule().stroke(Color.neonCyan.opacity(0.6), lineWidth: 1))
                            }
                            .accessibilityIdentifier("import-contact-button")
                            .accessibilityLabel("Import Contact")
                        }

                        // Matched Contact Banner if already in CRM
                        if let matched = matchedExistingLead {
                            HStack(spacing: 12) {
                                Image(systemName: "person.text.rectangle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.neonOrange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Existing Contact Matched")
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.neonOrange)
                                    Text("\(matched.name) (\(matched.category))")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.textPrimary)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(Color.neonOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.neonOrange.opacity(0.5), lineWidth: 1))
                        }

                        // Contact Details Form
                        VStack(alignment: .leading, spacing: 14) {
                            Text("CONTACT DETAILS")
                                .font(.caption.bold())
                                .foregroundStyle(Color.textSecondary)

                            TextField("Full Name *", text: $name)
                                .textInputAutocapitalization(.words)
                                .padding()
                                .frostedGlass(cornerRadius: 14)

                            HStack(spacing: 10) {
                                TextField("Phone Number", text: $phone)
                                    .keyboardType(.phonePad)
                                    .padding()
                                    .frostedGlass(cornerRadius: 14)

                                TextField("Email", text: $email)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding()
                                    .frostedGlass(cornerRadius: 14)
                            }

                            HStack(spacing: 10) {
                                TextField("Company", text: $company)
                                    .padding()
                                    .frostedGlass(cornerRadius: 14)

                                TextField("Job Title", text: $jobTitle)
                                    .padding()
                                    .frostedGlass(cornerRadius: 14)
                            }

                            TextField("Address", text: $address)
                                .padding()
                                .frostedGlass(cornerRadius: 14)

                            // Category Selector
                            VStack(alignment: .leading, spacing: 8) {
                                Text("CATEGORY")
                                    .font(.caption2.bold())
                                    .foregroundStyle(Color.textSecondary)
                                HStack(spacing: 10) {
                                    categoryChip("Prospect", color: .neonCyan)
                                    categoryChip("Client", color: .neonGreen)
                                    categoryChip("Recruit", color: .neonPurple)
                                }
                            }
                        }
                        .padding(18)
                        .frostedGlass(cornerRadius: 18)

                        // Follow-up & Reminder Presets
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("FOLLOW-UP PRESET")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.textSecondary)
                                Spacer()
                                if followUpDate != nil {
                                    Button("Clear") {
                                        followUpDate = nil
                                        selectedPreset = nil
                                    }
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.neonPink)
                                }
                            }

                            if let date = followUpDate {
                                HStack(spacing: 8) {
                                    Image(systemName: "calendar.badge.clock")
                                        .foregroundStyle(Color.neonCyan)
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Color.textPrimary)
                                    Spacer()
                                    Text(selectedPreset?.label ?? "Custom")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.neonCyan)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.neonCyan.opacity(0.12), in: Capsule())
                                }
                                .padding(12)
                                .background(Color.neonCyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.neonCyan.opacity(0.4), lineWidth: 1))
                            }

                            // Preset buttons grid
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    presetButton(.todayPreset)
                                    presetButton(.tomorrowPreset)
                                }
                                HStack(spacing: 8) {
                                    presetButton(.plus1Week)
                                    presetButton(.plus2Weeks)
                                    presetButton(.plus1Month)
                                }
                                Button {
                                    showingCustomDatePicker.toggle()
                                    selectedPreset = nil
                                } label: {
                                    HStack {
                                        Image(systemName: "clock")
                                        Text(showingCustomDatePicker ? "Hide Custom Picker" : "Pick Custom Date & Time")
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.neonCyan)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.neonCyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.neonCyan.opacity(0.4), lineWidth: 1))
                                }
                            }

                            if showingCustomDatePicker {
                                DatePicker(
                                    "Follow-up Date",
                                    selection: Binding(
                                        get: { followUpDate ?? Date() },
                                        set: { followUpDate = $0 }
                                    ),
                                    in: Date()...,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .datePickerStyle(.graphical)
                                .padding()
                                .frostedGlass(cornerRadius: 14)
                            }

                            // Action Type selector
                            VStack(alignment: .leading, spacing: 8) {
                                Text("NEXT ACTION")
                                    .font(.caption2.bold())
                                    .foregroundStyle(Color.textSecondary)
                                HStack(spacing: 8) {
                                    actionTypeChip(.call, icon: "phone.fill")
                                    actionTypeChip(.message, icon: "message.fill")
                                    actionTypeChip(.meeting, icon: "person.2.fill")
                                    actionTypeChip(.toDo, icon: "checklist")
                                }
                            }
                        }
                        .padding(18)
                        .frostedGlass(cornerRadius: 18)

                        // Quick Notes
                        VStack(alignment: .leading, spacing: 10) {
                            Text("QUICK NOTE")
                                .font(.caption.bold())
                                .foregroundStyle(Color.textSecondary)
                            TextField("Add outcome note or context…", text: $quickNote, axis: .vertical)
                                .lineLimit(3...6)
                                .padding()
                                .frostedGlass(cornerRadius: 14)
                        }
                        .padding(18)
                        .frostedGlass(cornerRadius: 18)

                        IntroSmsDraftSection(
                            contactName: name,
                            phone: phone,
                            text: $introSmsText,
                            userEdited: $userEditedSms
                        )
                        .padding(18)
                        .frostedGlass(cornerRadius: 18)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Color.neonPink)
                                .padding(.horizontal)
                        }

                        // Bottom Actions: Save Lead & Save & Text
                        VStack(spacing: 12) {
                            Button {
                                Task { await saveLead(openMessages: true) }
                            } label: {
                                HStack {
                                    if isSaving {
                                        ProgressView().tint(.black)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                        Text("Save & Text Lead").bold()
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.neonGreen, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.black)
                            }
                            .disabled(isSaving || resolvedContactName().isEmpty)

                            Button {
                                Task { await saveLead(openMessages: false) }
                            } label: {
                                HStack {
                                    if isSaving {
                                        ProgressView().tint(.black)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Save Lead").bold()
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.neonCyan, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.black)
                            }
                            .accessibilityIdentifier("save-lead-button")
                            .disabled(isSaving || resolvedContactName().isEmpty)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Smart Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
            .sheet(isPresented: $showingContactPicker) {
                AppleContactPickerSheet { imported in
                    populate(from: imported)
                    showingContactPicker = false
                }
            }
            .onAppear {
                if openContactPickerOnAppear {
                    showingContactPicker = true
                }
            }
        }
    }

    private func resolvedContactName() -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let phoneTrimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phoneTrimmed.isEmpty { return phoneTrimmed }
        let companyTrimmed = company.trimmingCharacters(in: .whitespacesAndNewlines)
        if !companyTrimmed.isEmpty { return companyTrimmed }
        return ""
    }

    private func populate(from contact: ImportedContact) {
        if !contact.fullName.isEmpty { self.name = contact.fullName }
        if !contact.phone.isEmpty { self.phone = contact.phone }
        if !contact.email.isEmpty { self.email = contact.email }
        if !contact.company.isEmpty { self.company = contact.company }
        if !contact.jobTitle.isEmpty { self.jobTitle = contact.jobTitle }
        if !contact.address.isEmpty { self.address = contact.address }
        if !userEditedSms {
            self.introSmsText = SmartLogPlanner.renderIntroSms(template: nil, contactName: self.name)
        }
        didImportFromAddressBook = true
    }

    private func categoryChip(_ title: String, color: Color) -> some View {
        Button {
            category = title
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(category == title ? Color.black : color)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(category == title ? color : color.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(color.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func presetButton(_ preset: SmartLogPlanner.SmartPreset) -> some View {
        let isSelected = selectedPreset == preset
        return Button {
            selectedPreset = preset
            followUpDate = SmartLogPlanner.presetFollowUpDate(preset: preset)
            showingCustomDatePicker = false
        } label: {
            Text(preset.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.black : Color.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Color.neonCyan : Color.glassFrost, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.neonCyan : Color.glassFrost, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func actionTypeChip(_ type: ActionType, icon: String) -> some View {
        let isSelected = actionType == type
        return Button {
            actionType = type
            actionTitle = type.title
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(type.title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? Color.black : Color.neonCyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.neonCyan : Color.neonCyan.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Color.neonCyan.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func sendSms() {
        guard let url = SmartLogPlanner.messagesURL(phone: phone, body: introSmsText) else { return }
        openURL(url)
    }

    @MainActor
    private func saveLead(openMessages: Bool) async {
        let trimmedName = resolvedContactName()
        guard !trimmedName.isEmpty else {
            errorMessage = "Add a name, phone, or company before saving."
            return
        }

        isSaving = true
        errorMessage = nil

        do {
            var lead = Lead()
            lead.ownerId = userID
            lead.name = trimmedName
            lead.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
            lead.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
            lead.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
            lead.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
            lead.title = jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            lead.notes = quickNote.trimmingCharacters(in: .whitespacesAndNewlines)
            lead.category = category
            lead.followUpDate = followUpDate

            // If an existing lead was matched, update its details
            if let matched = matchedExistingLead {
                lead.id = matched.id
                var updated = matched
                if !lead.name.isEmpty { updated.name = lead.name }
                if !lead.phone.isEmpty { updated.phone = lead.phone }
                if !lead.email.isEmpty { updated.email = lead.email }
                if !lead.company.isEmpty { updated.company = lead.company }
                if !lead.title.isEmpty { updated.title = lead.title }
                if !lead.address.isEmpty { updated.address = lead.address }
                if !lead.category.isEmpty { updated.category = lead.category }
                if let followUp = followUpDate { updated.followUpDate = followUp }
                if !quickNote.isEmpty {
                    updated.notes = NoteUtils.prependNote(
                        matched.notes,
                        content: quickNote,
                        eventId: "smart_log_\(UUID().uuidString.prefix(8))",
                        date: Date()
                    )
                }
                try await store.updateLead(updated, original: matched, userID: userID)
            } else {
                _ = try await store.createLead(lead, userID: userID)
            }

            if openMessages {
                sendSms()
            }

            dismiss()
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

struct IntroSmsDraftSection: View {
    let contactName: String
    let phone: String
    @Binding var text: String
    @Binding var userEdited: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Text suggestion", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(Color.neonGreen)
                Spacer()
                Button("Reset") {
                    text = SmartLogPlanner.renderIntroSms(template: nil, contactName: contactName)
                    userEdited = false
                }
                .font(.caption.bold())
                .foregroundStyle(Color.textSecondary)
            }

            Text("Personalized intro SMS — same draft Smart Log uses. Edit before sending.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)

            TextField("SMS Message", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .padding()
                .frostedGlass(cornerRadius: 14)
                .onChange(of: text) { _, _ in
                    userEdited = true
                }

            Button {
                openDraftInMessages()
            } label: {
                Label("Open in Messages", systemImage: "arrow.up.right.square")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.neonGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.neonGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.neonGreen.opacity(0.6), lineWidth: 1))
            }
            .disabled(phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear { refreshDraftIfNeeded() }
        .onChange(of: contactName) { _, _ in refreshDraftIfNeeded() }
    }

    private func refreshDraftIfNeeded() {
        guard !userEdited else { return }
        text = SmartLogPlanner.renderIntroSms(template: nil, contactName: contactName)
    }

    private func openDraftInMessages() {
        guard let url = SmartLogPlanner.messagesURL(phone: phone, body: text) else { return }
        openURL(url)
    }
}
