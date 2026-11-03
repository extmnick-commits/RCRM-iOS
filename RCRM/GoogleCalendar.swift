import EventKit
import EventKitUI
import SwiftUI
import UIKit

@MainActor
final class GoogleCalendarService: ObservableObject {
    @Published private(set) var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var calendars: [AppointmentAgenda.UserCalendar] = []
    @Published private(set) var events: [AppointmentAgenda.CalendarEventRef] = []
    @Published var syncNotice: String?
    @Published var hideDuplicateHolidays: Bool
    @Published var visibleCalendarIDs: Set<String>?
    @Published var defaultCalendarID: String?
    @Published private(set) var localEventKeys: [String: String]

    private var store = EKEventStore()
    private let defaults = UserDefaults.standard
    private let filterSetKey = "rcrm_google_calendar.filter_set"
    private let visibleKey = "rcrm_google_calendar.visible_ids"
    private let defaultKey = "rcrm_google_calendar.default_id"
    private let hideDupKey = "rcrm_google_calendar.hide_duplicates"
    private let linksKey = "rcrm_google_calendar.event_links"
    private var loadedMonthStart: Int64?
    private var eventsByKey: [String: EKEvent] = [:]

    var hasAccess: Bool { access == .fullAccess }

    var hasGoogleAccount: Bool {
        calendars.contains(where: Self.isGoogleAccount)
    }

    static func isGoogleAccount(_ calendar: AppointmentAgenda.UserCalendar) -> Bool {
        let account = calendar.accountName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if account.contains("google") || account.contains("gmail") { return true }
        return false
    }

    var needsGoogleLink: Bool { !hasAccess || !hasGoogleAccount }

    init() {
        hideDuplicateHolidays = defaults.object(forKey: hideDupKey) as? Bool ?? true
        if defaults.bool(forKey: filterSetKey) {
            visibleCalendarIDs = Set(defaults.stringArray(forKey: visibleKey) ?? [])
        } else {
            visibleCalendarIDs = nil
        }
        defaultCalendarID = defaults.string(forKey: defaultKey)
        localEventKeys = defaults.dictionary(forKey: linksKey) as? [String: String] ?? [:]
        access = EKEventStore.authorizationStatus(for: .event)
    }

    func prepare(monthStartMillis: Int64) async {
        access = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else { return }
        reloadCalendars()
        await load(monthStartMillis: monthStartMillis)
    }

