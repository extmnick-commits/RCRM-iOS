import Contacts
import SwiftUI

struct ImportedContact: Identifiable, Equatable, Hashable {
    let id: String
    var givenName: String
    var familyName: String
    var fullName: String
    var phone: String
    var email: String
    var company: String
    var jobTitle: String
    var address: String
    var phoneNumbers: [LabeledPhone]

    init(
        id: String = UUID().uuidString,
        givenName: String = "",
        familyName: String = "",
        fullName: String = "",
        phone: String = "",
        email: String = "",
        company: String = "",
        jobTitle: String = "",
        address: String = "",
        phoneNumbers: [LabeledPhone] = []
    ) {
        self.id = id
        self.givenName = givenName
        self.familyName = familyName
        self.fullName = fullName.isEmpty ? [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ") : fullName
        self.phone = phone
        self.email = email
        self.company = company
        self.jobTitle = jobTitle
        self.address = address
        self.phoneNumbers = phoneNumbers
    }

    init(from cnContact: CNContact) {
        self.phoneNumbers = cnContact.phoneNumbers.map { number in
            let label = number.label.map { CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0) } ?? "Phone"
            return LabeledPhone(label: label, number: number.value.stringValue)
        }
        self.id = cnContact.identifier
        self.givenName = cnContact.givenName
        self.familyName = cnContact.familyName

        let formatter = CNContactFormatter()
        let formattedName = formatter.string(from: cnContact) ?? ""
        if !formattedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.fullName = formattedName
        } else {
            self.fullName = [cnContact.givenName, cnContact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        }

        if let firstPhone = cnContact.phoneNumbers.first?.value.stringValue {
            self.phone = firstPhone
        } else {
            self.phone = ""
        }

        if let firstEmail = cnContact.emailAddresses.first?.value as String? {
            self.email = firstEmail
        } else {
            self.email = ""
        }

        self.company = cnContact.organizationName
        self.jobTitle = cnContact.jobTitle

        if let firstAddress = cnContact.postalAddresses.first?.value {
            self.address = ContactSyncService.formatPostalAddress(firstAddress)
        } else {
            self.address = ""
        }

        if self.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !self.company.isEmpty {
                self.fullName = self.company
            } else if !self.phone.isEmpty {
                self.fullName = self.phone
            }
        }
    }

    var firstName: String {
        if !givenName.isEmpty { return givenName }
        return SmartLogPlanner.formatFirstName(from: fullName)
    }

    func toLead(ownerId: String) -> Lead {
        var lead = Lead()
        lead.ownerId = ownerId
        lead.name = fullName.isEmpty ? "Unknown Contact" : fullName
        lead.phone = phone
        lead.additionalPhoneNumbers = phoneNumbers
        lead.email = email
        lead.address = address
        lead.company = company
        lead.title = jobTitle
        lead.category = "Prospect"
        return lead
    }
}

enum ContactSyncService {
    static let store = CNContactStore()

    private static let contactDetailKeys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactJobTitleKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor
    ]

    static var contactPickerDisplayKeys: [String] {
        [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactOrganizationNameKey,
            CNContactJobTitleKey,
            CNContactPostalAddressesKey
        ]
    }

    static func importedContact(from picked: CNContact) -> ImportedContact {
        if let hydrated = try? store.unifiedContact(withIdentifier: picked.identifier, keysToFetch: contactDetailKeys) {
            return ImportedContact(from: hydrated)
        }
        return ImportedContact(from: picked)
    }

    static func checkAuthorizationStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    static func isContactsAccessGranted(_ status: CNAuthorizationStatus = checkAuthorizationStatus()) -> Bool {
        if status == .authorized { return true }
        if #available(iOS 18.0, *), status == .limited { return true }
        return false
    }

    static func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            return granted || isContactsAccessGranted()
        } catch {
            return isContactsAccessGranted()
        }
    }

    static func formatPostalAddress(_ address: CNPostalAddress) -> String {
        let parts = [
            address.street,
            address.city,
            address.state,
            address.postalCode
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.joined(separator: ", ")
    }

    static func fetchContacts(matching query: String? = nil) async throws -> [ImportedContact] {
        if !isContactsAccessGranted() {
            let granted = await requestAccess()
            guard granted else { return [] }
        }

        let keysToFetch = contactDetailKeys

        var results: [ImportedContact] = []
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmedQuery.isEmpty {
            let predicate = CNContact.predicateForContacts(matchingName: trimmedQuery)
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            results = contacts.map(ImportedContact.init(from:))
        } else {
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            request.sortOrder = .userDefault
            try store.enumerateContacts(with: request) { contact, _ in
                results.append(ImportedContact(from: contact))
            }
        }

        return results
    }

    static func leadAlreadyExists(_ contact: ImportedContact, in leads: [Lead]) -> Lead? {
        leads.first { lead in
            if !contact.phone.isEmpty && ([lead.phone] + lead.additionalPhoneNumbers.map(\.number)).contains(where: { SmartLogPlanner.phonesMatch(contact.phone, $0) }) {
                return true
            }
            if !contact.email.isEmpty && !lead.email.isEmpty &&
                contact.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ==
                lead.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                return true
            }
            let contactName = contact.fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let leadName = lead.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !contactName.isEmpty && contactName == leadName
        }
    }
}

/// In-app contact list. Apple's `CNContactPickerViewController` dismisses the Smart Log
/// sheet/cover when a contact is chosen (UIKit presentation walks up to the SwiftUI host).
struct AppleContactPickerSheet: View {
    var onSelectContact: (ImportedContact) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [ImportedContact] = []
    @State private var search = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var accessDenied = false

    private var filtered: [ImportedContact] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return contacts }
        return contacts.filter { contact in
            [contact.fullName, contact.phone, contact.email, contact.company]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackgroundView()
                content
            }
            .navigationTitle("Apple Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search contacts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadContacts() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading contacts…")
                .tint(Color.neonCyan)
                .foregroundStyle(Color.textPrimary)
        } else if accessDenied {
            ContentUnavailableView(
                "Contacts Access Needed",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("Allow Contacts in Settings so RCRM can import a name, phone, and email into Smart Log.")
            )
        } else if let errorMessage {
            ContentUnavailableView("Couldn't Load Contacts", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if filtered.isEmpty {
            ContentUnavailableView("No Contacts", systemImage: "person.crop.circle.badge.questionmark", description: Text(search.isEmpty ? "There are no contacts on this iPhone yet." : "No contacts match that search."))
        } else {
            List(filtered) { contact in
                Button {
                    onSelectContact(contact)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contact.fullName.isEmpty ? "Unnamed contact" : contact.fullName)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                        if !contact.phone.isEmpty {
                            Text(contact.phone).font(.subheadline).foregroundStyle(Color.textSecondary)
                        }
                        if !contact.email.isEmpty {
                            Text(contact.email).font(.caption).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.glassPanel)
                .accessibilityIdentifier("apple-contact-\(contact.fullName)")
            }
            .scrollContentBackground(.hidden)
        }
    }

    @MainActor
    private func loadContacts() async {
        isLoading = true
        errorMessage = nil
        accessDenied = false
        if !ContactSyncService.isContactsAccessGranted() {
            let granted = await ContactSyncService.requestAccess()
            if !granted {
                accessDenied = true
                isLoading = false
                return
            }
        }
        do {
            contacts = try await ContactSyncService.fetchContacts()
                .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
