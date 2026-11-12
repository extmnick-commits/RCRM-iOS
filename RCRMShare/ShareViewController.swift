import Contacts
import SwiftUI
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let view = ShareScreen(context: extensionContext) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

private struct ShareScreen: View {
    let context: NSExtensionContext?
    let finish: () -> Void
    @State private var status = "Reading shared contact…"
    @State private var saved = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: failed ? "exclamationmark.circle" : (saved ? "checkmark.circle" : "person.crop.circle"))
                    .font(.largeTitle).foregroundStyle(failed ? .orange : .cyan)
                Text(status).multilineTextAlignment(.center)
                if saved { Text("Open RCRM to import this contact.").foregroundStyle(.secondary).multilineTextAlignment(.center) }
                if saved || failed { Button("Done", action: finish).buttonStyle(.borderedProminent) }
                else { ProgressView() }
            }
            .padding()
            .navigationTitle("Share to RCRM")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: finish) } }
        }
        .task { await receive() }
    }

    @MainActor private func receive() async {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.vCard.identifier) }) else {
            failed = true
            status = "This item does not contain a supported contact card. Try Share Contact from the call details."
            return
        }
        do {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.vCard.identifier)
            let data: Data
            if let value = item as? Data { data = value }
            else if let url = item as? URL { data = try Data(contentsOf: url) }
            else { throw CocoaError(.fileReadUnknown) }
            let contacts = try CNContactVCardSerialization.contacts(with: data)
            let contact = contacts.first { !$0.phoneNumbers.isEmpty }
            guard let contact else {
                failed = true
                status = "The shared contact has no phone number. Make sure the phone field is included when sharing."
                return
            }
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            let payload = SharedContactItem(
                id: UUID().uuidString,
                name: name,
                phones: contact.phoneNumbers.map { $0.value.stringValue },
                email: contact.emailAddresses.first.map { $0.value as String } ?? "",
                company: contact.organizationName,
                jobTitle: contact.jobTitle,
                phoneLabels: contact.phoneNumbers.map { number in
                    guard let label = number.label, !label.isEmpty else { return "Phone" }
                    return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: label)
                }
            )
            try SharedContactInbox.add(payload)
            status = "Contact ready to import"
            saved = true
        } catch {
            failed = true
            status = "Could not save the shared contact. Please try again."
        }
    }
}