    func requestAccess(monthStartMillis: Int64) async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            syncNotice = error.localizedDescription
        }
        access = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else {
            if access == .denied || access == .restricted {
                syncNotice = "Calendar access is off. Turn it on in Settings to show Google Calendar events."
            }
            return
        }
        // A store created before the user allowed access keeps returning an empty calendar list.
        store = EKEventStore()
        reloadCalendars()
        await load(monthStartMillis: monthStartMillis)
    }

    func load(monthStartMillis: Int64) async {
        access = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else {
            events = []
            eventsByKey = [:]
            return
        }
        loadedMonthStart = monthStartMillis
        reloadCalendars()
        let monthStart = AppointmentAgenda.startOfMonthContaining(monthStartMillis)
        let monthEnd = AppointmentAgenda.shiftMonth(monthStart, delta: 1)
        let today = AppointmentAgenda.startOfDay(Int64(Date().timeIntervalSince1970 * 1000))
        let startMillis = min(monthStart, today)
        let endMillis = max(monthEnd, today + 2 * 24 * 60 * 60 * 1000)
        let selected = selectedCalendars()
        let start = Date(timeIntervalSince1970: Double(startMillis) / 1000)
        let end = Date(timeIntervalSince1970: Double(endMillis) / 1000)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected.isEmpty ? nil : selected)
        let fetched = store.events(matching: predicate)
        var mapped: [AppointmentAgenda.CalendarEventRef] = []
        var lookup: [String: EKEvent] = [:]
        for event in fetched {
            guard let ref = makeRef(event) else { continue }
            mapped.append(ref)
            lookup[ref.eventKey] = event
        }
        let deduped = AppointmentAgenda.dedupeEvents(mapped, calendars: calendars)
        events = deduped
        eventsByKey = lookup.filter { key, _ in deduped.contains { $0.eventKey == key } }
    }

    func setCalendarVisible(_ id: String, visible: Bool) {
        var ids = visibleCalendarIDs ?? Set(calendars.map(\.id))
        if visible { ids.insert(id) } else { ids.remove(id) }
        visibleCalendarIDs = ids
        defaults.set(true, forKey: filterSetKey)
        defaults.set(Array(ids), forKey: visibleKey)
        Task { await reloadLoadedMonth() }
    }

    func setDefaultCalendar(_ id: String) {
        guard calendars.contains(where: { $0.id == id && $0.canWrite }) else { return }
        defaultCalendarID = id
        defaults.set(id, forKey: defaultKey)
    }

    func setHideDuplicateHolidays(_ enabled: Bool) {
        hideDuplicateHolidays = enabled
        defaults.set(enabled, forKey: hideDupKey)
        Task { await reloadLoadedMonth() }
    }

    func event(for item: AppointmentAgenda.AgendaItem) -> EKEvent? {
        if let key = item.calendarEventKey, let cached = eventsByKey[key] { return cached }
        if let key = item.calendarEventKey, let direct = store.event(withIdentifier: key) { return direct }
        return nil
    }

    func syncAppointment(
        leadId: String,
        leadName: String,
        phone: String,
        appointmentId: String,
        start: Date,
        location: String?,
        notes: String,
        soleAppointment: Bool
    ) async -> String? {
        access = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else {
            return "Saved in RCRM. Allow calendar access to add it to Google Calendar."
        }
        let startMillis = Int64(start.timeIntervalSince1970 * 1000)
        let pool = events(around: startMillis)
        let refs = pool.compactMap(makeRef)
        let preferred = localEventKeys[appointmentId]
        let targetKey = AppointmentAgenda.selectRetryTarget(
            candidates: refs,
            appointmentId: appointmentId,
            leadId: leadId,
            preferredEventKey: preferred,
            soleAppointmentForLead: soleAppointment
        )
        if let targetKey, let existing = pool.first(where: { Self.eventKey(for: $0) == targetKey }) ?? store.event(withIdentifier: targetKey) {
            return update(existing, leadId: leadId, leadName: leadName, phone: phone, appointmentId: appointmentId, start: start, location: location, notes: notes, soleAppointment: soleAppointment)
        }
        return insert(leadId: leadId, leadName: leadName, phone: phone, appointmentId: appointmentId, start: start, location: location, notes: notes)
    }

    func cancelAppointment(leadId: String, appointmentId: String, soleAppointment: Bool) async -> String? {
        access = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else {
            return "Appointment canceled in RCRM. Allow calendar access, then cancel the calendar event."
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let pool = events(around: now)
        let refs = pool.compactMap(makeRef)
        guard let targetKey = AppointmentAgenda.selectRetryTarget(
            candidates: refs,
            appointmentId: appointmentId,
            leadId: leadId,
            preferredEventKey: localEventKeys[appointmentId],
            soleAppointmentForLead: soleAppointment
        ), let existing = pool.first(where: { Self.eventKey(for: $0) == targetKey }) ?? store.event(withIdentifier: targetKey) else {
            forgetLink(appointmentId)
            return nil
        }
        if existing.hasRecurrenceRules && existing.occurrenceDate == nil {
            return "This event repeats. Cancel that occurrence in Calendar so the rest of the series is left alone."
        }
        guard existing.calendar.allowsContentModifications else {
            return "That calendar is read-only. The RCRM appointment was canceled, and the calendar event was left unchanged."
        }
        do {
            try store.remove(existing, span: .thisEvent, commit: true)
            forgetLink(appointmentId)
            await reloadLoadedMonth()
            return nil
        } catch {
            return "Couldn't remove the calendar event."
        }
    }

    func stampExistingEvent(
        item: AppointmentAgenda.AgendaItem,
        leadId: String,
        leadName: String,
        phone: String,
        appointmentId: String
    ) -> String? {
        guard hasAccess, let key = item.calendarEventKey, let event = event(for: item) ?? eventsByKey[key] else {
            return "That calendar event is no longer on this iPhone."
        }
        guard event.calendar.allowsContentModifications else {
            return "That calendar is read-only, so RCRM left the event unchanged."
        }
        if event.hasRecurrenceRules && event.occurrenceDate == nil {
            return "This event repeats. Link that occurrence from Calendar so the rest of the series is left alone."
        }
        event.notes = AppointmentAgenda.mergeDescription(
            existing: event.notes,
            leadName: leadName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Lead" : leadName,
            phone: phone,
            location: item.location,
            leadId: leadId,
            appointmentId: appointmentId,
            notes: nil
        )
        if event.location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let location = item.location, !location.isEmpty {
            event.location = location
        }
        do {
            try store.save(event, span: .thisEvent, commit: true)
            remember(appointmentId: appointmentId, event: event)
            return nil
        } catch {
            return "Couldn't update the calendar event."
        }
    }

    private func insert(
        leadId: String,
        leadName: String,
        phone: String,
        appointmentId: String,
        start: Date,
        location: String?,
        notes: String
    ) -> String? {
        guard let calendar = writableCalendar() else {
            return "No writable calendar is available for this appointment."
        }
        let safeName = leadName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Lead" : leadName.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = "Appointment: \(safeName)"
        event.startDate = start
        event.endDate = start.addingTimeInterval(60 * 60)
        event.timeZone = .current
        event.location = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = AppointmentAgenda.crmDescription(
            leadName: safeName,
            phone: phone,
            location: location,
            leadId: leadId,
            appointmentId: appointmentId,
            notes: notes
        )
        event.addAlarm(EKAlarm(relativeOffset: -15 * 60))
        do {
            try store.save(event, span: .thisEvent, commit: true)
            remember(appointmentId: appointmentId, event: event)
            Task { await reloadLoadedMonth() }
            return nil
        } catch {
            return "Couldn't add the appointment to Google Calendar."
        }
    }

    private func update(
        _ event: EKEvent,
        leadId: String,
        leadName: String,
        phone: String,
        appointmentId: String,
        start: Date,
        location: String?,
        notes: String,
        soleAppointment: Bool
    ) -> String? {
        let recurringMaster = event.hasRecurrenceRules && event.occurrenceDate == nil
        guard AppointmentAgenda.eventIdentityAllows(
            eventLeadId: AppointmentAgenda.extractLeadId(event.notes),
            eventAppointmentId: AppointmentAgenda.extractAppointmentId(event.notes),
            expectedLeadId: leadId,
            expectedAppointmentId: appointmentId,
            soleAppointmentForLead: soleAppointment,
            recurringMaster: recurringMaster
        ) else {
            return insert(leadId: leadId, leadName: leadName, phone: phone, appointmentId: appointmentId, start: start, location: location, notes: notes)
        }
        if recurringMaster {
            return "This event repeats. Change that occurrence in Calendar so the rest of the series is left alone."
        }
        guard event.calendar.allowsContentModifications else {
            return "That calendar is read-only. The RCRM appointment was saved, and the calendar event was left unchanged."
        }
        let safeName = leadName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Lead" : leadName.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = AppointmentAgenda.mergeDescription(
            existing: event.notes,
            leadName: safeName,
            phone: phone,
            location: location,
            leadId: leadId,
            appointmentId: appointmentId,
            notes: notes
        )
        event.location = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        event.startDate = start
        event.endDate = start.addingTimeInterval(60 * 60)
        event.timeZone = .current
        event.alarms?.forEach { event.removeAlarm($0) }
        event.addAlarm(EKAlarm(relativeOffset: -15 * 60))
        do {
            try store.save(event, span: .thisEvent, commit: true)
            remember(appointmentId: appointmentId, event: event)
            Task { await reloadLoadedMonth() }
            return nil
        } catch {
            return "Couldn't update the calendar event."
        }
    }

    private func reloadLoadedMonth() async {
        guard let loadedMonthStart else { return }
        await load(monthStartMillis: loadedMonthStart)
    }

    private func reloadCalendars() {
        calendars = store.calendars(for: .event).map { calendar in
            AppointmentAgenda.UserCalendar(
                id: calendar.calendarIdentifier,
                displayName: calendar.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Calendar" : calendar.title,
                accountName: calendar.source.title,
                canWrite: calendar.allowsContentModifications,
                isPrimary: calendar.calendarIdentifier == store.defaultCalendarForNewEvents?.calendarIdentifier,
                colorHex: Self.hex(calendar.cgColor)
            )
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        if let google = calendars.first(where: { $0.canWrite && Self.isGoogleAccount($0) }) {
            let currentIsGoogle = calendars.contains { $0.id == defaultCalendarID && Self.isGoogleAccount($0) }
            if !currentIsGoogle {
                setDefaultCalendar(google.id)
            }
        }
    }

    private func selectedCalendars() -> [EKCalendar] {
        let hidden = hideDuplicateHolidays ? AppointmentAgenda.redundantReadOnlyCalendarIds(calendars) : []
        let allowed = calendars.filter { calendar in
            if hidden.contains(calendar.id) { return false }
            if let visibleCalendarIDs { return visibleCalendarIDs.contains(calendar.id) }
            return true
        }.map(\.id)
        return store.calendars(for: .event).filter { allowed.contains($0.calendarIdentifier) }
    }

    private func writableCalendar() -> EKCalendar? {
        let writable = store.calendars(for: .event).filter(\.allowsContentModifications)
        if let defaultCalendarID, let match = writable.first(where: { $0.calendarIdentifier == defaultCalendarID }) {
            return match
        }
        let google = writable.filter { calendar in
            let source = calendar.source.title
            return source.localizedCaseInsensitiveContains("google") || source.localizedCaseInsensitiveContains("gmail")
        }
        if let googleCalendar = google.first(where: { $0.calendarIdentifier == store.defaultCalendarForNewEvents?.calendarIdentifier }) ?? google.first {
            return googleCalendar
        }
        return store.defaultCalendarForNewEvents ?? writable.first
    }

    private func events(around millis: Int64) -> [EKEvent] {
        let start = Date(timeIntervalSince1970: Double(millis) / 1000 - 180 * 24 * 60 * 60)
        let end = Date(timeIntervalSince1970: Double(millis) / 1000 + 180 * 24 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
    }

    private func makeRef(_ event: EKEvent) -> AppointmentAgenda.CalendarEventRef? {
        guard let start = event.startDate else { return nil }
        let startMillis = Int64(start.timeIntervalSince1970 * 1000)
        guard startMillis > 0 else { return nil }
        let endMillis = Int64((event.endDate ?? start.addingTimeInterval(60 * 60)).timeIntervalSince1970 * 1000)
        let calendar = event.calendar
        return AppointmentAgenda.CalendarEventRef(
            eventKey: Self.eventKey(for: event),
            title: event.title ?? "",
            startMillis: startMillis,
            endMillis: endMillis > startMillis ? endMillis : startMillis + 60 * 60 * 1000,
            allDay: event.isAllDay,
            calendarId: calendar?.calendarIdentifier ?? "",
            calendarDisplayName: calendar?.title ?? "",
            accountName: calendar?.source.title ?? "",
            canWrite: calendar?.allowsContentModifications ?? false,
            recurring: event.hasRecurrenceRules || event.occurrenceDate != nil,
            originalInstanceTime: event.occurrenceDate.map { Int64($0.timeIntervalSince1970 * 1000) },
            explicitLeadId: AppointmentAgenda.extractLeadId(event.notes),
            explicitAppointmentId: AppointmentAgenda.extractAppointmentId(event.notes),
            canceled: event.status == .canceled,
            location: event.location,
            notes: event.notes ?? "",
            colorHex: Self.hex(calendar?.cgColor)
        )
    }

    private func remember(appointmentId: String, event: EKEvent) {
        let key = event.eventIdentifier ?? Self.eventKey(for: event)
        guard !appointmentId.isEmpty, !key.isEmpty else { return }
        localEventKeys[appointmentId] = key
        defaults.set(localEventKeys, forKey: linksKey)
    }

    private func forgetLink(_ appointmentId: String) {
        localEventKeys.removeValue(forKey: appointmentId)
        defaults.set(localEventKeys, forKey: linksKey)
    }

    private static func eventKey(for event: EKEvent) -> String {
        let base = event.eventIdentifier ?? event.calendarItemExternalIdentifier ?? "local-event"
        if event.hasRecurrenceRules || event.occurrenceDate != nil {
            let start = Int64((event.startDate ?? Date()).timeIntervalSince1970 * 1000)
            return "\(base)@\(start)"
        }
        return base
    }

    private static func hex(_ color: CGColor?) -> Int {
        guard let color, let components = color.components, components.count >= 3 else { return 0x4C8DFF }
        let red = Int((components[0] * 255).rounded())
        let green = Int((components[1] * 255).rounded())
        let blue = Int((components[2] * 255).rounded())
        return (red << 16) | (green << 8) | blue
    }
}

struct CalendarSettingsSheet: View {
    @ObservedObject var calendar: GoogleCalendarService
    let monthStartMillis: Int64
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackgroundView()
                List {
                    Section {
                        if calendar.hasGoogleAccount {
                            Label("Google Calendar is linked", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.neonGreen)
                        } else if calendar.hasAccess {
                            Text("Calendar access is on, but this iPhone has not given RCRM a Google calendar. The accounts RCRM can see are listed below. The Google Calendar app does not share its events until the Google account is added in Settings.")
                                .font(.footnote)
                                .foregroundStyle(Color.textSecondary)
                            Text("Settings → Calendar → Accounts → Add Account → Google. Then return here.")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Button("Open Settings") { openCalendarAccounts() }
                            Text("In Settings, go back, then open Calendar → Accounts → Add Account → Google. RCRM will link it when you return.")
                                .font(.footnote)
                                .foregroundStyle(Color.textSecondary)
                        } else {
                            Button {
                                Task { await calendar.requestAccess(monthStartMillis: monthStartMillis) }
                            } label: {
                                Label("Link Google Calendar", systemImage: "link")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.neonCyan)
                            .foregroundStyle(.black)
                        }
                    }.listRowBackground(Color.glassPanel)

                    Section("Access") {
                        if calendar.hasAccess {
                            Label("Calendar access is on", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.neonGreen)
                        } else {
                            Text("Calendar access is not on yet. Tap Link Google Calendar above.")
                                .foregroundStyle(Color.textSecondary)
                            if calendar.access == .denied || calendar.access == .restricted {
                                Button("Open Settings") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                }
                            }
                        }
                    }.listRowBackground(Color.glassPanel)

                    if calendar.hasAccess {
                        Section("New appointments") {
                            if writable.isEmpty {
                                Text("No writable calendar is on this iPhone yet.")
                                    .foregroundStyle(Color.textSecondary)
                            } else {
                                Picker("Save to", selection: Binding(
                                    get: { calendar.defaultCalendarID ?? writable.first?.id ?? "" },
                                    set: { calendar.setDefaultCalendar($0) }
                                )) {
                                    ForEach(writable) { item in
                                        Text(pickerTitle(item)).tag(item.id)
                                    }
                                }
                            }
                        }.listRowBackground(Color.glassPanel)

                        Section("Show on the agenda") {
                            Toggle("Hide duplicate holiday calendars", isOn: Binding(
                                get: { calendar.hideDuplicateHolidays },
                                set: { calendar.setHideDuplicateHolidays($0) }
                            ))
                            if calendar.calendars.isEmpty {
                                Text("No calendars found.")
                                    .foregroundStyle(Color.textSecondary)
                            }
                            ForEach(calendar.calendars) { item in
                                Toggle(isOn: Binding(
                                    get: { calendar.visibleCalendarIDs?.contains(item.id) ?? true },
                                    set: { calendar.setCalendarVisible(item.id, visible: $0) }
                                )) {
                                    HStack(spacing: 10) {
                                        Circle().fill(Color.calendarTint(item.colorHex)).frame(width: 10, height: 10)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.displayName)
                                            if !item.accountName.isEmpty {
                                                Text(item.accountName).font(.caption).foregroundStyle(Color.textSecondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }.listRowBackground(Color.glassPanel)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Google Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                Task { await calendar.prepare(monthStartMillis: monthStartMillis) }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.neonCyan)
    }

    private var writable: [AppointmentAgenda.UserCalendar] {
        calendar.calendars.filter(\.canWrite)
    }

    private func pickerTitle(_ item: AppointmentAgenda.UserCalendar) -> String {
        item.accountName.isEmpty ? item.displayName : "\(item.displayName) · \(item.accountName)"
    }

    private func openCalendarAccounts() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

struct LinkGoogleCalendarButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Link Google Calendar", systemImage: "link")
                .bold()
                .frame(maxWidth: .infinity)
                .padding()
        }
        .background(Color.neonCyan, in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.black)
    }
}

struct LinkCalendarEventSheet: View {
    let item: AppointmentAgenda.AgendaItem
    let userID: String
    @ObservedObject var calendar: GoogleCalendarService
    @EnvironmentObject private var store: LeadsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLeadID = ""
    @State private var creating = false
    @State private var name = ""
    @State private var phone = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    Text(item.title).font(.headline)
                    Text(item.startDate.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(Color.textSecondary)
                }.listRowBackground(Color.glassPanel)
                Section {
                    Picker("Mode", selection: $creating) {
                        Text("Existing contact").tag(false)
                        Text("New contact").tag(true)
                    }.pickerStyle(.segmented)
                }.listRowBackground(Color.clear)
                if creating {
                    Section("New contact") {
                        TextField("Name", text: $name)
                        TextField("Phone", text: $phone).keyboardType(.phonePad)
                    }.listRowBackground(Color.glassPanel)
                } else {
                    Section("Contact") {
                        Picker("Contact", selection: $selectedLeadID) {
                            Text("Select a contact").tag("")
                            ForEach(store.leads) { lead in
                                Text(lead.name).tag(lead.id)
                            }
                        }
                    }.listRowBackground(Color.glassPanel)
                }
                if let error {
                    Section { Text(error).foregroundStyle(Color.neonPink) }.listRowBackground(Color.glassPanel)
                }
            }
            .scrollContentBackground(.hidden)
            .background { SpaceBackgroundView() }
            .navigationTitle("Link to RCRM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Link") { link() }
                        .disabled(saving || (!creating && selectedLeadID.isEmpty) || (creating && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            .onAppear {
                if selectedLeadID.isEmpty {
                    selectedLeadID = item.suggestedLeadId ?? store.leads.first?.id ?? ""
                }
                if name.isEmpty { name = item.title.replacingOccurrences(of: "Appointment: ", with: "") }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.neonCyan)
    }

    private func link() {
        guard !saving else { return }
        saving = true
        error = nil
        Task {
            do {
                let leadId: String
                let leadName: String
                let leadPhone: String
                if creating {
                    var lead = Lead()
                    lead.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    lead.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
                    leadId = try await store.createLead(lead, userID: userID)
                    leadName = lead.name
                    leadPhone = lead.phone
                } else {
                    guard let lead = store.leads.first(where: { $0.id == selectedLeadID }) else {
                        error = "Choose a contact."
                        saving = false
                        return
                    }
                    leadId = lead.id
                    leadName = lead.name
                    leadPhone = lead.phone
                }
                let appointmentID = AppointmentAgenda.newAppointmentId()
                if let stampError = calendar.stampExistingEvent(item: item, leadId: leadId, leadName: leadName, phone: leadPhone, appointmentId: appointmentID) {
                    error = stampError
                    saving = false
                    return
                }
                _ = try await store.saveAppointment(
                    leadID: leadId,
                    userID: userID,
                    appointmentID: appointmentID,
                    startDate: item.startDate,
                    location: item.location,
                    note: "",
                    scheduleReminder: true
                )
                if let month = calendarMonth { await calendar.load(monthStartMillis: month) }
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }

    private var calendarMonth: Int64? {
        AppointmentAgenda.startOfMonthContaining(item.startMillis)
    }
}

struct CalendarEventPreview: UIViewControllerRepresentable {
    let event: EKEvent
    var onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = EKEventViewController()
        controller.event = event
        controller.allowsEditing = event.calendar.allowsContentModifications
        controller.allowsCalendarPreview = true
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, EKEventViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
            onDone()
        }
    }
}
