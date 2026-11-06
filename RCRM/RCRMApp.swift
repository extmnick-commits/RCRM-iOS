import SwiftUI
import UserNotifications
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

@main
struct RCRMApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var notifications = ReminderNotificationService.shared

    init() {
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path) {
            FirebaseApp.configure(options: options)
        }
        ReminderNotificationService.shared.installDelegate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(notifications)
                .onAppear {
                    notifications.onOpenLead = { [weak session] leadID in
                        DispatchQueue.main.async {
                            session?.pendingLeadID = leadID
                        }
                    }
                    if let queued = notifications.consumePendingLeadID() {
                        session.pendingLeadID = queued
                    }
                }
        }
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: User?
    @Published var error: String?
    @Published var isLoading = false
    @Published var pendingLeadID: String?
    @Published var pendingSmartLog = false
    @Published var pendingSmartLogImport = false
    private var authListener: AuthStateDidChangeListenerHandle?
    var isConfigured: Bool { FirebaseApp.app() != nil }

    init() {
        // App initialization configures Firebase before SwiftUI creates the state object.
        if FirebaseApp.app() != nil {
            authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
                Task { @MainActor in self?.user = user }
            }
        }
    }

    func signIn(email: String, password: String) async {
        guard isConfigured else { error = "Add a development Firebase configuration before signing in."; return }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            error = "Enter your email and password."; return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await Auth.auth().signIn(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func signUp(email: String, password: String, confirmation: String) async {
        guard isConfigured else { error = "Add a Firebase configuration before creating an account."; return }
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !password.isEmpty else { error = "Enter your email and password."; return }
        guard password.count >= 6 else { error = "Your password must be at least 6 characters."; return }
        guard password == confirmation else { error = "Passwords do not match."; return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await Auth.auth().createUser(withEmail: cleanEmail, password: password)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func signOut() {
        do { try Auth.auth().signOut(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

enum PipelineType: String, CaseIterable, Identifiable {
    case sales = "SALES", recruiting = "RECRUITING"
    var id: String { rawValue }
    var label: String { self == .sales ? "Client Sales" : "Downline Recruiting" }
}
enum SalesStage: String, CaseIterable, Identifiable {
    case newLead = "new_lead", contacted, apptSet = "appt_set", presentation, appSubmitted = "app_submitted", inForce = "in_force"
    var id: String { rawValue }
    var title: String { switch self {
    case .newLead: return "New Lead"; case .contacted: return "Contacted"; case .apptSet: return "Appointment Set"
    case .presentation: return "Kitchen Table / FNA"; case .appSubmitted: return "App Submitted"; case .inForce: return "Client / In-Force"
    } }
}
enum RecruitStage: String, CaseIterable, Identifiable {
    case prospect, invitedBop = "invited_bop", interviewed, ibaSubmitted = "iba_submitted", licensing, licensedActive = "licensed_active"
    var id: String { rawValue }
    var title: String { switch self {
    case .prospect: return "Recruit Prospect"; case .invitedBop: return "Invited to Overview"; case .interviewed: return "Interview Completed"
    case .ibaSubmitted: return "IBA Submitted"; case .licensing: return "Licensing / Fast Start"; case .licensedActive: return "Licensed & Field Trained"
    } }
}
enum ActionType: String, CaseIterable { case call = "CALL", message = "MESSAGE", meeting = "MEETING", toDo = "TO_DO", email = "EMAIL" }
enum ActionStatus: String, CaseIterable { case pending = "PENDING", completed = "COMPLETED", cancelled = "CANCELLED", paused = "PAUSED" }

enum WorkflowType: String, CaseIterable, Identifiable {
    case sales = "SALES", recruiting = "RECRUITING", general = "GENERAL"
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
enum WorkflowLifecycle: String, CaseIterable, Identifiable {
    case unchanged = "UNCHANGED", pause = "PAUSE", close = "CLOSE"
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
extension ActionType {
    var title: String {
        switch self {
        case .call: return "Call"
        case .message: return "Message"
        case .meeting: return "Meeting"
        case .toDo: return "To-do"
        case .email: return "Email"
        }
    }
}

enum AppointmentStatus: String, CaseIterable, Identifiable, Equatable, Hashable {
    case scheduled = "scheduled"
    case completed = "completed"
    case noShow = "no_show"
    case canceled = "canceled"

    static let SCHEDULED: AppointmentStatus = .scheduled
    static let COMPLETED: AppointmentStatus = .completed
    static let NO_SHOW: AppointmentStatus = .noShow
    static let CANCELED: AppointmentStatus = .canceled

    var id: String { rawValue }
}

enum AppointmentOutcome: String, CaseIterable, Identifiable, Equatable, Hashable {
    case completed = "COMPLETED"
    case noShow = "NO_SHOW"
    case canceled = "CANCELED"

    static let COMPLETED: AppointmentOutcome = .completed
    static let NO_SHOW: AppointmentOutcome = .noShow
    static let CANCELED: AppointmentOutcome = .canceled

    var id: String { rawValue }
    var label: String {
        switch self {
        case .completed: return "Completed"
        case .noShow: return "No-show"
        case .canceled: return "Canceled"
        }
    }
}

struct AppointmentRecord: Identifiable, Equatable, Hashable {
    var id: String
    var startMillis: Int64
    var location: String?
    var eventId: Int64?
    var status: AppointmentStatus
    var originalInstanceTime: Int64?
    var updatedAtMillis: Int64

    init(
        id: String,
        startMillis: Int64,
        location: String? = nil,
        eventId: Int64? = nil,
        status: AppointmentStatus = .scheduled,
        originalInstanceTime: Int64? = nil,
        updatedAtMillis: Int64 = 0
    ) {
        self.id = id
        self.startMillis = startMillis
        self.location = location
        self.eventId = eventId
        self.status = status
        self.originalInstanceTime = originalInstanceTime
        self.updatedAtMillis = updatedAtMillis
    }

    var startDate: Date { Date(timeIntervalSince1970: Double(startMillis) / 1000) }
}

struct AppointmentChoice: Identifiable, Equatable, Hashable {
    let id: String
    let label: String
    let startMillis: Int64
}

enum AppointmentAgenda {
    static let fieldAppointments = "appointments"
    static let sameInstantToleranceMs: Int64 = 60_000
    static let crmColor: Int = 0x4C8DFF
    static let upNextWindowMs: Int64 = 24 * 60 * 60 * 1000
    static let upNextGraceMs: Int64 = 10 * 60 * 1000
    static let upNextLimit: Int = 8
    private static let minuteMs: Int64 = 60_000

    typealias Status = AppointmentStatus
    typealias Outcome = AppointmentOutcome
    typealias Record = AppointmentRecord

    enum MonthWindow: String, CaseIterable, Identifiable {
        case upcoming = "UPCOMING"
        case all = "ALL"
        static let UPCOMING: MonthWindow = .upcoming
        static let ALL: MonthWindow = .all
        var id: String { rawValue }
        var label: String { self == .upcoming ? "Upcoming" : "All Month" }
    }

    enum EventSource: String, CaseIterable, Identifiable {
        case all = "ALL"
        case crmOnly = "CRM_ONLY"
        var id: String { rawValue }
        var label: String { self == .all ? "All Events" : "RCRM" }
    }

    struct DayCellModel: Identifiable, Equatable {
        let dayStartMillis: Int64
        let dayOfMonth: Int
        let dowLabel: String
        let isToday: Bool
        let selected: Bool
        var id: Int64 { dayStartMillis }
    }

    struct LegacyMirror: Equatable {
        let appointmentId: String?
        let startMillis: Int64?
        let location: String?
        let eventId: Int64?
    }

    struct SingleEditResult: Equatable {
        let records: [AppointmentRecord]
        let editedId: String?
        var keptNewer: Bool = false
    }

    struct AgendaItem: Identifiable, Equatable {
        var id: String
        var leadId: String
        var ownerId: String
        var appointmentId: String
        var leadName: String
        var phone: String
        var category: String
        var title: String
        var startMillis: Int64
        var endMillis: Int64
        var allDay: Bool = false
        var canceled: Bool = false
        var location: String?
        var eventId: Int64?
        var status: AppointmentStatus
        var originalInstanceTime: Int64?
        var updatedAtMillis: Int64
        var calendarEventKey: String?
        var calendarDisplayName: String
        var accountName: String
        var explicitCrm: Bool
        var suggestedLeadId: String?
        var canWriteCalendar: Bool
        var recurring: Bool
        var timeDrifted: Bool
        var eventDescription: String?
        var calendarColor: Int

        init(
            id: String? = nil,
            leadId: String = "",
            ownerId: String = "",
            appointmentId: String = "",
            leadName: String = "",
            phone: String = "",
            category: String = "Prospect",
            title: String = "",
            startMillis: Int64,
            endMillis: Int64? = nil,
            allDay: Bool = false,
            canceled: Bool = false,
            location: String? = nil,
            eventId: Int64? = nil,
            status: AppointmentStatus = .scheduled,
            originalInstanceTime: Int64? = nil,
            updatedAtMillis: Int64 = 0,
            calendarEventKey: String? = nil,
            calendarDisplayName: String = "",
            accountName: String = "",
            explicitCrm: Bool = true,
            suggestedLeadId: String? = nil,
            canWriteCalendar: Bool = true,
            recurring: Bool = false,
            timeDrifted: Bool = false,
            eventDescription: String? = nil,
            calendarColor: Int = 0x4C8DFF
        ) {
            let resolvedApptId = appointmentId.isEmpty ? (id ?? UUID().uuidString) : appointmentId
            self.id = id ?? (leadId.isEmpty ? resolvedApptId : "\(leadId)|\(resolvedApptId)")
            self.leadId = leadId
            self.ownerId = ownerId
            self.appointmentId = resolvedApptId
            self.leadName = leadName
            self.phone = phone
            self.category = category
            self.title = title.isEmpty ? (leadName.isEmpty ? "Appointment" : "Appointment: \(leadName)") : title
            self.startMillis = startMillis
            self.endMillis = endMillis ?? (startMillis + 60 * 60 * 1000)
            self.allDay = allDay
            self.canceled = canceled || status == .canceled
            self.location = location
            self.eventId = eventId
            self.status = status
            self.originalInstanceTime = originalInstanceTime
            self.updatedAtMillis = updatedAtMillis
            self.calendarEventKey = calendarEventKey
            self.calendarDisplayName = calendarDisplayName
            self.accountName = accountName
            self.explicitCrm = explicitCrm
            self.suggestedLeadId = suggestedLeadId
            self.canWriteCalendar = canWriteCalendar
            self.recurring = recurring
            self.timeDrifted = timeDrifted
            self.eventDescription = eventDescription
            self.calendarColor = calendarColor
        }

        var startDate: Date { Date(timeIntervalSince1970: Double(startMillis) / 1000) }
        var endDate: Date { Date(timeIntervalSince1970: Double(endMillis) / 1000) }
    }

    static func legacyAppointmentId(_ leadId: String) -> String { "legacy:\(leadId)" }
    static func newAppointmentId() -> String { UUID().uuidString }
    static func appointmentReminderKey(_ appointmentId: String) -> String { "appt:\(appointmentId)" }

    static func ownerCanEdit(ownerId: String?, currentUserId: String?) -> Bool {
        guard let current = currentUserId?.trimmingCharacters(in: .whitespacesAndNewlines), !current.isEmpty else { return false }
        guard let owner = ownerId?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty else { return true }
        return owner == current
    }

    static func sameInstant(_ left: Int64, _ right: Int64) -> Bool {
        abs(left - right) <= sameInstantToleranceMs
    }

    static func defaultEpochMillis(_ value: Any?) -> Int64? {
        if let int64 = value as? Int64 { return int64 }
        if let int = value as? Int { return Int64(int) }
        if let double = value as? Double { return Int64(double) }
        if let number = value as? NSNumber { return number.int64Value }
        if let date = value as? Date { return Int64(date.timeIntervalSince1970 * 1000) }
        if let str = value as? String, let parsed = Int64(str.trimmingCharacters(in: .whitespacesAndNewlines)) { return parsed }
        return nil
    }

    static func longOrNull(_ value: Any?) -> Int64? {
        if let int64 = value as? Int64 { return int64 }
        if let int = value as? Int { return Int64(int) }
        if let number = value as? NSNumber { return number.int64Value }
        if let str = value as? String { return Int64(str.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    static func statusOf(_ raw: String?) -> AppointmentStatus {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "completed": return .completed
        case "no_show", "noshow", "no-show": return .noShow
        case "canceled", "cancelled": return .canceled
        default: return .scheduled
        }
    }

    static func statusName(_ status: AppointmentStatus) -> String {
        switch status {
        case .scheduled: return "scheduled"
        case .completed: return "completed"
        case .noShow: return "no_show"
        case .canceled: return "canceled"
        }
    }

    static func statusLabel(_ status: AppointmentStatus?) -> String? {
        switch status {
        case nil, .scheduled: return nil
        case .completed: return "Completed"
        case .noShow: return "No-show"
        case .canceled: return "Canceled"
        }
    }

    static func normalize(_ records: [AppointmentRecord]) -> [AppointmentRecord] {
        var seen = Set<String>()
        var kept: [AppointmentRecord] = []
        kept.reserveCapacity(records.count)
        for record in records {
            let trimmedId = record.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedId.isEmpty, record.startMillis > 0 else { continue }
            if seen.insert(trimmedId).inserted {
                var clean = record
                clean.id = trimmedId
                kept.append(clean)
            }
        }
        return kept
    }

    static func parseRecords(_ raw: Any?, epochMillis: (Any?) -> Int64? = defaultEpochMillis) -> [AppointmentRecord] {
        guard let list = raw as? [Any] else { return [] }
        let records: [AppointmentRecord] = list.compactMap { entry in
            let map: [String: Any]
            if let dict = entry as? [String: Any] {
                map = dict
            } else if let nsDict = entry as? NSDictionary {
                var converted: [String: Any] = [:]
                for (k, v) in nsDict {
                    if let key = k as? String { converted[key] = v }
                }
                map = converted
            } else {
                return nil
            }
            let id = (map["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let start = epochMillis(map["startAt"]), !id.isEmpty, start > 0 else { return nil }
            let rawLocation = (map["location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let location = (rawLocation?.isEmpty == false) ? rawLocation : nil
            let eventId = longOrNull(map["eventId"]).flatMap { $0 > 0 ? $0 : nil }
            let status = statusOf(map["status"] as? String)
            let originalInstanceTime = epochMillis(map["originalInstanceTime"]).flatMap { $0 > 0 ? $0 : nil }
            let updatedAt = epochMillis(map["updatedAt"]) ?? 0
            return AppointmentRecord(
                id: id,
                startMillis: start,
                location: location,
                eventId: eventId,
                status: status,
                originalInstanceTime: originalInstanceTime,
                updatedAtMillis: updatedAt
            )
        }
        return normalize(records)
    }

    static func toFieldMaps(_ records: [AppointmentRecord]) -> [[String: Any]] {
        normalize(records).map { record in
            [
                "id": record.id,
                "startAt": record.startMillis,
                "location": record.location as Any? ?? NSNull(),
                "eventId": record.eventId as Any? ?? NSNull(),
                "status": statusName(record.status),
                "originalInstanceTime": record.originalInstanceTime as Any? ?? NSNull(),
                "updatedAt": record.updatedAtMillis
            ]
        }
    }

    static func migrateAppointments(
        leadId: String,
        existing: [AppointmentRecord],
        legacyStartMillis: Int64?,
        legacyLocation: String?,
        legacyEventId: Int64?,
        nowMillis: Int64
    ) -> [AppointmentRecord] {
        let normalized = normalize(existing)
        guard let legacyStartMillis, legacyStartMillis > 0 else { return normalized }
        let legacyId = legacyAppointmentId(leadId)
        if normalized.contains(where: { $0.id == legacyId }) { return normalized }
        if let legacyEventId, legacyEventId > 0, normalized.contains(where: { $0.eventId == legacyEventId }) {
            return normalized
        }
        if normalized.contains(where: { sameInstant($0.startMillis, legacyStartMillis) }) { return normalized }
        let trimmedLoc = legacyLocation?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized + [
            AppointmentRecord(
                id: legacyId,
                startMillis: legacyStartMillis,
                location: (trimmedLoc?.isEmpty == false) ? trimmedLoc : nil,
                eventId: legacyEventId.flatMap { $0 > 0 ? $0 : nil },
                status: .scheduled,
                originalInstanceTime: nil,
                updatedAtMillis: nowMillis
            )
        ]
    }

    static func upsertRecord(_ records: [AppointmentRecord], _ record: AppointmentRecord) -> [AppointmentRecord] {
        let trimmedId = record.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, record.startMillis > 0 else { return normalize(records) }
        var normalized = normalize(records)
        var clean = record
        clean.id = trimmedId
        if let idx = normalized.firstIndex(where: { $0.id == trimmedId }) {
            normalized[idx] = clean
            return normalized
        }
        normalized.append(clean)
        return normalized
    }

    static func addAppointment(_ records: [AppointmentRecord], _ record: AppointmentRecord) -> [AppointmentRecord] {
        upsertRecord(normalize(records), record)
    }

    static func withEventLink(_ records: [AppointmentRecord], appointmentId: String, eventId: Int64?) -> [AppointmentRecord]? {
        let trimmed = appointmentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = records.firstIndex(where: { $0.id == trimmed }) else { return nil }
        let stored = eventId.flatMap { $0 > 0 ? $0 : nil }
        if records[index].eventId == stored { return records }
        var copy = records
        copy[index].eventId = stored
        return copy
    }

    static func applyOutcome(
        _ records: [AppointmentRecord],
        appointmentId: String,
        outcome: AppointmentOutcome,
        nowMillis: Int64
    ) -> [AppointmentRecord] {
        guard let index = records.firstIndex(where: { $0.id == appointmentId }) else { return records }
        let status: AppointmentStatus
        switch outcome {
        case .completed: status = .completed
        case .noShow: status = .noShow
        case .canceled: status = .canceled
        }
        if records[index].status == status { return records }
        var copy = records
        copy[index].status = status
        copy[index].updatedAtMillis = nowMillis
        return copy
    }

    static func reschedule(
        _ records: [AppointmentRecord],
        appointmentId: String,
        newStartMillis: Int64,
        nowMillis: Int64,
        rememberInstance: Bool = false
    ) -> [AppointmentRecord] {
        guard newStartMillis > 0, let index = records.firstIndex(where: { $0.id == appointmentId }) else { return records }
        let current = records[index]
        let original = current.originalInstanceTime ?? (rememberInstance ? current.startMillis : nil)
        var copy = records
        copy[index] = AppointmentRecord(
            id: current.id,
            startMillis: newStartMillis,
            location: current.location,
            eventId: current.eventId,
            status: .scheduled,
            originalInstanceTime: original,
            updatedAtMillis: nowMillis
        )
        return copy
    }

    static func legacyMirror(_ records: [AppointmentRecord], nowMillis: Int64) -> LegacyMirror {
        let scheduled = records.filter { $0.status == .scheduled && $0.startMillis > 0 }
        let upcoming = scheduled.filter { $0.startMillis >= nowMillis }.min(by: { $0.startMillis < $1.startMillis })
        let primary = upcoming ?? scheduled.max(by: { $0.startMillis < $1.startMillis })
        return LegacyMirror(
            appointmentId: primary?.id,
            startMillis: primary?.startMillis,
            location: primary?.location,
            eventId: primary?.eventId
        )
    }

    static func describeSingleAppointmentEdit(
        leadId: String,
        existing: [AppointmentRecord],
        previousStartMillis: Int64?,
        previousLocation: String?,
        previousEventId: Int64?,
        newStartMillis: Int64?,
        newLocation: String?,
        newEventId: Int64?,
        nowMillis: Int64,
        createdId: String,
        baseUpdatedAtMillis: Int64 = .max
    ) -> SingleEditResult {
        let base = migrateAppointments(
            leadId: leadId,
            existing: existing,
            legacyStartMillis: previousStartMillis,
            legacyLocation: previousLocation,
            legacyEventId: previousEventId,
            nowMillis: nowMillis
        )
        let index = findEditedIndex(base, leadId: leadId, previousStartMillis: previousStartMillis, previousEventId: previousEventId)
        if let index, keptNewerEdit(base[index], newStartMillis: newStartMillis, newLocation: newLocation, nowMillis: nowMillis, baseUpdatedAtMillis: baseUpdatedAtMillis) {
            return SingleEditResult(records: base, editedId: base[index].id, keptNewer: true)
        }
        guard let newStartMillis, newStartMillis > 0 else {
            guard let index else { return SingleEditResult(records: base, editedId: nil) }
            let current = base[index]
            if current.status == .canceled {
                return SingleEditResult(records: base, editedId: current.id)
            }
            var copy = base
            copy[index].status = .canceled
            copy[index].updatedAtMillis = nowMillis
            return SingleEditResult(records: copy, editedId: current.id)
        }
        let cleanLoc = newLocation?.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = (cleanLoc?.isEmpty == false) ? cleanLoc : nil
        let eventId = newEventId.flatMap { $0 > 0 ? $0 : nil }
        if let index {
            let current = base[index]
            var copy = base
            copy[index] = AppointmentRecord(
                id: current.id,
                startMillis: newStartMillis,
                location: location ?? current.location,
                eventId: eventId ?? current.eventId,
                status: .scheduled,
                originalInstanceTime: current.originalInstanceTime,
                updatedAtMillis: nowMillis
            )
            return SingleEditResult(records: copy, editedId: current.id)
        }
        let trimmedCreated = createdId.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = trimmedCreated.isEmpty ? newAppointmentId() : trimmedCreated
        let created = AppointmentRecord(
            id: id,
            startMillis: newStartMillis,
            location: location,
            eventId: eventId,
            status: .scheduled,
            originalInstanceTime: nil,
            updatedAtMillis: nowMillis
        )
        return SingleEditResult(records: upsertRecord(base, created), editedId: id)
    }

    static func applySingleAppointmentEdit(
        leadId: String,
        existing: [AppointmentRecord],
        previousStartMillis: Int64?,
        previousLocation: String?,
        previousEventId: Int64?,
        newStartMillis: Int64?,
        newLocation: String?,
        newEventId: Int64?,
        nowMillis: Int64,
        createdId: String
    ) -> [AppointmentRecord] {
        describeSingleAppointmentEdit(
            leadId: leadId,
            existing: existing,
            previousStartMillis: previousStartMillis,
            previousLocation: previousLocation,
            previousEventId: previousEventId,
            newStartMillis: newStartMillis,
            newLocation: newLocation,
            newEventId: newEventId,
            nowMillis: nowMillis,
            createdId: createdId
        ).records
    }

    private static func findEditedIndex(
        _ records: [AppointmentRecord],
        leadId: String,
        previousStartMillis: Int64?,
        previousEventId: Int64?
    ) -> Int? {
        if let previousEventId, previousEventId > 0,
           let byEvent = records.firstIndex(where: { $0.eventId == previousEventId }) {
            return byEvent
        }
        if let previousStartMillis, previousStartMillis > 0,
           let byStart = records.firstIndex(where: { sameInstant($0.startMillis, previousStartMillis) }) {
            return byStart
        }
        let legacyId = legacyAppointmentId(leadId)
        if let legacy = records.firstIndex(where: { $0.id == legacyId }) {
            return legacy
        }
        let scheduledIndices = records.enumerated().compactMap { $0.element.status == .scheduled ? $0.offset : nil }
        return scheduledIndices.count == 1 ? scheduledIndices[0] : nil
    }

    private static func keptNewerEdit(
        _ current: AppointmentRecord,
        newStartMillis: Int64?,
        newLocation: String?,
        nowMillis: Int64,
        baseUpdatedAtMillis: Int64
    ) -> Bool {
        if current.updatedAtMillis <= baseUpdatedAtMillis { return false }
        if current.updatedAtMillis == nowMillis { return false }
        let clearing = newStartMillis == nil || (newStartMillis ?? 0) <= 0
        let cleanLoc = newLocation?.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = (cleanLoc?.isEmpty == false) ? cleanLoc : nil
        let startDiffers = !clearing && !sameInstant(current.startMillis, newStartMillis ?? 0)
        let locationDiffers = location != nil && location != current.location
        let clearDiffers = clearing && current.status != .canceled
        return startDiffers || locationDiffers || clearDiffers
    }

    static func digestAppointmentStarts(
        _ records: [AppointmentRecord],
        dayStart: Int64,
        dayEnd: Int64
    ) -> [Int64] {
        records
            .filter { $0.status == .scheduled && $0.startMillis >= dayStart && $0.startMillis < dayEnd }
            .map(\.startMillis)
            .sorted()
    }

    static func startOfDay(_ millis: Int64, calendar: Calendar = .current) -> Int64 {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        return Int64(calendar.startOfDay(for: date).timeIntervalSince1970 * 1000)
    }

    static func startOfMonthContaining(_ millis: Int64, calendar: Calendar = .current) -> Int64 {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        let comps = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1, hour: 0, minute: 0, second: 0))!
        return Int64(start.timeIntervalSince1970 * 1000)
    }

    static func shiftMonth(_ monthStartMillis: Int64, delta: Int, calendar: Calendar = .current) -> Int64 {
        let base = Date(timeIntervalSince1970: Double(startOfMonthContaining(monthStartMillis, calendar: calendar)) / 1000)
        let shifted = calendar.date(byAdding: .month, value: delta, to: base)!
        return startOfMonthContaining(Int64(shifted.timeIntervalSince1970 * 1000), calendar: calendar)
    }

    static func buildDayCells(
        monthStartMillis: Int64,
        todayStartMillis: Int64,
        selectedDayMillis: Int64?,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> [DayCellModel] {
        let startMillis = startOfMonthContaining(monthStartMillis, calendar: calendar)
        let startDate = Date(timeIntervalSince1970: Double(startMillis) / 1000)
        let range = calendar.range(of: .day, in: .month, for: startDate) ?? 1..<31
        let comps = calendar.dateComponents([.year, .month], from: startDate)
        let dowFormatter = DateFormatter()
        dowFormatter.locale = locale
        dowFormatter.timeZone = calendar.timeZone
        dowFormatter.dateFormat = "EEE"
        return range.compactMap { day -> DayCellModel? in
            guard let dayDate = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: day, hour: 0, minute: 0, second: 0)) else {
                return nil
            }
            let dayStart = Int64(dayDate.timeIntervalSince1970 * 1000)
            return DayCellModel(
                dayStartMillis: dayStart,
                dayOfMonth: day,
                dowLabel: dowFormatter.string(from: dayDate),
                isToday: dayStart == todayStartMillis,
                selected: dayStart == selectedDayMillis
            )
        }
    }

    static func dayStripAnchorIndex(dayStarts: [Int64], todayStart: Int64, selectedDay: Int64?) -> Int {
        guard !dayStarts.isEmpty else { return 0 }
        if let selectedDay, let selectedIndex = dayStarts.firstIndex(of: selectedDay) {
            return selectedIndex
        }
        if let todayIndex = dayStarts.firstIndex(of: todayStart) {
            return todayIndex
        }
        return 0
    }

    static func visibleItems(
        _ items: [AgendaItem],
        monthStartMillis: Int64,
        monthWindow: MonthWindow,
        selectedDayMillis: Int64?,
        todayStartMillis: Int64,
        source: EventSource = .all,
        calendar: Calendar = .current
    ) -> [AgendaItem] {
        let rangeStart = startOfMonthContaining(monthStartMillis, calendar: calendar)
        let rangeEnd = shiftMonth(rangeStart, delta: 1, calendar: calendar)
        return items
            .filter { item in
                if source == .crmOnly && !item.explicitCrm { return false }
                let anchor = item.allDay ? eventDayStart(item.startMillis, allDay: true, calendar: calendar) : item.startMillis
                return anchor >= rangeStart && anchor < rangeEnd
            }
            .filter { item in
                let day = eventDayStart(item.startMillis, allDay: item.allDay, calendar: calendar)
                if let selectedDayMillis { return day == selectedDayMillis }
                if monthWindow == .upcoming && day < todayStartMillis { return false }
                return true
            }
            .sorted {
                if $0.startMillis == $1.startMillis {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.startMillis < $1.startMillis
            }
    }

    static func durationLabel(_ minutes: Int) -> String {
        let safe = max(0, minutes)
        let hours = safe / 60
        let rest = safe % 60
        if hours == 0 { return "\(rest)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h \(rest)m"
    }

    static func isLiveNow(startMillis: Int64, endMillis: Int64, nowMillis: Int64) -> Bool {
        nowMillis >= startMillis && nowMillis <= endMillis
    }

    static func liveBadge(endMillis: Int64, nowMillis: Int64) -> String {
        let remaining = max(0, endMillis - nowMillis)
        let minutes = max(1, Int((remaining + minuteMs - 1) / minuteMs))
        let ends = minutes < 60 ? "\(minutes)m" : durationLabel(minutes)
        return "LIVE NOW • Ends in \(ends)"
    }

    static func upcomingEvents(
        _ events: [AgendaItem],
        nowMillis: Int64,
        windowMillis: Int64 = upNextWindowMs,
        graceMillis: Int64 = upNextGraceMs,
        limit: Int = upNextLimit
    ) -> [AgendaItem] {
        events
            .filter { !$0.allDay && !$0.canceled && $0.status == .scheduled && $0.endMillis > nowMillis }
            .filter { event in
                isLiveNow(startMillis: event.startMillis, endMillis: event.endMillis, nowMillis: nowMillis) ||
                    (event.startMillis >= nowMillis - graceMillis && event.startMillis < nowMillis + windowMillis)
            }
            .sorted { left, right in
                let leftLive = isLiveNow(startMillis: left.startMillis, endMillis: left.endMillis, nowMillis: nowMillis) ? 0 : 1
                let rightLive = isLiveNow(startMillis: right.startMillis, endMillis: right.endMillis, nowMillis: nowMillis) ? 0 : 1
                if leftLive != rightLive { return leftLive < rightLive }
                if left.startMillis != right.startMillis { return left.startMillis < right.startMillis }
                return left.title.lowercased() < right.title.lowercased()
            }
            .prefix(max(1, limit))
            .map { $0 }
    }

    static func pickUpNext(
        _ events: [AgendaItem],
        nowMillis: Int64,
        windowMillis: Int64 = upNextWindowMs,
        graceMillis: Int64 = upNextGraceMs
    ) -> AgendaItem? {
        upcomingEvents(events, nowMillis: nowMillis, windowMillis: windowMillis, graceMillis: graceMillis, limit: 1).first
    }

    static func countdownLabel(
        startMillis: Int64,
        nowMillis: Int64,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let diff = startMillis - nowMillis
        if diff <= 0 { return "Now" }
        let minutes = Int((diff + minuteMs - 1) / minuteMs)
        if minutes < 60 { return "In \(minutes)m" }
        if minutes < 180 { return "In \(durationLabel(minutes))" }
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "h:mm a"
        let startDate = Date(timeIntervalSince1970: Double(startMillis) / 1000)
        let time = timeFormatter.string(from: startDate)
        let day = startOfDay(startMillis, calendar: calendar)
        let today = startOfDay(nowMillis, calendar: calendar)
        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: Date(timeIntervalSince1970: Double(today) / 1000))!
        let tomorrow = startOfDay(Int64(tomorrowDate.timeIntervalSince1970 * 1000), calendar: calendar)
        if day == today { return "Today at \(time)" }
        if day == tomorrow { return "Tomorrow at \(time)" }
        let dowFormatter = DateFormatter()
        dowFormatter.locale = locale
        dowFormatter.timeZone = calendar.timeZone
        dowFormatter.dateFormat = "EEE"
        return "\(dowFormatter.string(from: startDate)) at \(time)"
    }

    static func upNextHeadline(startMillis: Int64, nowMillis: Int64, calendar: Calendar = .current) -> String {
        if startMillis <= nowMillis { return "Happening Now" }
        return startOfDay(startMillis, calendar: calendar) == startOfDay(nowMillis, calendar: calendar)
            ? "Up Next Today"
            : "Up Next Tomorrow"
    }

    static func extractMeetingOrWebUrl(location: String?, description: String? = nil) -> String? {
        let pattern = try! NSRegularExpression(pattern: #"(?i)https?://[^\s<>"']+"#)
        let hostPattern = try! NSRegularExpression(pattern: #"(?i)zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com|gotomeeting\.com"#)
        func trimUrl(_ raw: String) -> String {
            var res = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            while let last = res.last, [".", ",", ";", ")", "]", "\"", "'"].contains(String(last)) {
                res.removeLast()
            }
            return res
        }
        if let loc = location, !loc.isEmpty {
            let ns = loc as NSString
            if let match = pattern.firstMatch(in: loc, range: NSRange(location: 0, length: ns.length)) {
                let candidate = trimUrl(ns.substring(with: match.range))
                if !candidate.isEmpty { return candidate }
            }
        }
        guard let desc = description, !desc.isEmpty else { return nil }
        let ns = desc as NSString
        let urls = pattern.matches(in: desc, range: NSRange(location: 0, length: ns.length))
            .map { trimUrl(ns.substring(with: $0.range)) }
            .filter { !$0.isEmpty }
        return urls.first(where: { url in
            hostPattern.firstMatch(in: url, range: NSRange(location: 0, length: (url as NSString).length)) != nil
        }) ?? urls.first
    }

    static func locationChipLabel(location: String?, meetingUrl: String?) -> String? {
        let cleanLoc = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanUrl = meetingUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleanLoc.isEmpty || !cleanUrl.isEmpty else { return nil }
        return "📍 Location / Join"
    }

    struct UserCalendar: Equatable, Identifiable {
        var id: String
        var displayName: String
        var accountName: String
        var canWrite: Bool
        var isPrimary: Bool
        var colorHex: Int
    }

    struct CalendarEventRef: Equatable {
        var eventKey: String
        var title: String
        var startMillis: Int64
        var endMillis: Int64
        var allDay: Bool
        var calendarId: String
        var calendarDisplayName: String
        var accountName: String
        var canWrite: Bool
        var recurring: Bool
        var originalInstanceTime: Int64?
        var explicitLeadId: String?
        var explicitAppointmentId: String?
        var canceled: Bool
        var location: String?
        var notes: String
        var colorHex: Int
    }

    private static let leadLinkPattern = try! NSRegularExpression(pattern: #"rcrm://lead/(\S+)"#, options: [.caseInsensitive])
    private static let appointmentLinkPattern = try! NSRegularExpression(pattern: #"rcrm://appointment/(\S+)"#, options: [.caseInsensitive])

    static func leadId(from url: URL) -> String? {
        guard url.scheme?.caseInsensitiveCompare("rcrm") == .orderedSame else { return nil }
        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let segment: String
        if host.caseInsensitiveCompare("lead") == .orderedSame {
            segment = path
        } else if host.isEmpty {
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count >= 2, parts[0].caseInsensitiveCompare("lead") == .orderedSame else { return nil }
            segment = parts.dropFirst().joined(separator: "/")
        } else {
            return nil
        }
        guard !segment.isEmpty, segment.caseInsensitiveCompare("lead") != .orderedSame else { return nil }
        return cleanLinkToken(segment)
    }

    static func extractLeadId(_ description: String?) -> String? {
        firstLinkToken(in: description, pattern: leadLinkPattern)
    }

    static func extractAppointmentId(_ description: String?) -> String? {
        firstLinkToken(in: description, pattern: appointmentLinkPattern)
    }

    static func crmDescription(
        leadName: String,
        phone: String?,
        location: String?,
        leadId: String,
        appointmentId: String?,
        notes: String? = nil
    ) -> String {
        var lines = ["Appointment with \(leadName)"]
        if let phone = phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            lines.append("Phone: \(phone)")
        }
        if let location = location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            lines.append("Location: \(location)")
        }
        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            lines.append("")
            lines.append("Notes:")
            lines.append(notes)
        }
        lines.append("")
        lines.append("---")
        lines.append("Open Lead in RCRM: rcrm://lead/\(leadId)")
        if let appointmentId = appointmentId?.trimmingCharacters(in: .whitespacesAndNewlines), !appointmentId.isEmpty {
            lines.append("rcrm://appointment/\(appointmentId)")
        }
        return lines.joined(separator: "\n")
    }

    static func mergeDescription(
        existing: String?,
        leadName: String,
        phone: String?,
        location: String?,
        leadId: String,
        appointmentId: String?,
        notes: String? = nil
    ) -> String {
        guard let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return crmDescription(leadName: leadName, phone: phone, location: location, leadId: leadId, appointmentId: appointmentId, notes: notes)
        }
        var text = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty, !text.contains(notes) {
            text += "\n\nNotes:\n\(notes)"
        }
        if !text.contains("rcrm://lead/\(leadId)") {
            text += "\n\nOpen Lead in RCRM: rcrm://lead/\(leadId)"
        }
        if let appointmentId = appointmentId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !appointmentId.isEmpty,
           !text.contains("rcrm://appointment/\(appointmentId)") {
            text += "\nrcrm://appointment/\(appointmentId)"
        }
        return text
    }

    static func stripRcrmFooter(_ text: String?) -> String {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed == "---" { return false }
                if trimmed.lowercased().hasPrefix("rcrm://") { return false }
                if trimmed.lowercased().contains("rcrm://lead/") || trimmed.lowercased().contains("rcrm://appointment/") { return false }
                if trimmed.lowercased().hasPrefix("open lead in rcrm:") { return false }
                return true
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func eventSubtitle(calendarDisplayName: String, linkedLeadName: String?) -> String {
        let calendar = calendarDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Calendar"
            : calendarDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = linkedLeadName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let linkText = link.isEmpty ? "Unlinked Event" : "Linked: \(link)"
        return "● \(calendar) • \(linkText)"
    }

    static func emptyMessage(monthWindow: MonthWindow, source: EventSource, daySelected: Bool) -> String {
        if daySelected && source == .crmOnly { return "No RCRM appointments on this day" }
        if daySelected { return "No events on this day" }
        if source == .crmOnly && monthWindow == .upcoming { return "No upcoming RCRM appointments this month." }
        if source == .crmOnly { return "No RCRM appointments this month." }
        if monthWindow == .upcoming { return "Nothing upcoming this month. Switch to All Month to see earlier days." }
        return "No appointments or calendar events this month"
    }

    static func matchEventToLeadName(_ eventTitle: String, names: [String]) -> String? {
        let title = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let lowerTitle = title.lowercased()
        let ranked = Array(Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.count >= 2 }))
            .sorted { $0.count > $1.count }
        return ranked.first { containsName(lowerTitle, $0.lowercased()) }
    }

    static func eventIdentityAllows(
        eventLeadId: String?,
        eventAppointmentId: String?,
        expectedLeadId: String,
        expectedAppointmentId: String?,
        soleAppointmentForLead: Bool,
        recurringMaster: Bool = false
    ) -> Bool {
        if recurringMaster || expectedLeadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        let eventAppointment = nonEmpty(eventAppointmentId)
        let eventLead = nonEmpty(eventLeadId)
        if let eventAppointment {
            if eventAppointment != expectedAppointmentId { return false }
            if let eventLead, eventLead != expectedLeadId { return false }
            return !(expectedAppointmentId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        if let eventLead {
            if eventLead != expectedLeadId { return false }
            if expectedAppointmentId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { return true }
            if expectedAppointmentId == legacyAppointmentId(expectedLeadId) { return true }
            return soleAppointmentForLead
        }
        return false
    }

    static func selectRetryTarget(
        candidates: [CalendarEventRef],
        appointmentId: String?,
        leadId: String,
        preferredEventKey: String?,
        soleAppointmentForLead: Bool = false
    ) -> String? {
        if let preferredEventKey, !preferredEventKey.isEmpty,
           let preferred = candidates.first(where: { $0.eventKey == preferredEventKey }),
           eventIdentityAllows(
            eventLeadId: preferred.explicitLeadId,
            eventAppointmentId: preferred.explicitAppointmentId,
            expectedLeadId: leadId,
            expectedAppointmentId: appointmentId,
            soleAppointmentForLead: soleAppointmentForLead
           ) {
            return preferred.eventKey
        }
        if let appointmentId = appointmentId?.trimmingCharacters(in: .whitespacesAndNewlines), !appointmentId.isEmpty {
            let matches = candidates.filter { event in
                event.explicitAppointmentId == appointmentId &&
                    (event.explicitLeadId?.isEmpty != false || event.explicitLeadId == leadId)
            }.map(\.eventKey)
            if let first = Array(Set(matches)).sorted().first { return first }
        }
        if !leadId.isEmpty {
            let leadMatches = Array(Set(candidates.filter { event in
                event.explicitLeadId == leadId && event.explicitAppointmentId == nil
            }.map(\.eventKey))).sorted()
            let appointmentBlank = appointmentId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            if leadMatches.count == 1 && (appointmentBlank || appointmentId == legacyAppointmentId(leadId) || soleAppointmentForLead) {
                return leadMatches[0]
            }
        }
        return nil
    }

    static func suggestedLeadIds(events: [CalendarEventRef], leads: [(id: String, name: String)]) -> [String: String] {
        var nameToId: [String: String] = [:]
        var names: [String] = []
        for lead in leads {
            let name = lead.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.lowercased()
            guard name.count >= 2, nameToId[key] == nil else { continue }
            nameToId[key] = lead.id
            names.append(name)
        }
        var suggestions: [String: String] = [:]
        for event in events {
            if event.explicitLeadId?.isEmpty == false || event.explicitAppointmentId?.isEmpty == false { continue }
            guard let matched = matchEventToLeadName(event.title, names: names) else { continue }
            if let leadId = nameToId[matched.lowercased()] {
                suggestions[event.eventKey] = leadId
            }
        }
        return suggestions
    }

    static func redundantReadOnlyCalendarIds(_ calendars: [UserCalendar]) -> Set<String> {
        var hide = Set<String>()
        let groups = Dictionary(grouping: calendars) { $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        for group in groups.values where group.count >= 2 {
            guard let keeper = group.min(by: { lhs, rhs in
                let leftRank = calendarPreferenceRank(lhs)
                let rightRank = calendarPreferenceRank(rhs)
                if leftRank != rightRank { return leftRank < rightRank }
                let leftAccount = lhs.accountName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let rightAccount = rhs.accountName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if leftAccount != rightAccount { return leftAccount < rightAccount }
                return lhs.id < rhs.id
            }) else { continue }
            let holidayGroup = keeper.displayName.localizedCaseInsensitiveContains("holiday")
            for calendar in group where calendar.id != keeper.id {
                if !calendar.canWrite || holidayGroup { hide.insert(calendar.id) }
            }
        }
        return hide
    }

    static func dedupeEvents(_ events: [CalendarEventRef], calendars: [UserCalendar]) -> [CalendarEventRef] {
        let byId = Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0) })
        let ranked = events.sorted { lhs, rhs in
            let left = calendarPreferenceRank(byId[lhs.calendarId])
            let right = calendarPreferenceRank(byId[rhs.calendarId])
            if left != right { return left < right }
            let leftAccount = (byId[lhs.calendarId]?.accountName ?? lhs.accountName).lowercased()
            let rightAccount = (byId[rhs.calendarId]?.accountName ?? rhs.accountName).lowercased()
            if leftAccount != rightAccount { return leftAccount < rightAccount }
            if lhs.calendarId != rhs.calendarId { return lhs.calendarId < rhs.calendarId }
            return lhs.eventKey < rhs.eventKey
        }
        var seen = Set<String>()
        var kept: [CalendarEventRef] = []
        for event in ranked {
            let key = "\(event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(event.startMillis)|\(event.endMillis)"
            if seen.insert(key).inserted { kept.append(event) }
        }
        return kept.sorted {
            if $0.startMillis != $1.startMillis { return $0.startMillis < $1.startMillis }
            return $0.title.lowercased() < $1.title.lowercased()
        }
    }

    static func matchAgenda(
        appointments: [AgendaItem],
        events: [CalendarEventRef],
        suggestedLeadIdsByEventKey: [String: String],
        localEventKeysByAppointmentId: [String: String]
    ) -> [AgendaItem] {
        var used = Set<Int>()
        var rows: [AgendaItem] = []
        for appointment in appointments {
            if let match = matchEventIndex(appointment, events: events, used: used, appointments: appointments, localEventKeysByAppointmentId: localEventKeysByAppointmentId) {
                used.insert(match)
                rows.append(mergedEntry(appointment, event: events[match]))
            } else {
                var crmOnly = appointment
                if crmOnly.calendarDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    crmOnly.calendarDisplayName = "RCRM"
                }
                crmOnly.explicitCrm = true
                rows.append(crmOnly)
            }
        }
        for (index, event) in events.enumerated() {
            if used.contains(index) || event.canceled { continue }
            let explicit = event.explicitLeadId?.isEmpty == false || event.explicitAppointmentId?.isEmpty == false
            let suggestion = explicit ? nil : suggestedLeadIdsByEventKey[event.eventKey]
            rows.append(eventEntry(event, suggestedLeadId: suggestion))
        }
        return rows.sorted {
            if $0.startMillis != $1.startMillis { return $0.startMillis < $1.startMillis }
            return $0.title.lowercased() < $1.title.lowercased()
        }
    }

    static func eventDayStart(_ millis: Int64, allDay: Bool, calendar: Calendar = .current) -> Int64 {
        if !allDay { return startOfDay(millis, calendar: calendar) }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        guard let local = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 0, minute: 0, second: 0)) else {
            return startOfDay(millis, calendar: calendar)
        }
        return Int64(local.timeIntervalSince1970 * 1000)
    }

    static func calendarAppURL(at millis: Int64) -> URL? {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        return URL(string: "calshow:\(date.timeIntervalSinceReferenceDate)")
    }

    private static func calendarPreferenceRank(_ calendar: UserCalendar?) -> Int {
        guard let calendar else { return 4 }
        if calendar.isPrimary && calendar.canWrite { return 0 }
        if calendar.canWrite { return 1 }
        if calendar.isPrimary { return 2 }
        return 3
    }

    private static func matchEventIndex(
        _ appointment: AgendaItem,
        events: [CalendarEventRef],
        used: Set<Int>,
        appointments: [AgendaItem],
        localEventKeysByAppointmentId: [String: String]
    ) -> Int? {
        let open = events.indices.filter { index in
            !used.contains(index) && !events[index].canceled
        }
        func pick(_ indices: [Int]) -> Int? {
            if indices.isEmpty { return nil }
            let exact = indices.filter { sameInstant(events[$0].startMillis, appointment.startMillis) }
            if exact.count == 1 { return exact[0] }
            if exact.count > 1 { return exact.min { events[$0].eventKey < events[$1].eventKey } }
            let storedInstance = appointment.originalInstanceTime
            let moved = indices.filter { index in
                let event = events[index]
                if let original = event.originalInstanceTime, sameInstant(original, appointment.startMillis) { return true }
                if let storedInstance, sameInstant(event.startMillis, storedInstance) { return true }
                return false
            }
            if moved.count == 1 { return moved[0] }
            if !moved.isEmpty { return nil }
            if indices.count == 1 { return indices[0] }
            return nil
        }
        if let hit = pick(open.filter { events[$0].explicitAppointmentId == appointment.appointmentId }) {
            return hit
        }
        if let storedKey = localEventKeysByAppointmentId[appointment.appointmentId], !storedKey.isEmpty {
            let sole = appointments.filter { $0.leadId == appointment.leadId }.count == 1
            if let hit = pick(open.filter { index in
                let event = events[index]
                guard event.eventKey == storedKey else { return false }
                return eventIdentityAllows(
                    eventLeadId: event.explicitLeadId,
                    eventAppointmentId: event.explicitAppointmentId,
                    expectedLeadId: appointment.leadId,
                    expectedAppointmentId: appointment.appointmentId,
                    soleAppointmentForLead: sole
                )
            }) {
                return hit
            }
        }
        let leadEvents = open.filter { index in
            let event = events[index]
            return event.explicitLeadId == appointment.leadId && event.explicitAppointmentId == nil
        }
        let leadAppointments = appointments.filter { $0.leadId == appointment.leadId }.count
        if leadEvents.count == 1 && leadAppointments == 1 { return leadEvents[0] }
        return nil
    }

    private static func mergedEntry(_ appointment: AgendaItem, event: CalendarEventRef) -> AgendaItem {
        var merged = appointment
        merged.title = event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? appointment.title : event.title
        merged.startMillis = event.startMillis
        merged.endMillis = event.endMillis
        merged.allDay = event.allDay
        merged.location = nonEmpty(event.location) ?? appointment.location
        merged.calendarEventKey = event.eventKey
        merged.calendarDisplayName = event.calendarDisplayName
        merged.accountName = event.accountName
        merged.explicitCrm = true
        merged.suggestedLeadId = nil
        merged.canWriteCalendar = event.canWrite
        merged.recurring = event.recurring
        merged.timeDrifted = !sameInstant(appointment.startMillis, event.startMillis)
        merged.eventDescription = event.notes
        merged.calendarColor = event.colorHex
        return merged
    }

    private static func eventEntry(_ event: CalendarEventRef, suggestedLeadId: String?) -> AgendaItem {
        let explicit = event.explicitLeadId?.isEmpty == false || event.explicitAppointmentId?.isEmpty == false
        let leadId = event.explicitLeadId ?? ""
        let appointmentId = event.explicitAppointmentId ?? ""
        return AgendaItem(
            id: "cal|\(event.eventKey)|\(event.startMillis)",
            leadId: leadId,
            appointmentId: appointmentId,
            category: "",
            title: event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(No title)" : event.title,
            startMillis: event.startMillis,
            endMillis: event.endMillis,
            allDay: event.allDay,
            location: nonEmpty(event.location),
            calendarEventKey: event.eventKey,
            calendarDisplayName: event.calendarDisplayName,
            accountName: event.accountName,
            explicitCrm: explicit,
            suggestedLeadId: explicit ? nil : suggestedLeadId,
            canWriteCalendar: event.canWrite,
            recurring: event.recurring,
            eventDescription: event.notes,
            calendarColor: event.colorHex
        )
    }

    private static func firstLinkToken(in text: String?, pattern: NSRegularExpression) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let ns = text as NSString
        guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else { return nil }
        return cleanLinkToken(ns.substring(with: match.range(at: 1)))
    }

    private static func cleanLinkToken(_ raw: String) -> String? {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let trim: Set<Character> = [".", ",", ";", ")", "]"]
        while let last = token.last, trim.contains(last) { token.removeLast() }
        return token.isEmpty ? nil : token
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func containsName(_ lowerTitle: String, _ lowerName: String) -> Bool {
        guard !lowerName.isEmpty else { return false }
        var from = lowerTitle.startIndex
        while let range = lowerTitle.range(of: lowerName, range: from..<lowerTitle.endIndex) {
            let beforeOK = range.lowerBound == lowerTitle.startIndex || !lowerTitle[lowerTitle.index(before: range.lowerBound)].isLetter && !lowerTitle[lowerTitle.index(before: range.lowerBound)].isNumber
            let afterOK = range.upperBound == lowerTitle.endIndex || !lowerTitle[range.upperBound].isLetter && !lowerTitle[range.upperBound].isNumber
            if beforeOK && afterOK { return true }
            from = lowerTitle.index(after: range.lowerBound)
        }
        return false
    }
}

enum AppointmentSync {
    enum AppointmentMutation: Equatable {
        case saveOutcome(appointmentId: String, outcome: AppointmentOutcome, nowMillis: Int64, baseUpdatedAtMillis: Int64)
        case reschedule(appointmentId: String, newStartMillis: Int64, nowMillis: Int64, rememberInstance: Bool, baseUpdatedAtMillis: Int64)
        case upsert(record: AppointmentRecord, baseUpdatedAtMillis: Int64)
        case setEventId(appointmentId: String, eventId: Int64?)
        case migrate(legacyStartMillis: Int64?, legacyLocation: String?, legacyEventId: Int64?, nowMillis: Int64)
        case singleEdit(
            previousStartMillis: Int64?,
            previousLocation: String?,
            previousEventId: Int64?,
            newStartMillis: Int64?,
            newLocation: String?,
            newEventId: Int64?,
            nowMillis: Int64,
            createdId: String,
            baseUpdatedAtMillis: Int64
        )
    }

    struct MutationResult: Equatable {
        let records: [AppointmentRecord]
        let changed: Bool
        let targetId: String?
        var keptNewer: Bool = false
    }

    static func applyAppointmentMutation(
        leadId: String,
        fresh: [AppointmentRecord],
        mutation: AppointmentMutation
    ) -> MutationResult {
        switch mutation {
        case let .saveOutcome(appointmentId, outcome, nowMillis, baseUpdatedAtMillis):
            guard let existing = fresh.first(where: { $0.id == appointmentId }) else {
                return MutationResult(records: fresh, changed: false, targetId: nil)
            }
            let desired = statusFor(outcome)
            if existing.status == desired {
                return MutationResult(records: fresh, changed: false, targetId: existing.id)
            }
            if baseUpdatedAtMillis > 0 && existing.updatedAtMillis > baseUpdatedAtMillis {
                return MutationResult(records: fresh, changed: false, targetId: existing.id, keptNewer: true)
            }
            let next = AppointmentAgenda.applyOutcome(fresh, appointmentId: appointmentId, outcome: outcome, nowMillis: nowMillis)
            return MutationResult(records: next, changed: next != fresh, targetId: appointmentId)

        case let .reschedule(appointmentId, newStartMillis, nowMillis, rememberInstance, baseUpdatedAtMillis):
            guard newStartMillis > 0, let existing = fresh.first(where: { $0.id == appointmentId }) else {
                return MutationResult(records: fresh, changed: false, targetId: nil)
            }
            if AppointmentAgenda.sameInstant(existing.startMillis, newStartMillis) && existing.status == .scheduled {
                return MutationResult(records: fresh, changed: false, targetId: existing.id)
            }
            if existing.updatedAtMillis > baseUpdatedAtMillis && !AppointmentAgenda.sameInstant(existing.startMillis, newStartMillis) {
                return MutationResult(records: fresh, changed: false, targetId: existing.id, keptNewer: true)
            }
            let next = AppointmentAgenda.reschedule(
                fresh,
                appointmentId: appointmentId,
                newStartMillis: newStartMillis,
                nowMillis: nowMillis,
                rememberInstance: rememberInstance
            )
            return MutationResult(records: next, changed: next != fresh, targetId: appointmentId)

        case let .upsert(record, baseUpdatedAtMillis):
            if let existing = fresh.first(where: { $0.id == record.id }),
               existing.updatedAtMillis > baseUpdatedAtMillis,
               (existing.startMillis != record.startMillis || existing.status != record.status || existing.location != record.location) {
                return MutationResult(records: fresh, changed: false, targetId: existing.id, keptNewer: true)
            }
            let next = AppointmentAgenda.upsertRecord(fresh, record)
            return MutationResult(records: next, changed: next != fresh, targetId: record.id)

        case let .setEventId(appointmentId, eventId):
            guard let next = AppointmentAgenda.withEventLink(fresh, appointmentId: appointmentId, eventId: eventId) else {
                return MutationResult(records: fresh, changed: false, targetId: nil)
            }
            return MutationResult(records: next, changed: next != fresh, targetId: appointmentId)

        case let .migrate(legacyStartMillis, legacyLocation, legacyEventId, nowMillis):
            let next = AppointmentAgenda.migrateAppointments(
                leadId: leadId,
                existing: fresh,
                legacyStartMillis: legacyStartMillis,
                legacyLocation: legacyLocation,
                legacyEventId: legacyEventId,
                nowMillis: nowMillis
            )
            let legacyId = AppointmentAgenda.legacyAppointmentId(leadId)
            let target = next.first(where: { $0.id == legacyId })?.id
            return MutationResult(records: next, changed: next != fresh, targetId: target)

        case let .singleEdit(previousStartMillis, previousLocation, previousEventId, newStartMillis, newLocation, newEventId, nowMillis, createdId, baseUpdatedAtMillis):
            let described = AppointmentAgenda.describeSingleAppointmentEdit(
                leadId: leadId,
                existing: fresh,
                previousStartMillis: previousStartMillis,
                previousLocation: previousLocation,
                previousEventId: previousEventId,
                newStartMillis: newStartMillis,
                newLocation: newLocation,
                newEventId: newEventId,
                nowMillis: nowMillis,
                createdId: createdId,
                baseUpdatedAtMillis: baseUpdatedAtMillis
            )
            return MutationResult(
                records: described.records,
                changed: described.records != fresh,
                targetId: described.editedId,
                keptNewer: described.keptNewer
            )
        }
    }

    private static func statusFor(_ outcome: AppointmentOutcome) -> AppointmentStatus {
        switch outcome {
        case .completed: return .completed
        case .noShow: return .noShow
        case .canceled: return .canceled
        }
    }
}

struct NextAction: Identifiable {
    var id = UUID().uuidString
    var leadId = "", ownerId = ""
    var workflow: WorkflowType = .general
    var type: ActionType = .toDo
    var title = "", notes = ""
    var dueTime: Int64 = 0
    var status: ActionStatus = .pending
    var appointmentId: String?
    var createdAt = Int64(Date().timeIntervalSince1970 * 1000)
    var completedAt: Int64?
    var reason: String?
    var dueDate: Date { Date(timeIntervalSince1970: Double(dueTime) / 1000) }
    var data: [String: Any] {
        var result: [String: Any] = ["id": id, "leadId": leadId, "ownerId": ownerId, "workflow": workflow.rawValue,
            "type": type.rawValue, "title": title, "notes": notes, "dueTime": dueTime, "status": status.rawValue, "createdAt": createdAt]
        if let appointmentId { result["appointmentId"] = appointmentId }
        if let completedAt { result["completedAt"] = completedAt }
        if let reason { result["reason"] = reason }
        return result
    }
}
struct ActivityRecord: Identifiable {
    var id = UUID().uuidString
    var leadId = "", ownerId = ""
    var type: ActionType = .toDo
    var outcome = "", note = ""
    var timestamp = Int64(Date().timeIntervalSince1970 * 1000)
    var data: [String: Any] {
        ["id": id, "leadId": leadId, "ownerId": ownerId, "type": type.rawValue, "outcome": outcome, "note": note, "timestamp": timestamp]
    }
}
struct StageChangeSpec: Equatable {
    let pipelineType: PipelineType
    let newStageId: String
    let stageTitle: String
}
struct NextActionSpec: Equatable {
    let title: String
    let dueTime: Int64
    let type: ActionType
    var appointmentId: String? = nil
}
struct OutcomeSaveRequest {
    let operationId: String
    let leadId: String
    let ownerId: String
    var outcome: String? = nil
    var note = ""
    var stage: StageChangeSpec? = nil
    var currentActionId: String? = nil
    var appointmentId: String? = nil
    var resolveCurrentActionIfMissing = true
    var nextAction: NextActionSpec? = nil
    var clearExistingNextAction = false
    var lifecycle: WorkflowLifecycle = .unchanged
    var lifecycleReason: String? = nil
    var nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
}
struct OutcomeSavePlan {
    let activity: ActivityRecord
    let newAction: NextAction?
    let completeActionId: String?
    let completeStatus: ActionStatus?
    let completeReason: String?
    let notes: String?
    let category: String?
    let isPaused: Bool?
    let isClosed: Bool?
    let writePausedReason: Bool
    let lastAttemptedContact: Int64?
    let lastConnectedContact: Int64?
}
enum DueShortcut { case today, tomorrow }
enum OutcomeSavePlanner {
    static let appointmentLookbackMs: Int64 = 12 * 60 * 60 * 1000
    static let maxAppointmentChoices = 6

    static func followUpMillis(_ actions: [NextAction], paused: Bool = false, closed: Bool = false) -> Int64? {
        guard !paused, !closed else { return nil }
        return actions.filter { $0.status == .pending && $0.dueTime > 0 }.map(\.dueTime).min()
    }
    static func contactTimestamps(from activities: [ActivityRecord]) -> (attempted: Int64?, connected: Int64?) {
        var attempted: Int64?
        var connected: Int64?
        for record in activities {
            let outcome = record.outcome.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !outcome.isEmpty else { continue }
            if attempted == nil || record.timestamp > attempted! {
                attempted = record.timestamp
            }
            if outcome.localizedCaseInsensitiveContains("Connected")
                || outcome.localizedCaseInsensitiveContains("Meeting completed") {
                if connected == nil || record.timestamp > connected! {
                    connected = record.timestamp
                }
            }
        }
        return (attempted, connected)
    }
    static func sanitizeOperationId(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? "outcome" : trimmed).replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
    }
    static func activityDocumentId(_ operationId: String) -> String { "act_\(sanitizeOperationId(operationId))" }
    static func nextActionDocumentId(_ operationId: String) -> String { "next_\(sanitizeOperationId(operationId))" }
    static func activityType(for outcome: String?, scheduled: ActionType?) -> ActionType {
        if let scheduled { return scheduled }
        switch outcome?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Connected", "No answer", "Voicemail left": return .call
        case "Message sent": return .message
        case "Meeting completed", "No-show", "Rescheduled": return .meeting
        default: return .toDo
        }
    }
    static func appointmentOutcome(for outcome: String?) -> AppointmentOutcome? {
        switch outcome?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Meeting completed", "Completed": return .completed
        case "No-show", "No-Show": return .noShow
        case "Canceled", "Cancelled": return .canceled
        default: return nil
        }
    }
    static func formatDue(_ millis: Int64, timeZone: TimeZone = .current, locale: Locale = Locale(identifier: "en_US_POSIX")) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE, MMM d, yyyy, h:mm a"
        return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }
    static func relevantAppointments(
        records: [AppointmentRecord],
        legacyStartMillis: Int64?,
        nowMillis: Int64,
        timeZone: TimeZone = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> [AppointmentChoice] {
        let earliest = nowMillis - appointmentLookbackMs
        let scheduled = records
            .filter { $0.status == .scheduled && $0.startMillis >= earliest }
            .sorted { $0.startMillis < $1.startMillis }
            .prefix(maxAppointmentChoices)
            .map { record -> AppointmentChoice in
                let time = formatDue(record.startMillis, timeZone: timeZone, locale: locale)
                let place = record.location?.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasPlace = place?.isEmpty == false
                return AppointmentChoice(
                    id: record.id,
                    label: hasPlace ? "\(time) · \(place!)" : time,
                    startMillis: record.startMillis
                )
            }
        if !scheduled.isEmpty { return scheduled }
        guard let legacy = legacyStartMillis, legacy >= earliest else { return [] }
        return [
            AppointmentChoice(
                id: "",
                label: formatDue(legacy, timeZone: timeZone, locale: locale),
                startMillis: legacy
            )
        ]
    }
    static func dueDate(for shortcut: DueShortcut, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let minute = calendar.dateInterval(of: .minute, for: now)!.start
        if shortcut == .tomorrow {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: minute)!
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        }
        let evening = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: minute)!
        if evening > now { return evening }
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: minute)!
        return calendar.dateInterval(of: .hour, for: nextHour)!.start
    }
    static func plan(_ request: OutcomeSaveRequest, existingNotes: String, existingCategory: String, pending: [NextAction]) -> OutcomeSavePlan {
        let outcome = request.outcome?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let changingLifecycle = request.lifecycle != .unchanged
        let spec = request.nextAction
        let schedule = !changingLifecycle && !request.clearExistingNextAction && spec != nil &&
            !(spec?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) && (spec?.dueTime ?? 0) > 0
        let finish = changingLifecycle || !outcome.isEmpty || request.clearExistingNextAction || schedule
        let target = request.currentActionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkedApptTarget: String? = {
            guard let apptId = request.appointmentId?.trimmingCharacters(in: .whitespacesAndNewlines), !apptId.isEmpty else { return nil }
            return pending.first(where: { $0.status == .pending && $0.appointmentId == apptId })?.id
        }()
        let earliest = pending.filter { $0.status == .pending }.sorted { $0.dueTime == $1.dueTime ? $0.id < $1.id : $0.dueTime < $1.dueTime }.first
        let finishedID = finish ? ((target?.isEmpty == false ? target : nil) ?? linkedApptTarget ?? (request.resolveCurrentActionIfMissing ? earliest?.id : nil)) : nil
        let status: ActionStatus? = finishedID == nil ? nil : (request.lifecycle == .pause || request.clearExistingNextAction ? .cancelled : .completed)
        var next: NextAction?
        if schedule, let spec {
            let workflow: WorkflowType = request.stage.map { $0.pipelineType == .sales ? .sales : .recruiting } ?? .general
            let cleanApptId = spec.appointmentId?.trimmingCharacters(in: .whitespacesAndNewlines)
            next = NextAction(id: nextActionDocumentId(request.operationId), leadId: request.leadId, ownerId: request.ownerId,
                workflow: workflow, type: spec.type, title: spec.title.trimmingCharacters(in: .whitespacesAndNewlines),
                dueTime: spec.dueTime, appointmentId: (cleanApptId?.isEmpty == false) ? cleanApptId : nil, createdAt: request.nowMillis)
        }
        var parts: [String] = []
        if let stage = request.stage, !stage.stageTitle.isEmpty { parts.append("Moved to \(stage.stageTitle) stage") }
        let typed = request.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { parts.append(typed) }
        let reason = request.lifecycleReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if changingLifecycle && !reason.isEmpty { parts.append("\(request.lifecycle == .pause ? "Paused" : "Closed"): \(reason)") }
        let noteBody = parts.joined(separator: "\n\n")
        let activityID = activityDocumentId(request.operationId)
        let activityOutcome = request.stage == nil ? outcome : (outcome.isEmpty ? "Stage Changed" : "Stage Changed: \(outcome)")
        let activity = ActivityRecord(id: activityID, leadId: request.leadId, ownerId: request.ownerId,
            type: activityType(for: outcome, scheduled: next?.type), outcome: activityOutcome, note: noteBody, timestamp: request.nowMillis)
        let category: String? = request.stage?.newStageId == "in_force" && !existingCategory.contains("Client")
            ? (existingCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Client" : "\(existingCategory), Client") : nil
        let resumed = next != nil && !changingLifecycle
        return OutcomeSavePlan(activity: activity, newAction: next, completeActionId: finishedID, completeStatus: status,
            completeReason: changingLifecycle && !reason.isEmpty ? reason : nil,
            notes: noteBody.isEmpty ? nil : NoteUtils.prependNote(existingNotes, content: noteBody, eventId: activityID, date: Date(timeIntervalSince1970: Double(request.nowMillis) / 1000)),
            category: category, isPaused: changingLifecycle ? request.lifecycle == .pause : (resumed ? false : nil),
            isClosed: changingLifecycle ? request.lifecycle == .close : (resumed ? false : nil), writePausedReason: changingLifecycle || resumed,
            lastAttemptedContact: outcome.isEmpty ? nil : request.nowMillis,
            lastConnectedContact: outcome.localizedCaseInsensitiveContains("Connected") || outcome.localizedCaseInsensitiveContains("Meeting completed") ? request.nowMillis : nil)
    }
}
enum NoteUtils {
    static func prependNote(_ existing: String, content: String, eventId: String? = nil, date: Date = Date()) -> String {
        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return existing }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM dd, yyyy hh:mm a"
        let event = eventId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let formatted = "[\(formatter.string(from: date))\(event.isEmpty ? "" : " | eid:\(event)")]: \(clean)"
        return existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? formatted : "\(formatted)\n\n\(existing)"
    }
    static func sortedNotes(_ fullNotes: String) -> [ParsedNote] {
        ContactActivityTimeline.parseNotes(fullNotes)
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .sorted { lhs, rhs in
                let leftTime = lhs.element.timestampMillis ?? Int64.min
                let rightTime = rhs.element.timestampMillis ?? Int64.min
                if leftTime == rightTime { return lhs.offset < rhs.offset }
                return leftTime > rightTime
            }
            .map(\.element)
    }
    static func canApplyEditedNotes(remoteNotes: String, expectedOriginalNotes: String) -> Bool {
        remoteNotes == expectedOriginalNotes
    }
    static func removeNote(withEventId eventId: String, from existing: String) -> String {
        let id = eventId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return existing }
        let parsed = ContactActivityTimeline.parseNotes(existing)
        let filtered = parsed.filter { $0.eventId != id }
        guard filtered.count != parsed.count else { return existing }
        return serializedNotes(filtered)
    }
    private static func serializedNotes(_ notes: [ParsedNote]) -> String {
        notes.compactMap { note in
            let content = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            if note.date == "Unknown date", note.eventId == nil {
                return content
            }
            let eventPart = note.eventId.map { " | eid:\($0)" } ?? ""
            return "[\(note.date)\(eventPart)]: \(content)"
        }.joined(separator: "\n\n")
    }
    static func getDisplayNote(_ fullNotes: String) -> String {
        let parsed = ContactActivityTimeline.parseNotes(fullNotes)
        if let newest = parsed.first(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let lines = newest.content.components(separatedBy: .newlines)
            let firstLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? newest.content
            return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let firstBlock = fullNotes.components(separatedBy: "\n\n").first ?? fullNotes
        let fallback = firstBlock.replacingOccurrences(of: #"^\[.*?\]:\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "No notes available" : fallback
    }
}
struct ParsedNote: Equatable {
    let date: String
    let content: String
    let timestampMillis: Int64?
    let eventId: String?
}
struct TimelineItem: Identifiable {
    let id: String
    let type: ActionType
    let outcome: String
    let note: String
    let timestampMillis: Int64?
    let dateDisplay: String
    let isActivityRecord: Bool
    let eventId: String?
    let stageContext: String?
}
enum ContactActivityTimeline {
    static func parseTimestamp(_ text: String) -> Int64? {
        let patterns = ["MMM dd, yyyy hh:mm a", "MMM dd, yyyy h:mm a", "MMM d, yyyy hh:mm a", "MMM d, yyyy h:mm a",
            "MMM dd, yyyy, hh:mm a", "MMM dd, yyyy, h:mm a", "MMM d, yyyy, hh:mm a", "MMM d, yyyy, h:mm a",
            "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "MMM dd, yyyy", "MMM d, yyyy"]
        for locale in [Locale(identifier: "en_US_POSIX"), Locale.current] {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.isLenient = false
            for pattern in patterns {
                formatter.dateFormat = pattern
                if let date = formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) { return Int64(date.timeIntervalSince1970 * 1000) }
            }
        }
        return nil
    }
    static func parseNotes(_ raw: String) -> [ParsedNote] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        guard text.length > 0 else { return [] }
        let headers = try! NSRegularExpression(pattern: #"(?m)^\[([^\]\r\n]+)\]:\s*"#)
        let events = try! NSRegularExpression(pattern: #"\b(?:eid|event):([a-zA-Z0-9_\-]+)"#)
        let cleanEvents = try! NSRegularExpression(pattern: #"\|?\s*\b(?:eid|event):[a-zA-Z0-9_\-]+\s*\|?"#)
        let matches = headers.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        guard !matches.isEmpty else { return [ParsedNote(date: "Unknown date", content: text as String, timestampMillis: nil, eventId: nil)] }
        var notes: [ParsedNote] = []
        if let first = matches.first, first.range.location > 0 {
            let prefix = text.substring(to: first.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty { notes.append(ParsedNote(date: "Unknown date", content: prefix, timestampMillis: nil, eventId: nil)) }
        }
        for (index, match) in matches.enumerated() {
            let header = text.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(header.startIndex..., in: header)
            let event = events.firstMatch(in: header, range: range).map { (header as NSString).substring(with: $0.range(at: 1)) }
            let date = cleanEvents.stringByReplacingMatches(in: header, range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let start = NSMaxRange(match.range)
            let end = index + 1 < matches.count ? matches[index + 1].range.location : text.length
            notes.append(ParsedNote(date: date.isEmpty ? header : date,
                content: text.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespacesAndNewlines),
                timestampMillis: parseTimestamp(date), eventId: event))
        }
        return notes
    }
    static func stageContext(outcome: String?, note: String) -> String? {
        if let outcome, outcome.hasPrefix("Stage Changed: ") { return String(outcome.dropFirst("Stage Changed: ".count)).trimmingCharacters(in: .whitespacesAndNewlines) }
        let regex = try! NSRegularExpression(pattern: "Moved to (.+?) stage")
        return regex.firstMatch(in: note, range: NSRange(note.startIndex..., in: note)).map { (note as NSString).substring(with: $0.range(at: 1)) }
    }
    static func mergeActivityAndNotes(_ records: [ActivityRecord], rawNotes: String) -> [TimelineItem] {
        let ids = Set(records.map(\.id))
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy, h:mm a"
        var items = records.map { record in
            TimelineItem(id: record.id, type: record.type, outcome: record.outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Activity" : record.outcome.trimmingCharacters(in: .whitespacesAndNewlines),
                note: record.note.trimmingCharacters(in: .whitespacesAndNewlines), timestampMillis: record.timestamp,
                dateDisplay: formatter.string(from: Date(timeIntervalSince1970: Double(record.timestamp) / 1000)),
                isActivityRecord: true, eventId: record.id, stageContext: stageContext(outcome: record.outcome, note: record.note))
        }
        for (index, note) in parseNotes(rawNotes).enumerated() {
            let duplicate = note.eventId.map { ids.contains($0) } ?? records.contains { record in
                record.note.trimmingCharacters(in: .whitespacesAndNewlines) == note.content.trimmingCharacters(in: .whitespacesAndNewlines) &&
                    note.timestampMillis.map { abs(Double(record.timestamp) - Double($0)) < 120_000 } == true
            }
            guard !duplicate, !note.content.isEmpty else { continue }
            let voice = note.content.lowercased().hasPrefix("[voice log]")
            let clean = voice ? note.content.replacingOccurrences(of: #"^\[Voice Log\]:?\s*"#, with: "", options: [.regularExpression, .caseInsensitive]) : note.content
            items.append(TimelineItem(id: "note_\(index)_\(note.timestampMillis ?? Int64(index))", type: voice ? .message : .toDo,
                outcome: voice ? "Voice Note" : "Note", note: clean, timestampMillis: note.timestampMillis, dateDisplay: note.date,
                isActivityRecord: false, eventId: note.eventId, stageContext: stageContext(outcome: nil, note: note.content)))
        }
        return items.enumerated().sorted {
            let left = $0.element.timestampMillis, right = $1.element.timestampMillis
            if left == right { return $0.offset < $1.offset }
            if let left, let right { return left > right }
            return left != nil
        }.map(\.element)
    }
}

struct ReminderAlarmState: Equatable, Codable, Identifiable {
    var leadId: String
    var actionId: String
    var dueTime: Int64
    var title: String
    var contactName: String

    var id: String {
        ReminderNotificationPlanner.reminderRequestIdentity(leadId: leadId, actionId: actionId)
    }

    var notificationTitle: String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Reminder" : clean
    }

    var notificationBody: String {
        let clean = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Contact" : clean
    }

    var deepLinkURLString: String {
        "rcrm://lead/\(leadId)"
    }
}

struct ReminderAlarmSync: Equatable {
    var cancelActionIds: Set<String>
    var cancelRequestIds: Set<String>
    var schedule: [ReminderAlarmState]
}

struct LeadNotificationSummary: Equatable {
    var id: String
    var name: String
    var followUpMillis: Int64?
    var isPaused: Bool
    var isClosed: Bool
    var appointments: [AppointmentRecord]

    init(
        id: String,
        name: String,
        followUpMillis: Int64? = nil,
        isPaused: Bool = false,
        isClosed: Bool = false,
        appointments: [AppointmentRecord] = []
    ) {
        self.id = id
        self.name = name
        self.followUpMillis = followUpMillis
        self.isPaused = isPaused
        self.isClosed = isClosed
        self.appointments = appointments
    }
}

struct DailyDigestPlan: Equatable {
    var followUps: [String]
    var appointments: [String]
    var title: String
    var summaryText: String
    var bodyLines: [String]
    var bodyText: String

    var totalCount: Int { followUps.count + appointments.count }
}

enum ReminderNotificationPlanner {
    static let restoreGraceMillis: Int64 = 6 * 60 * 60 * 1000
    static let dailyDigestIdentifier = "rcrm_daily_digest"
    static let defaultDigestHour = 8
    static let defaultDigestMinute = 0
    static let maxLinesPerSection = 8
    static let extraLeadIdKey = "targetLeadId"
    static let extraReminderIdKey = "reminderId"
    static let extraTitleKey = "REMINDER_TITLE"
    static let extraContactNameKey = "LEAD_NAME"
    static let extraUrlKey = "rcrmUrl"

    static func sanitizeId(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "reminder" : trimmed
        return base.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
    }

    static func reminderRequestIdentity(leadId: String, actionId: String) -> String {
        "reminder:\(sanitizeId(leadId)):\(sanitizeId(actionId))"
    }

    static func legacyActionId(leadId: String) -> String {
        "legacy_followup_\(sanitizeId(leadId))"
    }

    static func appointmentActionId(appointmentId: String) -> String {
        "appt_\(sanitizeId(appointmentId))"
    }

    static func isAppointmentAlarmKey(_ key: String) -> Bool {
        key.hasPrefix("appt:") || key.hasPrefix("appt_")
    }

    static func shouldRestoreAlarm(dueTime: Int64, nowMillis: Int64) -> Bool {
        dueTime > 0 && dueTime > nowMillis - restoreGraceMillis
    }

    static func fireDate(dueTime: Int64, nowMillis: Int64) -> Date {
        let targetMillis = max(dueTime, nowMillis + 5_000)
        return Date(timeIntervalSince1970: Double(targetMillis) / 1000)
    }

    static func syncAlarms(
        leadId: String,
        contactName: String,
        isPaused: Bool = false,
        isClosed: Bool = false,
        persisted: [ReminderAlarmState],
        actions: [NextAction],
        nowMillis: Int64
    ) -> ReminderAlarmSync {
        let cleanName = contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Contact"
            : contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let desired: [NextAction]
        if isPaused || isClosed {
            desired = []
        } else {
            desired = actions.filter { action in
                action.status == .pending &&
                    action.dueTime > 0 &&
                    shouldRestoreAlarm(dueTime: action.dueTime, nowMillis: nowMillis)
            }
        }
        let leadPersisted = persisted.filter { $0.leadId == leadId }
        var cancelActionIds = Set<String>()
        for stored in leadPersisted {
            let match = desired.first(where: { $0.id == stored.actionId })
            let desiredTitle = match.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Reminder" : $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            if match == nil || match?.dueTime != stored.dueTime || desiredTitle != stored.title || cleanName != stored.contactName {
                cancelActionIds.insert(stored.actionId)
            }
        }
        let legacyId = legacyActionId(leadId: leadId)
        if !desired.contains(where: { $0.id == legacyId }) {
            cancelActionIds.insert(legacyId)
        }
        let cancelRequestIds = Set(cancelActionIds.map { reminderRequestIdentity(leadId: leadId, actionId: $0) })
        let schedule = desired.compactMap { action -> ReminderAlarmState? in
            let cleanTitle = action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Reminder"
                : action.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let stored = leadPersisted.first(where: { $0.actionId == action.id })
            if let stored,
               stored.dueTime == action.dueTime,
               stored.title == cleanTitle,
               stored.contactName == cleanName {
                return nil
            }
            return ReminderAlarmState(
                leadId: leadId,
                actionId: action.id,
                dueTime: action.dueTime,
                title: cleanTitle,
                contactName: cleanName
            )
        }
        return ReminderAlarmSync(
            cancelActionIds: cancelActionIds,
            cancelRequestIds: cancelRequestIds,
            schedule: schedule
        )
    }

    static func reconcileLeadSummaries(
        leads: [LeadNotificationSummary],
        persisted: [ReminderAlarmState],
        syncedLeadIds: Set<String>,
        nowMillis: Int64
    ) -> (kept: [ReminderAlarmState], cancelRequestIds: Set<String>, schedule: [ReminderAlarmState]) {
        let leadsById = Dictionary(uniqueKeysWithValues: leads.map { ($0.id, $0) })
        var kept: [ReminderAlarmState] = []
        var cancelRequestIds = Set<String>()
        var schedule: [ReminderAlarmState] = []

        for alarm in persisted {
            guard let lead = leadsById[alarm.leadId],
                  !lead.isPaused,
                  !lead.isClosed,
                  shouldRestoreAlarm(dueTime: alarm.dueTime, nowMillis: nowMillis) else {
                cancelRequestIds.insert(alarm.id)
                continue
            }
            if alarm.actionId == legacyActionId(leadId: lead.id), lead.followUpMillis == nil {
                cancelRequestIds.insert(alarm.id)
                continue
            }
            let cleanName = lead.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Contact" : lead.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if alarm.contactName != cleanName {
                cancelRequestIds.insert(alarm.id)
                let updated = ReminderAlarmState(
                    leadId: alarm.leadId,
                    actionId: alarm.actionId,
                    dueTime: alarm.dueTime,
                    title: alarm.title,
                    contactName: cleanName
                )
                kept.append(updated)
                schedule.append(updated)
            } else {
                kept.append(alarm)
            }
        }

        for lead in leads where !lead.isPaused && !lead.isClosed {
            let cleanName = lead.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Contact" : lead.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let existingForLead = kept.filter { $0.leadId == lead.id }

            for appt in lead.appointments where appt.status == .scheduled && shouldRestoreAlarm(dueTime: appt.startMillis, nowMillis: nowMillis) {
                let apptActionId = appointmentActionId(appointmentId: appt.id)
                if let index = kept.firstIndex(where: { $0.leadId == lead.id && $0.actionId == apptActionId }) {
                    if kept[index].dueTime != appt.startMillis || kept[index].contactName != cleanName {
                        cancelRequestIds.insert(kept[index].id)
                        let updated = ReminderAlarmState(leadId: lead.id, actionId: apptActionId, dueTime: appt.startMillis, title: "Appointment", contactName: cleanName)
                        kept[index] = updated
                        schedule.append(updated)
                    }
                } else if !syncedLeadIds.contains(lead.id) {
                    let created = ReminderAlarmState(leadId: lead.id, actionId: apptActionId, dueTime: appt.startMillis, title: "Appointment", contactName: cleanName)
                    kept.append(created)
                    schedule.append(created)
                }
            }

            let scheduledApptActionIds = Set(
                lead.appointments
                    .filter { $0.status == .scheduled && shouldRestoreAlarm(dueTime: $0.startMillis, nowMillis: nowMillis) }
                    .map { appointmentActionId(appointmentId: $0.id) }
            )
            for existing in existingForLead where isAppointmentAlarmKey(existing.actionId) && !scheduledApptActionIds.contains(existing.actionId) {
                if !syncedLeadIds.contains(lead.id) {
                    cancelRequestIds.insert(existing.id)
                    kept.removeAll { $0.id == existing.id }
                }
            }

            let hasLeadAlarms = kept.contains(where: { $0.leadId == lead.id })
            if !syncedLeadIds.contains(lead.id),
               !hasLeadAlarms,
               let followUpMillis = lead.followUpMillis,
               shouldRestoreAlarm(dueTime: followUpMillis, nowMillis: nowMillis) {
                let fallback = ReminderAlarmState(
                    leadId: lead.id,
                    actionId: legacyActionId(leadId: lead.id),
                    dueTime: followUpMillis,
                    title: "Follow up",
                    contactName: cleanName
                )
                kept.append(fallback)
                schedule.append(fallback)
            } else if !syncedLeadIds.contains(lead.id),
                      let legacyIdx = kept.firstIndex(where: { $0.leadId == lead.id && $0.actionId == legacyActionId(leadId: lead.id) }),
                      let followUpMillis = lead.followUpMillis,
                      shouldRestoreAlarm(dueTime: followUpMillis, nowMillis: nowMillis),
                      kept[legacyIdx].dueTime != followUpMillis {
                cancelRequestIds.insert(kept[legacyIdx].id)
                let updated = ReminderAlarmState(
                    leadId: lead.id,
                    actionId: legacyActionId(leadId: lead.id),
                    dueTime: followUpMillis,
                    title: "Follow up",
                    contactName: cleanName
                )
                kept[legacyIdx] = updated
                schedule.append(updated)
            }
        }

        return (kept: kept, cancelRequestIds: cancelRequestIds, schedule: schedule)
    }

    static func buildDailyDigest(
        leads: [LeadNotificationSummary],
        nowMillis: Int64,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> DailyDigestPlan? {
        let todayStart = AppointmentAgenda.startOfDay(nowMillis, calendar: calendar)
        let todayDate = Date(timeIntervalSince1970: Double(todayStart) / 1000)
        let todayEndDate = calendar.date(byAdding: .day, value: 1, to: todayDate) ?? todayDate.addingTimeInterval(86_400)
        let todayEnd = Int64(todayEndDate.timeIntervalSince1970 * 1000)

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "h:mm a"

        var followUps: [String] = []
        var appointments: [String] = []

        for lead in leads {
            if lead.isClosed { continue }
            let cleanName = lead.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : lead.name.trimmingCharacters(in: .whitespacesAndNewlines)

            if !lead.isPaused {
                if let followUpMillis = lead.followUpMillis, followUpMillis > 0 {
                    if followUpMillis < todayStart {
                        followUps.append("\(cleanName) · Overdue")
                    } else if followUpMillis >= todayStart && followUpMillis < todayEnd {
                        let formatted = timeFormatter.string(from: Date(timeIntervalSince1970: Double(followUpMillis) / 1000))
                        followUps.append("\(cleanName) · \(formatted)")
                    }
                } else {
                    followUps.append("\(cleanName) · Missing Plan")
                }
            }

            let starts = AppointmentAgenda.digestAppointmentStarts(lead.appointments, dayStart: todayStart, dayEnd: todayEnd)
            for start in starts {
                let formatted = timeFormatter.string(from: Date(timeIntervalSince1970: Double(start) / 1000))
                appointments.append("\(cleanName) · \(formatted)")
            }
        }

        guard !followUps.isEmpty || !appointments.isEmpty else { return nil }
        let totalCount = followUps.count + appointments.count
        let title = "Today's schedule (\(totalCount))"
        let summaryText: String
        if !followUps.isEmpty && !appointments.isEmpty {
            summaryText = "\(followUps.count) follow-up(s) and \(appointments.count) appointment(s) today"
        } else if !followUps.isEmpty {
            summaryText = "\(followUps.count) follow-up(s) due today"
        } else {
            summaryText = "\(appointments.count) appointment(s) today"
        }

        var bodyLines: [String] = []
        if !followUps.isEmpty {
            bodyLines.append("— Follow-ups —")
            let shown = Array(followUps.prefix(maxLinesPerSection))
            bodyLines.append(contentsOf: shown)
            let remaining = followUps.count - shown.count
            if remaining > 0 {
                bodyLines.append("…and \(remaining) more")
            }
        }
        if !appointments.isEmpty {
            bodyLines.append("— Appointments —")
            let shown = Array(appointments.prefix(maxLinesPerSection))
            bodyLines.append(contentsOf: shown)
            let remaining = appointments.count - shown.count
            if remaining > 0 {
                bodyLines.append("…and \(remaining) more")
            }
        }

        return DailyDigestPlan(
            followUps: followUps,
            appointments: appointments,
            title: title,
            summaryText: summaryText,
            bodyLines: bodyLines,
            bodyText: ([summaryText] + bodyLines).joined(separator: "\n")
        )
    }

    static func extractLeadId(fromUserInfo userInfo: [AnyHashable: Any]) -> String? {
        if let leadId = (userInfo[extraLeadIdKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !leadId.isEmpty {
            return leadId
        }
        if let leadId = (userInfo["leadId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !leadId.isEmpty {
            return leadId
        }
        if let rawUrl = (userInfo[extraUrlKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: rawUrl),
           let leadId = AppointmentAgenda.leadId(from: url) {
            return leadId
        }
        return nil
    }
}

enum SmartLogPlanner {
    static let nameToken = "[NAME]"
    static let defaultIntroTemplate = "Hi [NAME], just following up to see if you had any questions! Looking forward to connecting again."

    static func normalizedPhone(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        if digits.count == 11 && digits.hasPrefix("1") {
            return String(digits.dropFirst())
        }
        return digits
    }

    static func phonesMatch(_ first: String, _ second: String) -> Bool {
        let n1 = normalizedPhone(first)
        let n2 = normalizedPhone(second)
        return !n1.isEmpty && n1 == n2
    }

    static func formatFirstName(from fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.components(separatedBy: .whitespacesAndNewlines).first ?? trimmed
    }

    static func renderIntroSms(template: String?, contactName: String) -> String {
        let base = (template?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (template ?? defaultIntroTemplate)
            : defaultIntroTemplate
        let firstName = formatFirstName(from: contactName)
        let replacement = firstName.isEmpty ? "there" : firstName
        return base.replacingOccurrences(of: nameToken, with: replacement)
    }

    static func messagesURL(phone: String, body: String) -> URL? {
        let cleanPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPhone.isEmpty else { return nil }
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "sms:\(cleanPhone)&body=\(encodedBody)")
    }

    /** Optional fields left empty in a quick log never erase the full contact profile. */
    static func profileUpdates(draft: [String: String]) -> [String: Any] {
        var updates: [String: Any] = [:]
        for (key, value) in draft {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                updates[key] = trimmed
            }
        }
        return updates
    }

    enum SmartPreset: String, CaseIterable, Identifiable {
        case todayPreset = "today_preset"
        case tomorrowPreset = "tomorrow_preset"
        case plus1Week = "plus_1_week"
        case plus2Weeks = "plus_2_weeks"
        case plus1Month = "plus_1_month"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .todayPreset: return "7 PM Today"
            case .tomorrowPreset: return "7 PM Tomorrow"
            case .plus1Week: return "+1 Week"
            case .plus2Weeks: return "+2 Weeks"
            case .plus1Month: return "+1 Month"
            }
        }
    }

    static func presetFollowUpDate(
        preset: SmartPreset,
        now: Date = Date(),
        presetHour: Int = 19,
        presetMinute: Int = 0,
        calendar: Calendar = .current
    ) -> Date {
        switch preset {
        case .todayPreset:
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = presetHour
            comps.minute = presetMinute
            comps.second = 0
            if let target = calendar.date(from: comps) {
                if target > now {
                    return target
                } else {
                    return calendar.date(byAdding: .day, value: 1, to: target) ?? target
                }
            }
            return now
        case .tomorrowPreset:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            var comps = calendar.dateComponents([.year, .month, .day], from: tomorrow)
            comps.hour = presetHour
            comps.minute = presetMinute
            comps.second = 0
            return calendar.date(from: comps) ?? tomorrow
        case .plus1Week:
            let week = calendar.date(byAdding: .day, value: 7, to: now) ?? now
            var comps = calendar.dateComponents([.year, .month, .day], from: week)
            comps.hour = presetHour
            comps.minute = presetMinute
            comps.second = 0
            return calendar.date(from: comps) ?? week
        case .plus2Weeks:
            let twoWeeks = calendar.date(byAdding: .day, value: 14, to: now) ?? now
            var comps = calendar.dateComponents([.year, .month, .day], from: twoWeeks)
            comps.hour = presetHour
            comps.minute = presetMinute
            comps.second = 0
            return calendar.date(from: comps) ?? twoWeeks
        case .plus1Month:
            let month = calendar.date(byAdding: .month, value: 1, to: now) ?? now
            var comps = calendar.dateComponents([.year, .month, .day], from: month)
            comps.hour = presetHour
            comps.minute = presetMinute
            comps.second = 0
            return calendar.date(from: comps) ?? month
        }
    }

    static func renderRecommendedSms(
        name: String,
        notes: String = "",
        category: String = "",
        intent: LocalSmsDraft.Intent? = nil,
        tone: LocalSmsDraft.Tone = .warm
    ) -> String {
        LocalSmsDraft.generate(name: name, notes: notes, category: category, explicitIntent: intent, tone: tone)
    }
}

#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

enum LocalSmsDraft {
    enum Intent: String, CaseIterable, Identifiable {
        case checkIn = "check_in"
        case insurance = "insurance"
        case investment = "investment"
        case appointment = "appointment"
        case recruit = "recruit"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .checkIn: return "Check-In"
            case .insurance: return "Coverage"
            case .investment: return "Goals"
            case .appointment: return "Meet"
            case .recruit: return "Opportunity"
            }
        }

        var iconName: String {
            switch self {
            case .checkIn: return "message.fill"
            case .insurance: return "shield.lefthalf.filled"
            case .investment: return "chart.line.uptrend.xyaxis"
            case .appointment: return "calendar"
            case .recruit: return "person.2.badge.gearshape"
            }
        }
    }

    enum Tone: String, CaseIterable, Identifiable {
        case warm = "warm"
        case direct = "direct"
        case question = "question"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .warm: return "Warm"
            case .direct: return "Direct"
            case .question: return "Action"
            }
        }
    }

    struct Recommendation: Identifiable, Equatable {
        var id: UUID
        let text: String
        let intent: Intent
        let tone: Tone
        let confidence: Double
        let contextBadge: String

        init(
            id: UUID = UUID(),
            text: String,
            intent: Intent,
            tone: Tone,
            confidence: Double,
            contextBadge: String
        ) {
            self.id = id
            self.text = text
            self.intent = intent
            self.tone = tone
            self.confidence = confidence
            self.contextBadge = contextBadge
        }
    }

    static func extractTokens(from text: String) -> [String] {
        #if canImport(NaturalLanguage)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let word = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !word.isEmpty { tokens.append(word) }
            return true
        }
        return tokens
        #else
        return text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        #endif
    }

    static func detectIntent(
        notes: String,
        category: String = "",
        explicitIntent: Intent? = nil
    ) -> (intent: Intent, confidence: Double, reason: String) {
        if let explicit = explicitIntent {
            return (explicit, 0.98, "Selected: \(explicit.label)")
        }

        let lowerNotes = notes.lowercased()
        let lowerCategory = category.lowercased()
        let tokens = Set(extractTokens(from: "\(lowerNotes) \(lowerCategory)"))

        let insuranceKeywords = ["quote", "insurance", "policy", "coverage", "premium", "beneficiary", "beneficiaries", "term", "underwriting", "carrier"]
        let investmentKeywords = ["invest", "investment", "rollover", "account", "401k", "ira", "roth", "contribution", "wealth", "portfolio", "fund", "savings"]
        let appointmentKeywords = ["appointment", "meet", "meeting", "schedule", "calendar", "zoom", "fna", "kitchen"]
        let recruitKeywords = ["recruit", "recruiting", "opportunity", "bop", "iba", "interview", "licensing", "license", "career", "partner"]

        var insuranceScore = 0
        var matchedInsurance: [String] = []
        for kw in insuranceKeywords {
            if lowerNotes.contains(kw) || lowerCategory.contains(kw) || tokens.contains(kw) {
                insuranceScore += (lowerNotes.contains(kw) ? 2 : 1)
                matchedInsurance.append(kw)
            }
        }

        var investmentScore = 0
        var matchedInvestment: [String] = []
        for kw in investmentKeywords {
            if lowerNotes.contains(kw) || lowerCategory.contains(kw) || tokens.contains(kw) {
                investmentScore += (lowerNotes.contains(kw) ? 2 : 1)
                matchedInvestment.append(kw)
            }
        }

        var appointmentScore = 0
        var matchedAppointment: [String] = []
        for kw in appointmentKeywords {
            if lowerNotes.contains(kw) || tokens.contains(kw) {
                appointmentScore += 2
                matchedAppointment.append(kw)
            }
        }

        var recruitScore = 0
        var matchedRecruit: [String] = []
        for kw in recruitKeywords {
            if lowerNotes.contains(kw) || lowerCategory.contains(kw) || tokens.contains(kw) {
                recruitScore += (lowerCategory.contains(kw) ? 3 : 2)
                matchedRecruit.append(kw)
            }
        }

        if lowerCategory.contains("recruit") { recruitScore += 3 }
        if lowerCategory.contains("life insurance") || lowerCategory.contains("insurance") { insuranceScore += 3 }
        if lowerCategory.contains("investment") { investmentScore += 3 }

        let candidates: [(Intent, Int, [String])] = [
            (.insurance, insuranceScore, matchedInsurance),
            (.investment, investmentScore, matchedInvestment),
            (.appointment, appointmentScore, matchedAppointment),
            (.recruit, recruitScore, matchedRecruit)
        ]

        guard let best = candidates.max(by: { $0.1 < $1.1 }), best.1 > 0 else {
            return (.checkIn, 0.50, "General check-in")
        }

        let confidence = min(0.95, 0.55 + Double(best.1) * 0.1)
        let reason = best.2.isEmpty ? "\(best.0.label) match" : "Matched cues: \(best.2.prefix(2).joined(separator: ", "))"
        return (best.0, confidence, reason)
    }

    static func renderText(firstName: String, intent: Intent, tone: Tone) -> String {
        switch (intent, tone) {
        case (.insurance, .warm):
            return "Hi \(firstName), following up on our recent chat regarding your coverage options! Let me know if you have any questions."
        case (.insurance, .direct):
            return "Hi \(firstName), I'm ready to review your coverage options whenever you have a moment. What time works best today?"
        case (.insurance, .question):
            return "Hi \(firstName), did you have any questions about the coverage details we discussed? Happy to walk through them with you."

        case (.investment, .warm):
            return "Hi \(firstName), following up on our discussion about your financial goals! Let me know when you'd like to review the details."
        case (.investment, .direct):
            return "Hi \(firstName), let's schedule a quick review of your financial goals and account setup. Are you free this afternoon?"
        case (.investment, .question):
            return "Hi \(firstName), how are things looking on your end regarding your savings and investment goals? Would love to catch up soon."

        case (.appointment, .warm):
            return "Hi \(firstName), looking forward to connecting for our upcoming meeting! Please let me know if that time still works best for you."
        case (.appointment, .direct):
            return "Hi \(firstName), confirming our scheduled meeting. Please let me know if you need to adjust the time."
        case (.appointment, .question):
            return "Hi \(firstName), does our upcoming meeting time still work well for your schedule?"

        case (.recruit, .warm):
            return "Hi \(firstName), really enjoyed our conversation about the business opportunity! Let me know when you have a few minutes to connect on next steps."
        case (.recruit, .direct):
            return "Hi \(firstName), let's set up a quick 10-minute sync to walk through the partnership overview. Does today work for you?"
        case (.recruit, .question):
            return "Hi \(firstName), have you had a chance to think about the team expansion opportunity we chatted about?"

        case (.checkIn, .warm):
            return "Hi \(firstName), just following up to see how your day is going! Let me know if you have any questions or when is a good time to connect."
        case (.checkIn, .direct):
            return "Hi \(firstName), touching base on our next steps. Let me know when you're available for a brief call."
        case (.checkIn, .question):
            return "Hi \(firstName), how is your week going? Let me know if there's anything I can help with!"
        }
    }

    static func generate(
        name: String,
        notes: String = "",
        category: String = "",
        explicitIntent: Intent? = nil,
        tone: Tone = .warm,
        onDownloading: (() -> Void)? = nil
    ) -> String {
        onDownloading?()
        let targetName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = targetName.isEmpty ? "there" : targetName
        let firstName = SmartLogPlanner.formatFirstName(from: resolvedName).isEmpty
            ? "there"
            : SmartLogPlanner.formatFirstName(from: resolvedName)
        let detection = detectIntent(notes: notes, category: category, explicitIntent: explicitIntent)
        return renderText(firstName: firstName, intent: detection.intent, tone: tone)
    }

    static func generateAsync(
        name: String,
        notes: String = "",
        category: String = "",
        explicitIntent: Intent? = nil,
        tone: Tone = .warm,
        onDownloading: (() -> Void)? = nil
    ) async -> String {
        onDownloading?()
        return generate(
            name: name,
            notes: notes,
            category: category,
            explicitIntent: explicitIntent,
            tone: tone,
            onDownloading: onDownloading
        )
    }

    static func generateVariations(
        name: String,
        notes: String = "",
        category: String = "",
        explicitIntent: Intent? = nil
    ) -> [Recommendation] {
        let targetName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = targetName.isEmpty ? "there" : targetName
        let firstName = SmartLogPlanner.formatFirstName(from: resolvedName).isEmpty
            ? "there"
            : SmartLogPlanner.formatFirstName(from: resolvedName)

        let detection = detectIntent(notes: notes, category: category, explicitIntent: explicitIntent)

        return Tone.allCases.map { tone in
            Recommendation(
                text: renderText(firstName: firstName, intent: detection.intent, tone: tone),
                intent: detection.intent,
                tone: tone,
                confidence: detection.confidence,
                contextBadge: detection.reason
            )
        }
    }
}

struct Lead: Identifiable {
    var id = ""
    var ownerId = ""
    var name = "", phone = "", email = "", address = "", company = "", title = "", notes = "", category = "Prospect"
    var salesStage: SalesStage = .newLead
    var recruitStage: RecruitStage = .prospect
    var followUpDate: Date?
    var appointments: [AppointmentRecord] = []
    var appointmentDate: Date?
    var appointmentLocation: String?
    var googleCalendarEventId: Int64?
    var isPinned = false
    var isPaused = false, isClosed = false
    var pausedReason: String?
    var lastAttemptedContact: Date?, lastConnectedContact: Date?
    var tmMarried = false, tmAge = false, tmChildren = false, tmHomeowner = false, tmOccupation = false
    var targetMarketPoints: Int { [tmMarried, tmAge, tmChildren, tmHomeowner, tmOccupation].filter { $0 }.count }
    var categories: [String] { category.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }

    init() {}
    init(document: QueryDocumentSnapshot) {
        let d = document.data()
        id = document.documentID
        ownerId = d["ownerId"] as? String ?? ""
        name = d["name"] as? String ?? "Unnamed contact"
        phone = d["phone"] as? String ?? ""; email = d["email"] as? String ?? ""
        address = d["address"] as? String ?? ""; company = d["company"] as? String ?? ""
        title = d["jobTitle"] as? String ?? d["title"] as? String ?? ""
        notes = d["notes"] as? String ?? ""; category = d["category"] as? String ?? "Prospect"
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let legacyDate = Self.date(d["appointmentDate"])
        let legacyStartMillis = legacyDate.map { Int64($0.timeIntervalSince1970 * 1000) }
        let rawLegacyLoc = (d["appointmentLocation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyLocation = (rawLegacyLoc?.isEmpty == false) ? rawLegacyLoc : nil
        let legacyEventId = AppointmentAgenda.longOrNull(d["googleCalendarEventId"]).flatMap { $0 > 0 ? $0 : nil }
        let parsedRecords = LeadAppointmentSync.readRecords(d[AppointmentAgenda.fieldAppointments])
        appointments = AppointmentAgenda.migrateAppointments(
            leadId: id,
            existing: parsedRecords,
            legacyStartMillis: legacyStartMillis,
            legacyLocation: legacyLocation,
            legacyEventId: legacyEventId,
            nowMillis: nowMillis
        )
        let mirror = AppointmentAgenda.legacyMirror(appointments, nowMillis: nowMillis)
        appointmentDate = legacyDate ?? mirror.startMillis.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        appointmentLocation = legacyLocation ?? mirror.location
        googleCalendarEventId = legacyEventId ?? mirror.eventId
        isPinned = d["isPinned"] as? Bool ?? false
        salesStage = SalesStage(rawValue: d["salesStage"] as? String ?? "")
            ?? (category.localizedCaseInsensitiveContains("Client") ? .inForce : ((appointmentDate != nil || !appointments.isEmpty) ? .apptSet : .newLead))
        recruitStage = RecruitStage(rawValue: d["recruitStage"] as? String ?? "") ?? .prospect
        followUpDate = Self.date(d["followUpDate"]); isPaused = d["isPaused"] as? Bool ?? false; isClosed = d["isClosed"] as? Bool ?? false
        pausedReason = d["pausedReason"] as? String
        lastAttemptedContact = Self.date(d["lastAttemptedContact"]); lastConnectedContact = Self.date(d["lastConnectedContact"])
        let market = (d["targetMarket"] as? String ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        tmMarried = d["targetMarket"] is String ? market.contains("married") : (d["tmMarried"] as? Bool ?? false)
        tmAge = d["targetMarket"] is String ? market.contains("age 25-55") : (d["tmAge"] as? Bool ?? false)
        tmChildren = d["targetMarket"] is String ? market.contains("children") : (d["tmChildren"] as? Bool ?? false)
        tmHomeowner = d["targetMarket"] is String ? market.contains("homeowner") : (d["tmHomeowner"] as? Bool ?? false)
        tmOccupation = d["targetMarket"] is String ? market.contains("occupation") : (d["tmOccupation"] as? Bool ?? false)
    }
    static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue / 1000) }
        return nil
    }
    static func epochMillis(_ value: Any?) -> Int64? {
        if let timestamp = value as? Timestamp { return Int64(timestamp.dateValue().timeIntervalSince1970 * 1000) }
        return AppointmentAgenda.defaultEpochMillis(value)
    }
    func data(userID: String) -> [String: Any] {
        let market = [(tmMarried, "Married"), (tmAge, "Age 25-55"), (tmChildren, "Children"), (tmHomeowner, "Homeowner"), (tmOccupation, "Occupation")].filter { $0.0 }.map { $0.1 }.joined(separator: ", ")
        return ["ownerId": userID, "name": name, "phone": phone, "email": email, "address": address, "company": company, "jobTitle": title,
                "notes": notes, "category": category, "salesStage": salesStage.rawValue, "recruitStage": recruitStage.rawValue,
                "followUpDate": followUpDate.map { Timestamp(date: $0) } as Any? ?? NSNull(), "isPaused": isPaused, "isClosed": isClosed,
                "pausedReason": pausedReason as Any? ?? NSNull(),
                "lastAttemptedContact": lastAttemptedContact.map { Int64($0.timeIntervalSince1970 * 1000) } as Any? ?? NSNull(),
                "lastConnectedContact": lastConnectedContact.map { Int64($0.timeIntervalSince1970 * 1000) } as Any? ?? NSNull(),
                "tmMarried": tmMarried, "tmAge": tmAge, "tmChildren": tmChildren, "tmHomeowner": tmHomeowner, "tmOccupation": tmOccupation, "targetMarket": market]
    }
    func changes(from original: Lead, userID: String) -> [String: Any] {
        let updated = data(userID: userID)
        let before = original.data(userID: userID)
        var changes: [String: Any] = ["ownerId": userID]
        for (key, value) in updated where key != "ownerId" {
            if !NSDictionary(dictionary: [key: value]).isEqual(to: [key: before[key] ?? NSNull()]) {
                changes[key] = value
            }
        }
        return changes
    }
}

enum LeadAppointmentSync {
    static func readRecords(_ raw: Any?) -> [AppointmentRecord] {
        AppointmentAgenda.parseRecords(raw, epochMillis: Lead.epochMillis)
    }

    static func fields(
        records: [AppointmentRecord],
        nowMillis: Int64,
        forUpdate: Bool,
        fallbackEventId: Int64? = nil
    ) -> [String: Any] {
        let mirror = AppointmentAgenda.legacyMirror(records, nowMillis: nowMillis)
        var values: [String: Any] = [
            AppointmentAgenda.fieldAppointments: AppointmentAgenda.toFieldMaps(records)
        ]
        if let startMillis = mirror.startMillis, startMillis > 0 {
            values["appointmentDate"] = Timestamp(date: Date(timeIntervalSince1970: Double(startMillis) / 1000))
        } else if forUpdate {
            values["appointmentDate"] = FieldValue.delete()
        }
        if let loc = mirror.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            values["appointmentLocation"] = loc
        } else if forUpdate {
            values["appointmentLocation"] = FieldValue.delete()
        }
        let preservedEventId = mirror.eventId ?? (mirror.startMillis != nil ? fallbackEventId : nil)
        if let eventId = preservedEventId, eventId > 0 {
            values["googleCalendarEventId"] = eventId
        } else if forUpdate {
            values["googleCalendarEventId"] = FieldValue.delete()
        }
        return values
    }
}

@MainActor
final class LeadsStore: ObservableObject {
    @Published var leads: [Lead] = []
    @Published var error: String?
    @Published var isLoading = false
    private var listener: ListenerRegistration?
    private var currentUserID: String?
    func start(userID: String) {
        stop(); currentUserID = userID; leads = []; error = nil; isLoading = true
        listener = Firestore.firestore().collection("leads").whereField("ownerId", isEqualTo: userID)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.currentUserID == userID else { return }
                    self.isLoading = false
                    if let error { self.error = error.localizedDescription; return }
                    self.error = nil
                    self.leads = (snapshot?.documents ?? []).map(Lead.init).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    ReminderNotificationService.shared.reconcileLeads(self.leads)
                }
            }
    }
    func createLead(_ lead: Lead, userID: String) async throws -> String {
        try validate(userID)
        let db = Firestore.firestore()
        let ref = db.collection("leads").document()
        var data = lead.data(userID: userID)
        data["timestamp"] = Timestamp(date: Date())
        let batch = db.batch()
        var createdActions: [NextAction] = []
        if let date = lead.followUpDate {
            let due = Self.normalized(date)
            data["followUpDate"] = Timestamp(date: due)
            data["reminderMigrationVersion"] = 1
            let action = ref.collection("next_actions").document()
            let dueMillis = Int64(due.timeIntervalSince1970 * 1000)
            let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
            batch.setData(Self.reminderData(leadID: ref.documentID, userID: userID, date: due).merging(["id": action.documentID], uniquingKeysWith: { _, new in new }), forDocument: action)
            createdActions.append(NextAction(id: action.documentID, leadId: ref.documentID, ownerId: userID, title: "Follow up", dueTime: dueMillis, createdAt: nowMillis))
        }
        batch.setData(data, forDocument: ref)
        try await batch.commit()
        var createdLead = lead
        createdLead.id = ref.documentID
        createdLead.ownerId = userID
        ReminderNotificationService.shared.syncLeadActions(lead: createdLead, actions: createdActions)
        return ref.documentID
    }
    func updateLead(_ lead: Lead, original: Lead, userID: String) async throws {
        try validate(userID)
        guard !lead.id.isEmpty, lead.id == original.id, lead.ownerId == userID, original.ownerId == userID else { throw StoreError.invalidLead }
        var changes = lead.changes(from: original, userID: userID)
        let changesDate = lead.followUpDate != original.followUpDate
        let changesLifecycle = lead.isPaused != original.isPaused || lead.isClosed != original.isClosed
        guard changesDate || changesLifecycle else {
            try await Firestore.firestore().collection("leads").document(lead.id).updateData(changes)
            return
        }
        changes.removeValue(forKey: "followUpDate")
        let newID = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try await writeActions(leadID: lead.id, userID: userID) { transaction, ref, data, snapshots, _ in
            guard Self.sameDate(Lead.date(data["followUpDate"]), original.followUpDate) else { throw StoreError.changedFollowUp }
            var actions = Self.migratedActions(parent: data, snapshots: snapshots, leadID: lead.id, userID: userID, now: now)
            let earliest = actions.filter { $0.status == .pending && $0.dueTime > 0 }.sorted { $0.dueTime == $1.dueTime ? $0.id < $1.id : $0.dueTime < $1.dueTime }.first
            var editedID: String?
            if changesDate {
                if earliest?.appointmentId?.isEmpty == false { throw StoreError.linkedAppointment }
                if var action = earliest {
                    editedID = action.id
                    var patch: [String: Any] = ["id": action.id, "ownerId": userID, "leadId": lead.id]
                    if let date = lead.followUpDate {
                        action.dueTime = Int64(Self.normalized(date).timeIntervalSince1970 * 1000)
                        patch["dueTime"] = action.dueTime
                    } else {
                        action.status = .cancelled; patch["status"] = "CANCELLED"; patch["completedAt"] = now
                    }
                    if snapshots.contains(where: { $0.exists && $0.documentID == action.id }) {
                        transaction.updateData(patch, forDocument: ref.collection("next_actions").document(action.id))
                    } else { transaction.setData(action.data.merging(patch, uniquingKeysWith: { _, new in new }), forDocument: ref.collection("next_actions").document(action.id)) }
                    actions.removeAll { $0.id == action.id }; actions.append(action)
                } else if let date = lead.followUpDate {
                    let action = NextAction(id: newID, leadId: lead.id, ownerId: userID, title: "Follow up",
                        dueTime: Int64(Self.normalized(date).timeIntervalSince1970 * 1000), createdAt: now)
                    transaction.setData(action.data, forDocument: ref.collection("next_actions").document(newID))
                    actions.append(action); editedID = newID
                }
            }
            let existing = Set(snapshots.filter(\.exists).map(\.documentID))
            for action in actions where !existing.contains(action.id) && action.id != editedID {
                transaction.setData(action.data, forDocument: ref.collection("next_actions").document(action.id))
            }
            var patch = changes
            patch["followUpDate"] = Self.followUpPatch(actions, paused: lead.isPaused, closed: lead.isClosed)
            patch["reminderMigrationVersion"] = 1
            transaction.updateData(patch, forDocument: ref)
        }
    }
    private static func normalized(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60)
    }
    private static func sameDate(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (left?, right?): return abs(left.timeIntervalSince1970 - right.timeIntervalSince1970) < 0.001
        default: return false
        }
    }
    private static func reminderData(leadID: String, userID: String, date: Date) -> [String: Any] {
        ["ownerId": userID, "leadId": leadID, "workflow": "GENERAL", "type": "TO_DO", "title": "Follow up", "notes": "", "dueTime": Int64(date.timeIntervalSince1970 * 1000), "status": "PENDING", "createdAt": Int64(Date().timeIntervalSince1970 * 1000)]
    }
    func deleteLead(_ lead: Lead, userID: String) async throws {
        try validate(userID)
        guard !lead.id.isEmpty, lead.ownerId == userID else { throw StoreError.invalidLead }
        try await Firestore.firestore().collection("leads").document(lead.id).delete()
        var deleted = lead
        deleted.isClosed = true
        ReminderNotificationService.shared.syncLeadActions(lead: deleted, actions: [])
    }
    func deleteActivityRecord(leadID: String, userID: String, activityID: String) async throws {
        try validate(userID)
        guard !leadID.isEmpty, !leadID.contains("/"), !activityID.isEmpty else { throw StoreError.invalidLead }
        let db = Firestore.firestore()
        let leadRef = db.collection("leads").document(leadID)
        let activityRef = leadRef.collection("activity_records").document(activityID)
        let listed = try await leadRef.collection("activity_records").getDocuments(source: .server)
        let remaining = listed.documents
            .filter { $0.documentID != activityID }
            .map { ActivityRecord(document: $0, leadID: leadID) }
        let timestamps = OutcomeSavePlanner.contactTimestamps(from: remaining)
        _ = try await db.runTransaction { transaction, pointer -> Any? in
            do {
                let leadSnap = try transaction.getDocument(leadRef)
                guard let data = leadSnap.data(), data["ownerId"] as? String == userID else { throw StoreError.invalidLead }
                let activitySnap = try transaction.getDocument(activityRef)
                guard activitySnap.exists else { throw StoreError.activityNotFound }
                transaction.deleteDocument(activityRef)
                let existingNotes = data["notes"] as? String ?? ""
                let updatedNotes = NoteUtils.removeNote(withEventId: activityID, from: existingNotes)
                var updates: [String: Any] = ["ownerId": userID]
                if updatedNotes != existingNotes { updates["notes"] = updatedNotes }
                if let attempted = timestamps.attempted {
                    updates["lastAttemptedContact"] = attempted
                } else {
                    updates["lastAttemptedContact"] = FieldValue.delete()
                }
                if let connected = timestamps.connected {
                    updates["lastConnectedContact"] = connected
                } else {
                    updates["lastConnectedContact"] = FieldValue.delete()
                }
                transaction.updateData(updates, forDocument: leadRef)
                return nil
            } catch {
                pointer?.pointee = error as NSError
                return nil
            }
        }
    }
    private func validate(_ userID: String) throws {
        guard currentUserID == userID, Auth.auth().currentUser?.uid == userID else { throw StoreError.invalidSession }
    }
    func stop() { listener?.remove(); listener = nil; currentUserID = nil }
    deinit { listener?.remove() }
    enum StoreError: LocalizedError {
        case invalidSession, invalidLead, changedFollowUp, linkedAppointment, invalidReminder, reminderNotOpen, reminderTitle, reminderDate
        case invalidAppointment, newerAppointment, staleNotes, activityNotFound
        var errorDescription: String? {
            switch self {
            case .activityNotFound: return "That activity entry was already removed."
            case .invalidReminder: return "That reminder is no longer available."
            case .reminderNotOpen: return "That reminder is no longer open."
            case .reminderTitle: return "Please enter a title."
            case .reminderDate: return "Choose a time that hasn't already passed."
            case .invalidSession: return "Your session has changed. Please sign in again."
            case .invalidLead: return "This contact does not belong to your account."
            case .changedFollowUp: return "The follow-up changed on another device. Reopen this contact and try again."
            case .linkedAppointment: return "This follow-up is linked to an appointment. Edit or reschedule the appointment instead."
            case .invalidAppointment: return "That appointment is no longer on this contact."
            case .newerAppointment: return "A newer appointment change was kept."
            case .staleNotes: return "Notes changed elsewhere. Copy your edits, then reopen notes."
            }
        }
    }
}
extension NextAction {
    init(document: DocumentSnapshot, leadID: String) {
        let d = document.data() ?? [:]
        self.init(id: document.documentID, leadId: d["leadId"] as? String ?? leadID, ownerId: d["ownerId"] as? String ?? "",
            workflow: WorkflowType(rawValue: d["workflow"] as? String ?? "") ?? .general,
            type: ActionType(rawValue: d["type"] as? String ?? "") ?? .toDo,
            title: d["title"] as? String ?? "", notes: d["notes"] as? String ?? "",
            dueTime: Lead.date(d["dueTime"]).map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0,
            status: ActionStatus(rawValue: d["status"] as? String ?? "") ?? .pending,
            appointmentId: d["appointmentId"] as? String,
            createdAt: Lead.date(d["createdAt"]).map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0,
            completedAt: Lead.date(d["completedAt"]).map { Int64($0.timeIntervalSince1970 * 1000) }, reason: d["reason"] as? String)
    }
}
extension ActivityRecord {
    init(document: DocumentSnapshot, leadID: String) {
        let d = document.data() ?? [:]
        self.init(id: document.documentID, leadId: d["leadId"] as? String ?? leadID, ownerId: d["ownerId"] as? String ?? "",
            type: ActionType(rawValue: d["type"] as? String ?? "") ?? .toDo,
            outcome: d["outcome"] as? String ?? "", note: d["note"] as? String ?? "",
            timestamp: Lead.date(d["timestamp"]).map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0)
    }
}

@MainActor
final class LeadActivityStore: ObservableObject {
    @Published var actions: [NextAction] = []
    @Published var activities: [ActivityRecord] = []
    @Published var actionsLoading = true
    @Published var activitiesLoading = true
    @Published var actionsError: String?
    @Published var activitiesError: String?
    private var listeners: [ListenerRegistration] = []
    private var generation = UUID()
    func start(leadID: String, userID: String) {
        stop()
        let token = generation
        actions = []; activities = []; actionsError = nil; activitiesError = nil
        actionsLoading = true; activitiesLoading = true
        guard Auth.auth().currentUser?.uid == userID else { return }
        let lead = Firestore.firestore().collection("leads").document(leadID)
        listeners.append(lead.collection("next_actions").addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self, self.generation == token, Auth.auth().currentUser?.uid == userID else { return }
                self.actionsLoading = false; self.actionsError = error?.localizedDescription
                if let snapshot {
                    let loaded = snapshot.documents.map { NextAction(document: $0, leadID: leadID) }
                    let sorted = loaded.sorted { lhs, rhs in
                        if lhs.dueTime == rhs.dueTime { return lhs.id < rhs.id }
                        return lhs.dueTime < rhs.dueTime
                    }
                    self.actions = sorted
                    ReminderNotificationService.shared.syncActionsIfKnownLead(leadID: leadID, actions: sorted)
                }
            }
        })
        listeners.append(lead.collection("activity_records").addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self, self.generation == token, Auth.auth().currentUser?.uid == userID else { return }
                self.activitiesLoading = false; self.activitiesError = error?.localizedDescription
                if let snapshot { self.activities = snapshot.documents.map { ActivityRecord(document: $0, leadID: leadID) } }
            }
        })
    }
    func stop() { generation = UUID(); listeners.forEach { $0.remove() }; listeners = [] }
    deinit { listeners.forEach { $0.remove() } }
}

extension LeadsStore {
    /// Queries cannot run inside an Apple Firestore transaction. Discover references on the
    /// server, then re-read them and the parent before any writes. If the parent or query
    /// results changed, discover again rather than committing a stale reminder projection.
    private func writeActions(leadID: String, userID: String, extraReads: [DocumentReference] = [],
        idempotencyRef: DocumentReference? = nil,
        body: @escaping (FirebaseFirestore.Transaction, DocumentReference, [String: Any], [DocumentSnapshot], [DocumentSnapshot]) throws -> Void) async throws {
        try validate(userID)
        guard !leadID.isEmpty, !leadID.contains("/") else { throw StoreError.invalidLead }
        let db = Firestore.firestore(), leadRef = Firestore.firestore().collection("leads").document(leadID)
        for attempt in 0..<3 {
            let before = try await leadRef.getDocument(source: .server)
            guard before.data()?["ownerId"] as? String == userID else { throw StoreError.invalidLead }
            let listed = try await leadRef.collection("next_actions").whereField("status", isEqualTo: "PENDING").getDocuments(source: .server)
            let any = try await leadRef.collection("next_actions").limit(to: 1).getDocuments(source: .server)
            let legacy = leadRef.collection("next_actions").document("legacy_followup_\(OutcomeSavePlanner.sanitizeOperationId(leadID))")
            let refs = Dictionary((listed.documents.map(\.reference) + any.documents.map(\.reference) + [legacy]).map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a }).values.sorted { $0.path < $1.path }
            try validate(userID)
            do {
                _ = try await db.runTransaction { transaction, pointer -> Any? in
                    do {
                        if let idempotencyRef, try transaction.getDocument(idempotencyRef).exists { return nil }
                        let parent = try transaction.getDocument(leadRef)
                        guard let data = parent.data(), data["ownerId"] as? String == userID else { throw StoreError.invalidLead }
                        guard NSDictionary(dictionary: data).isEqual(to: before.data() ?? [:]) else { throw StoreError.changedFollowUp }
                        let actions = try refs.map { try transaction.getDocument($0) }
                        let extras = try extraReads.map { try transaction.getDocument($0) }
                        for old in listed.documents {
                            guard let fresh = actions.first(where: { $0.documentID == old.documentID }),
                                NSDictionary(dictionary: fresh.data() ?? [:]).isEqual(to: old.data()) else { throw StoreError.changedFollowUp }
                        }
                        for snapshot in actions + extras where snapshot.exists && snapshot.reference.parent.collectionID == "next_actions" {
                            let childOwner = snapshot.data()?["ownerId"] as? String ?? ""
                            let childLead = snapshot.data()?["leadId"] as? String ?? ""
                            guard (childOwner.isEmpty || childOwner == userID), (childLead.isEmpty || childLead == leadID) else { throw StoreError.invalidLead }
                        }
                        try body(transaction, leadRef, data, actions, extras)
                        return nil
                    } catch { pointer?.pointee = error as NSError; return nil }
                }
                await refreshLeadNotifications(leadID: leadID, userID: userID)
                return
            } catch {
                let nsError = error as NSError, stale = StoreError.changedFollowUp as NSError
                if attempt < 2 && nsError.domain == stale.domain && nsError.code == stale.code { continue }
                throw error
            }
        }
    }
    private func refreshLeadNotifications(leadID: String, userID: String) async {
        guard Auth.auth().currentUser?.uid == userID else { return }
        let leadRef = Firestore.firestore().collection("leads").document(leadID)
        guard let parent = try? await leadRef.getDocument(),
              parent.exists,
              parent.data()?["ownerId"] as? String == userID,
              let actionsSnap = try? await leadRef.collection("next_actions").getDocuments() else {
            return
        }
        let d = parent.data() ?? [:]
        var syncedLead = leads.first(where: { $0.id == leadID }) ?? Lead()
        syncedLead.id = leadID
        syncedLead.ownerId = userID
        syncedLead.name = d["name"] as? String ?? syncedLead.name
        syncedLead.isPaused = d["isPaused"] as? Bool ?? false
        syncedLead.isClosed = d["isClosed"] as? Bool ?? false
        syncedLead.followUpDate = Lead.date(d["followUpDate"])
        let actions = actionsSnap.documents.map { NextAction(document: $0, leadID: leadID) }
        ReminderNotificationService.shared.syncLeadActions(lead: syncedLead, actions: actions)
    }
    private static func followUpPatch(_ pending: [NextAction], paused: Bool, closed: Bool) -> Any {
        guard let millis = OutcomeSavePlanner.followUpMillis(pending, paused: paused, closed: closed) else { return FieldValue.delete() }
        return Timestamp(date: Date(timeIntervalSince1970: Double(millis) / 1000))
    }
    private static func migratedActions(parent: [String: Any], snapshots: [DocumentSnapshot], leadID: String, userID: String, now: Int64) -> [NextAction] {
        var actions = snapshots.filter(\.exists).map { NextAction(document: $0, leadID: leadID) }
        if ((parent["reminderMigrationVersion"] as? NSNumber)?.intValue ?? 0) < 1,
            actions.isEmpty, let date = Lead.date(parent["followUpDate"]), date.timeIntervalSince1970 > 0 {
            actions.append(NextAction(id: "legacy_followup_\(OutcomeSavePlanner.sanitizeOperationId(leadID))", leadId: leadID,
                ownerId: userID, title: "Follow up", dueTime: Int64(normalized(date).timeIntervalSince1970 * 1000), createdAt: now))
        }
        return actions
    }
    private static func migratedAppointmentsFromData(_ data: [String: Any], leadID: String, now: Int64) -> ([AppointmentRecord], Int64?) {
        let fresh = LeadAppointmentSync.readRecords(data[AppointmentAgenda.fieldAppointments])
        let legacyStart = Lead.epochMillis(data["appointmentDate"])
        let legacyLocation = (data["appointmentLocation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyEventId = AppointmentAgenda.longOrNull(data["googleCalendarEventId"]).flatMap { $0 > 0 ? $0 : nil }
        let migrated = AppointmentAgenda.migrateAppointments(
            leadId: leadID,
            existing: fresh,
            legacyStartMillis: legacyStart,
            legacyLocation: (legacyLocation?.isEmpty == false) ? legacyLocation : nil,
            legacyEventId: legacyEventId,
            nowMillis: now
        )
        return (migrated, legacyEventId)
    }
    func saveOutcome(_ request: OutcomeSaveRequest) async throws {
        try validate(request.ownerId)
        guard !request.leadId.isEmpty, !request.leadId.contains("/") else { throw StoreError.invalidLead }
        let leadRef = Firestore.firestore().collection("leads").document(request.leadId)
        let activityRef = leadRef.collection("activity_records").document(OutcomeSavePlanner.activityDocumentId(request.operationId))
        let target = request.currentActionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !target.contains("/") else { throw StoreError.invalidReminder }
        let targetRefs = target.isEmpty ? [] : [leadRef.collection("next_actions").document(target)]
        try await writeActions(leadID: request.leadId, userID: request.ownerId, extraReads: targetRefs, idempotencyRef: activityRef) { transaction, ref, data, snapshots, extras in
            // Match OutcomeSavePlanner: outcome logging resolves existing actions without
            // inventing a legacy action. The migration marker makes this decision durable.
            var pending = snapshots.filter(\.exists).map { NextAction(document: $0, leadID: request.leadId) }.filter { $0.status == .pending }
            for extra in extras where extra.exists && !pending.contains(where: { $0.id == extra.documentID }) {
                let action = NextAction(document: extra, leadID: request.leadId)
                if action.status == .pending { pending.append(action) }
            }
            let plan = OutcomeSavePlanner.plan(request, existingNotes: data["notes"] as? String ?? "", existingCategory: data["category"] as? String ?? "", pending: pending)
            if let id = plan.completeActionId, let status = plan.completeStatus,
                let action = pending.first(where: { $0.id == id }) {
                var updates: [String: Any] = ["id": id, "ownerId": request.ownerId, "leadId": request.leadId,
                    "status": status.rawValue, "completedAt": request.nowMillis]
                if let reason = plan.completeReason { updates["reason"] = reason }
                transaction.updateData(updates, forDocument: ref.collection("next_actions").document(action.id))
                pending.removeAll { $0.id == id }
            }
            if let next = plan.newAction {
                transaction.setData(next.data, forDocument: ref.collection("next_actions").document(next.id))
                pending.removeAll { $0.id == next.id }; pending.append(next)
            }
            var updates: [String: Any] = ["ownerId": request.ownerId, "reminderMigrationVersion": 1]
            let paused = plan.isPaused ?? (data["isPaused"] as? Bool ?? false)
            let closed = plan.isClosed ?? (data["isClosed"] as? Bool ?? false)
            updates["followUpDate"] = Self.followUpPatch(pending, paused: paused, closed: closed)
            if let stage = request.stage { updates[stage.pipelineType == .sales ? "salesStage" : "recruitStage"] = stage.newStageId }
            if let category = plan.category { updates["category"] = category }
            if let notes = plan.notes { updates["notes"] = notes }
            if let paused = plan.isPaused { updates["isPaused"] = paused }
            if let closed = plan.isClosed { updates["isClosed"] = closed }
            if plan.writePausedReason {
                let reason = request.lifecycleReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                updates["pausedReason"] = request.lifecycle != .unchanged && !reason.isEmpty ? reason as Any : FieldValue.delete()
            }
            if let attempted = plan.lastAttemptedContact { updates["lastAttemptedContact"] = attempted }
            if let connected = plan.lastConnectedContact { updates["lastConnectedContact"] = connected }
            if let apptId = request.appointmentId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !apptId.isEmpty,
               let apptOutcome = OutcomeSavePlanner.appointmentOutcome(for: request.outcome) {
                let (migrated, legacyEventId) = Self.migratedAppointmentsFromData(data, leadID: request.leadId, now: request.nowMillis)
                let baseUpdatedAt = migrated.first(where: { $0.id == apptId })?.updatedAtMillis ?? 0
                let mutationResult = AppointmentSync.applyAppointmentMutation(
                    leadId: request.leadId,
                    fresh: migrated,
                    mutation: .saveOutcome(appointmentId: apptId, outcome: apptOutcome, nowMillis: request.nowMillis, baseUpdatedAtMillis: baseUpdatedAt)
                )
                if mutationResult.keptNewer { throw StoreError.newerAppointment }
                for (key, value) in LeadAppointmentSync.fields(records: mutationResult.records, nowMillis: request.nowMillis, forUpdate: true, fallbackEventId: legacyEventId) {
                    updates[key] = value
                }
            }
            transaction.setData(plan.activity.data, forDocument: activityRef)
            transaction.updateData(updates, forDocument: ref)
        }
    }
    func saveAppointment(
        leadID: String,
        userID: String,
        appointmentID: String? = nil,
        startDate: Date,
        location: String? = nil,
        note: String = "",
        scheduleReminder: Bool = true,
        baseUpdatedAtMillis: Int64? = nil
    ) async throws -> String {
        try validate(userID)
        guard !leadID.isEmpty, !leadID.contains("/") else { throw StoreError.invalidLead }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let startMillis = Int64(Self.normalized(startDate).timeIntervalSince1970 * 1000)
        guard startMillis > 0 else { throw StoreError.reminderDate }
        let cleanApptID = appointmentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let targetID = cleanApptID.isEmpty ? AppointmentAgenda.newAppointmentId() : cleanApptID
        let cleanLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLocation = (cleanLocation?.isEmpty == false) ? cleanLocation : nil
        let reminderDocID = "appt_\(OutcomeSavePlanner.sanitizeOperationId(targetID))"
        let leadRef = Firestore.firestore().collection("leads").document(leadID)
        let reminderRef = leadRef.collection("next_actions").document(reminderDocID)
        try await writeActions(leadID: leadID, userID: userID, extraReads: [reminderRef]) { transaction, ref, data, snapshots, extras in
            let (migrated, legacyEventId) = Self.migratedAppointmentsFromData(data, leadID: leadID, now: now)
            let existing = migrated.first(where: { $0.id == targetID })
            let base = baseUpdatedAtMillis ?? existing?.updatedAtMillis ?? 0
            let record = AppointmentRecord(
                id: targetID,
                startMillis: startMillis,
                location: resolvedLocation,
                eventId: existing?.eventId ?? (migrated.isEmpty ? legacyEventId : nil),
                status: .scheduled,
                originalInstanceTime: existing?.originalInstanceTime,
                updatedAtMillis: now
            )
            let result = AppointmentSync.applyAppointmentMutation(
                leadId: leadID,
                fresh: migrated,
                mutation: .upsert(record: record, baseUpdatedAtMillis: base)
            )
            if result.keptNewer { throw StoreError.newerAppointment }
            var actions = Self.migratedActions(parent: data, snapshots: snapshots, leadID: leadID, userID: userID, now: now)
            let known = Set((snapshots + extras).filter(\.exists).map(\.documentID))
            for legacy in actions where !known.contains(legacy.id) {
                transaction.setData(legacy.data, forDocument: ref.collection("next_actions").document(legacy.id))
            }
            if let linkedIndex = actions.firstIndex(where: { $0.status == .pending && $0.appointmentId == targetID }) {
                var linked = actions[linkedIndex]
                linked.dueTime = startMillis
                linked.type = .meeting
                if linked.title.isEmpty { linked.title = "Appointment" }
                linked.notes = resolvedLocation ?? linked.notes
                transaction.setData(linked.data, forDocument: ref.collection("next_actions").document(linked.id))
                actions[linkedIndex] = linked
            } else if scheduleReminder {
                let reminder = NextAction(
                    id: reminderDocID,
                    leadId: leadID,
                    ownerId: userID,
                    workflow: .sales,
                    type: .meeting,
                    title: "Appointment",
                    notes: resolvedLocation ?? "",
                    dueTime: startMillis,
                    status: .pending,
                    appointmentId: targetID,
                    createdAt: now
                )
                transaction.setData(reminder.data, forDocument: reminderRef)
                actions.removeAll { $0.id == reminder.id }
                actions.append(reminder)
            }
            var updates = LeadAppointmentSync.fields(records: result.records, nowMillis: now, forUpdate: true, fallbackEventId: legacyEventId)
            updates["ownerId"] = userID
            updates["timestamp"] = Timestamp(date: Date(timeIntervalSince1970: Double(now) / 1000))
            updates["reminderMigrationVersion"] = 1
            updates["followUpDate"] = Self.followUpPatch(actions, paused: data["isPaused"] as? Bool ?? false, closed: data["isClosed"] as? Bool ?? false)
            let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanNote.isEmpty {
                let existingNotes = data["notes"] as? String ?? ""
                updates["notes"] = NoteUtils.prependNote(existingNotes, content: cleanNote, date: Date(timeIntervalSince1970: Double(now) / 1000))
            }
            let currentSalesStage = data["salesStage"] as? String ?? ""
            if currentSalesStage.isEmpty || currentSalesStage == SalesStage.newLead.rawValue || currentSalesStage == SalesStage.contacted.rawValue {
                updates["salesStage"] = SalesStage.apptSet.rawValue
            }
            transaction.updateData(updates, forDocument: ref)
        }
        return targetID
    }
    func rescheduleAppointment(
        leadID: String,
        userID: String,
        appointmentID: String,
        newDate: Date,
        location: String? = nil,
        rememberInstance: Bool = false,
        baseUpdatedAtMillis: Int64? = nil,
        note: String = ""
    ) async throws {
        try validate(userID)
        guard !leadID.isEmpty, !leadID.contains("/") else { throw StoreError.invalidLead }
        let cleanApptID = appointmentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanApptID.isEmpty else { throw StoreError.invalidAppointment }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let newStartMillis = Int64(Self.normalized(newDate).timeIntervalSince1970 * 1000)
        guard newStartMillis > 0 else { throw StoreError.reminderDate }
        try await writeActions(leadID: leadID, userID: userID) { transaction, ref, data, snapshots, _ in
            let (migrated, legacyEventId) = Self.migratedAppointmentsFromData(data, leadID: leadID, now: now)
            guard let current = migrated.first(where: { $0.id == cleanApptID }) else {
                throw StoreError.invalidAppointment
            }
            let base = baseUpdatedAtMillis ?? current.updatedAtMillis
            var result = AppointmentSync.applyAppointmentMutation(
                leadId: leadID,
                fresh: migrated,
                mutation: .reschedule(
                    appointmentId: cleanApptID,
                    newStartMillis: newStartMillis,
                    nowMillis: now,
                    rememberInstance: rememberInstance,
                    baseUpdatedAtMillis: base
                )
            )
            if result.keptNewer { throw StoreError.newerAppointment }
            if let location {
                let cleanLoc = location.trimmingCharacters(in: .whitespacesAndNewlines)
                let newLoc = cleanLoc.isEmpty ? nil : cleanLoc
                var updatedRecords = result.records
                if let idx = updatedRecords.firstIndex(where: { $0.id == cleanApptID }), updatedRecords[idx].location != newLoc {
                    updatedRecords[idx].location = newLoc
                    updatedRecords[idx].updatedAtMillis = now
                    result = AppointmentSync.MutationResult(records: updatedRecords, changed: true, targetId: cleanApptID, keptNewer: false)
                }
            }
            var actions = Self.migratedActions(parent: data, snapshots: snapshots, leadID: leadID, userID: userID, now: now)
            let known = Set(snapshots.filter(\.exists).map(\.documentID))
            for legacy in actions where !known.contains(legacy.id) {
                transaction.setData(legacy.data, forDocument: ref.collection("next_actions").document(legacy.id))
            }
            for idx in actions.indices where actions[idx].status == .pending && actions[idx].appointmentId == cleanApptID {
                actions[idx].dueTime = newStartMillis
                if let loc = location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                    actions[idx].notes = loc
                }
                transaction.setData(actions[idx].data, forDocument: ref.collection("next_actions").document(actions[idx].id))
            }
            var updates = LeadAppointmentSync.fields(records: result.records, nowMillis: now, forUpdate: true, fallbackEventId: legacyEventId)
            updates["ownerId"] = userID
            updates["timestamp"] = Timestamp(date: Date(timeIntervalSince1970: Double(now) / 1000))
            updates["reminderMigrationVersion"] = 1
            updates["followUpDate"] = Self.followUpPatch(actions, paused: data["isPaused"] as? Bool ?? false, closed: data["isClosed"] as? Bool ?? false)
            let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanNote.isEmpty {
                let actID = "act_resched_\(OutcomeSavePlanner.sanitizeOperationId(cleanApptID))_\(now)"
                let existingNotes = data["notes"] as? String ?? ""
                updates["notes"] = NoteUtils.prependNote(existingNotes, content: cleanNote, eventId: actID, date: Date(timeIntervalSince1970: Double(now) / 1000))
                let activity = ActivityRecord(id: actID, leadId: leadID, ownerId: userID, type: .meeting, outcome: "Rescheduled", note: cleanNote, timestamp: now)
                transaction.setData(activity.data, forDocument: ref.collection("activity_records").document(actID))
            }
            transaction.updateData(updates, forDocument: ref)
        }
    }
    func recordAppointmentOutcome(
        leadID: String,
        userID: String,
        appointmentID: String,
        outcome: AppointmentOutcome,
        baseUpdatedAtMillis: Int64? = nil,
        note: String = ""
    ) async throws {
        try validate(userID)
        guard !leadID.isEmpty, !leadID.contains("/") else { throw StoreError.invalidLead }
        let cleanApptID = appointmentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanApptID.isEmpty else { throw StoreError.invalidAppointment }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try await writeActions(leadID: leadID, userID: userID) { transaction, ref, data, snapshots, _ in
            let (migrated, legacyEventId) = Self.migratedAppointmentsFromData(data, leadID: leadID, now: now)
            guard let current = migrated.first(where: { $0.id == cleanApptID }) else {
                throw StoreError.invalidAppointment
            }
            let base = baseUpdatedAtMillis ?? current.updatedAtMillis
            let result = AppointmentSync.applyAppointmentMutation(
                leadId: leadID,
                fresh: migrated,
                mutation: .saveOutcome(
                    appointmentId: cleanApptID,
                    outcome: outcome,
                    nowMillis: now,
                    baseUpdatedAtMillis: base
                )
            )
            if result.keptNewer { throw StoreError.newerAppointment }
            var actions = Self.migratedActions(parent: data, snapshots: snapshots, leadID: leadID, userID: userID, now: now)
            let known = Set(snapshots.filter(\.exists).map(\.documentID))
            for legacy in actions where !known.contains(legacy.id) {
                transaction.setData(legacy.data, forDocument: ref.collection("next_actions").document(legacy.id))
            }
            for idx in actions.indices where actions[idx].status == .pending && actions[idx].appointmentId == cleanApptID {
                actions[idx].status = (outcome == .completed) ? .completed : .cancelled
                actions[idx].completedAt = now
                transaction.setData(actions[idx].data, forDocument: ref.collection("next_actions").document(actions[idx].id))
            }
            var updates = LeadAppointmentSync.fields(records: result.records, nowMillis: now, forUpdate: true, fallbackEventId: legacyEventId)
            updates["ownerId"] = userID
            updates["timestamp"] = Timestamp(date: Date(timeIntervalSince1970: Double(now) / 1000))
            updates["reminderMigrationVersion"] = 1
            updates["followUpDate"] = Self.followUpPatch(actions.filter { $0.status == .pending }, paused: data["isPaused"] as? Bool ?? false, closed: data["isClosed"] as? Bool ?? false)
            updates["lastAttemptedContact"] = now
            if outcome == .completed {
                updates["lastConnectedContact"] = now
            }
            let actID = "act_appt_\(OutcomeSavePlanner.sanitizeOperationId(cleanApptID))_\(now)"
            let outcomeLabel: String
            switch outcome {
            case .completed: outcomeLabel = "Meeting completed"
            case .noShow: outcomeLabel = "No-show"
            case .canceled: outcomeLabel = "Canceled"
            }
            let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanNote.isEmpty {
                let existingNotes = data["notes"] as? String ?? ""
                updates["notes"] = NoteUtils.prependNote(existingNotes, content: cleanNote, eventId: actID, date: Date(timeIntervalSince1970: Double(now) / 1000))
            }
            let activity = ActivityRecord(id: actID, leadId: leadID, ownerId: userID, type: .meeting, outcome: outcomeLabel, note: cleanNote, timestamp: now)
            transaction.setData(activity.data, forDocument: ref.collection("activity_records").document(actID))
            transaction.updateData(updates, forDocument: ref)
        }
    }
    func createReminder(leadID: String, userID: String, actionID: String, title: String, notes: String, type: ActionType, date: Date) async throws {
        try validate(userID)
        guard !leadID.isEmpty, !leadID.contains("/") else { throw StoreError.invalidLead }
        let now = Int64(Date().timeIntervalSince1970 * 1000), due = Self.normalized(date)
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.reminderTitle }
        guard due > Date() else { throw StoreError.reminderDate }
        let id = OutcomeSavePlanner.sanitizeOperationId(actionID)
        let ref = Firestore.firestore().collection("leads").document(leadID).collection("next_actions").document(id)
        try await writeActions(leadID: leadID, userID: userID, idempotencyRef: ref) { transaction, lead, data, snapshots, _ in
            var actions = Self.migratedActions(parent: data, snapshots: snapshots, leadID: leadID, userID: userID, now: now)
            let action = NextAction(id: id, leadId: leadID, ownerId: userID, type: type, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines), dueTime: Int64(due.timeIntervalSince1970 * 1000), createdAt: now)
            let known = Set(snapshots.filter(\.exists).map(\.documentID))
            for legacy in actions where !known.contains(legacy.id) { transaction.setData(legacy.data, forDocument: lead.collection("next_actions").document(legacy.id)) }
            actions.append(action)
            transaction.setData(action.data, forDocument: ref)
            transaction.updateData(["ownerId": userID, "reminderMigrationVersion": 1,
                "followUpDate": Self.followUpPatch(actions, paused: data["isPaused"] as? Bool ?? false, closed: data["isClosed"] as? Bool ?? false)], forDocument: lead)
        }
    }
    func completeReminder(leadID: String, userID: String, actionID: String) async throws {
        try await changeReminder(leadID: leadID, userID: userID, actionID: actionID, status: .completed)
    }
    func cancelReminder(leadID: String, userID: String, actionID: String, reason: String = "Deleted") async throws {
        try await changeReminder(leadID: leadID, userID: userID, actionID: actionID, status: .cancelled, reason: reason)
    }
    func rescheduleReminder(leadID: String, userID: String, actionID: String, date: Date) async throws {
        try await changeReminder(leadID: leadID, userID: userID, actionID: actionID, date: date)
    }
    private func changeReminder(leadID: String, userID: String, actionID: String, status: ActionStatus? = nil, reason: String? = nil, date: Date? = nil) async throws {
        try validate(userID)
        guard !leadID.isEmpty, !leadID.contains("/") else { throw StoreError.invalidLead }
        guard !actionID.isEmpty, !actionID.contains("/") else { throw StoreError.invalidReminder }
        let leadRef = Firestore.firestore().collection("leads").document(leadID)
        let ref = leadRef.collection("next_actions").document(actionID)
        let activity = leadRef.collection("activity_records").document("act_reminder_completed_\(OutcomeSavePlanner.sanitizeOperationId(actionID))")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try await writeActions(leadID: leadID, userID: userID, extraReads: [ref, activity]) { transaction, lead, data, snapshots, extras in
            guard let snapshot = extras.first, snapshot.exists else { throw StoreError.invalidReminder }
            var action = NextAction(document: snapshot, leadID: leadID)
            if action.status == status { return }
            guard action.status == .pending else { throw StoreError.reminderNotOpen }
            var updates: [String: Any] = ["id": action.id, "ownerId": userID, "leadId": leadID]
            if let date {
                let due = Self.normalized(date)
                let dueMillis = Int64(due.timeIntervalSince1970 * 1000)
                let previous = Int64(Self.normalized(action.dueDate).timeIntervalSince1970 * 1000)
                guard dueMillis == previous || due > Date(timeIntervalSince1970: Double(now) / 1000) else { throw StoreError.reminderDate }
                action.dueTime = dueMillis
                updates["dueTime"] = action.dueTime
                updates["completedAt"] = FieldValue.delete()
                updates["reason"] = FieldValue.delete()
            }
            if let status {
                action.status = status; updates["status"] = status.rawValue; updates["completedAt"] = now
                if let reason, !reason.isEmpty { updates["reason"] = reason }
            }
            var actions = Self.migratedActions(parent: data, snapshots: snapshots, leadID: leadID, userID: userID, now: now)
            actions.removeAll { $0.id == actionID }; actions.append(action)
            if status == .completed, extras.last?.exists == false {
                let note = [action.title.trimmingCharacters(in: .whitespacesAndNewlines), action.notes.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }.joined(separator: "\n")
                let record = ActivityRecord(id: activity.documentID, leadId: leadID, ownerId: userID, type: .toDo, outcome: "Reminder completed", note: note, timestamp: now)
                transaction.setData(record.data, forDocument: activity)
            }
            transaction.updateData(updates, forDocument: ref)
            transaction.updateData(["ownerId": userID, "reminderMigrationVersion": 1,
                "followUpDate": Self.followUpPatch(actions, paused: data["isPaused"] as? Bool ?? false, closed: data["isClosed"] as? Bool ?? false)], forDocument: lead)
        }
    }
    func addContactNote(leadID: String, userID: String, note: String, now: Date = Date()) async throws {
        try validate(userID)
        guard !leadID.isEmpty, !leadID.contains("/") else { throw StoreError.invalidLead }
        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let db = Firestore.firestore()
        let leadRef = db.collection("leads").document(leadID)
        _ = try await db.runTransaction { transaction, pointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(leadRef)
                guard let data = snapshot.data(), data["ownerId"] as? String == userID else { throw StoreError.invalidLead }
                let existingNotes = data["notes"] as? String ?? ""
                let updatedNotes = NoteUtils.prependNote(existingNotes, content: clean, date: now)
                transaction.updateData(["ownerId": userID, "notes": updatedNotes], forDocument: leadRef)
                return nil
            } catch {
                pointer?.pointee = error as NSError
                return nil
            }
        }
    }
    func updateContactNotes(leadID: String, userID: String, notes: String, originalNotes: String) async throws {
        try validate(userID)
        guard !leadID.isEmpty, !leadID.contains("/") else { throw StoreError.invalidLead }
        guard notes != originalNotes else { return }
        let db = Firestore.firestore()
        let leadRef = db.collection("leads").document(leadID)
        _ = try await db.runTransaction { transaction, pointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(leadRef)
                guard let data = snapshot.data(), data["ownerId"] as? String == userID else { throw StoreError.invalidLead }
                let remoteNotes = data["notes"] as? String ?? ""
                guard NoteUtils.canApplyEditedNotes(remoteNotes: remoteNotes, expectedOriginalNotes: originalNotes) else {
                    throw StoreError.staleNotes
                }
                transaction.updateData(["ownerId": userID, "notes": notes], forDocument: leadRef)
                return nil
            } catch {
                pointer?.pointee = error as NSError
                return nil
            }
        }
    }
}

@MainActor
final class ReminderNotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderNotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var persistedAlarms: [ReminderAlarmState] = []
    @Published var dailyDigestEnabled: Bool
    @Published var dailyDigestHour: Int
    @Published var dailyDigestMinute: Int
    @Published var statusNotice: String?

    var onOpenLead: ((String) -> Void)?
    private var pendingOpenedLeadID: String?
    private var syncedLeadIDs = Set<String>()
    private var latestLeads: [Lead] = []

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let alarmsKey = "rcrm_reminder_alarms.persisted"
    private let syncedLeadsKey = "rcrm_reminder_alarms.synced_leads"
    private let digestEnabledKey = "rcrm_daily_digest.enabled"
    private let digestHourKey = "rcrm_daily_digest.hour"
    private let digestMinuteKey = "rcrm_daily_digest.minute"

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    var needsPermissionPrompt: Bool {
        authorizationStatus == .notDetermined
    }

    var isDenied: Bool {
        authorizationStatus == .denied
    }

    var dailyDigestTimeDate: Date {
        var comps = DateComponents()
        comps.hour = dailyDigestHour
        comps.minute = dailyDigestMinute
        return Calendar.current.date(from: comps) ?? Date()
    }

    override init() {
        if defaults.object(forKey: digestEnabledKey) == nil {
            dailyDigestEnabled = true
        } else {
            dailyDigestEnabled = defaults.bool(forKey: digestEnabledKey)
        }
        if defaults.object(forKey: digestHourKey) == nil {
            dailyDigestHour = ReminderNotificationPlanner.defaultDigestHour
        } else {
            dailyDigestHour = defaults.integer(forKey: digestHourKey)
        }
        if defaults.object(forKey: digestMinuteKey) == nil {
            dailyDigestMinute = ReminderNotificationPlanner.defaultDigestMinute
        } else {
            dailyDigestMinute = defaults.integer(forKey: digestMinuteKey)
        }
        if let data = defaults.data(forKey: alarmsKey),
           let decoded = try? JSONDecoder().decode([ReminderAlarmState].self, from: data) {
            persistedAlarms = decoded
        } else {
            persistedAlarms = []
        }
        syncedLeadIDs = Set(defaults.stringArray(forKey: syncedLeadsKey) ?? [])
        super.init()
    }

    func installDelegate() {
        center.delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    func consumePendingLeadID() -> String? {
        defer { pendingOpenedLeadID = nil }
        return pendingOpenedLeadID
    }

    @MainActor
    func deliverLeadDeepLink(_ leadID: String) {
        let trimmed = leadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let onOpenLead {
            onOpenLead(trimmed)
        } else {
            pendingOpenedLeadID = trimmed
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if isAuthorized {
            restorePersistedAlarms()
            refreshDailyDigest(leads: latestLeads)
        }
    }

    func requestPermission() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            statusNotice = error.localizedDescription
        }
        await refreshAuthorizationStatus()
        if isDenied {
            statusNotice = "Notifications are turned off. Enable them in Settings to receive reminder alerts and your daily briefing."
        } else if isAuthorized {
            statusNotice = nil
            reconcileLeads(latestLeads)
        }
    }

    func setDailyDigestEnabled(_ enabled: Bool) {
        dailyDigestEnabled = enabled
        defaults.set(enabled, forKey: digestEnabledKey)
        refreshDailyDigest(leads: latestLeads)
    }

    func setDailyDigestTime(_ date: Date) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        dailyDigestHour = comps.hour ?? ReminderNotificationPlanner.defaultDigestHour
        dailyDigestMinute = comps.minute ?? ReminderNotificationPlanner.defaultDigestMinute
        defaults.set(dailyDigestHour, forKey: digestHourKey)
        defaults.set(dailyDigestMinute, forKey: digestMinuteKey)
        refreshDailyDigest(leads: latestLeads)
    }

    func sendDailyDigestPreview() async {
        if !isAuthorized {
            await requestPermission()
            guard isAuthorized else { return }
        }
        let summaries = latestLeads.map(Self.summary(for:))
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        guard let plan = ReminderNotificationPlanner.buildDailyDigest(leads: summaries, nowMillis: nowMillis) else {
            statusNotice = "No follow-ups or appointments are due today."
            return
        }
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.subtitle = plan.summaryText
        content.body = plan.bodyLines.joined(separator: "\n")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "\(ReminderNotificationPlanner.dailyDigestIdentifier).preview", content: content, trigger: trigger)
        do {
            try await center.add(request)
            statusNotice = "Daily digest preview sent."
        } catch {
            statusNotice = error.localizedDescription
        }
    }

    func syncActionsIfKnownLead(leadID: String, actions: [NextAction]) {
        guard let lead = latestLeads.first(where: { $0.id == leadID }) else { return }
        syncLeadActions(lead: lead, actions: actions)
    }

    func syncLeadActions(lead: Lead, actions: [NextAction]) {
        syncedLeadIDs.insert(lead.id)
        defaults.set(Array(syncedLeadIDs), forKey: syncedLeadsKey)
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let sync = ReminderNotificationPlanner.syncAlarms(
            leadId: lead.id,
            contactName: lead.name,
            isPaused: lead.isPaused,
            isClosed: lead.isClosed,
            persisted: persistedAlarms,
            actions: actions,
            nowMillis: nowMillis
        )
        if !sync.cancelRequestIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(sync.cancelRequestIds))
            center.removeDeliveredNotifications(withIdentifiers: Array(sync.cancelRequestIds))
        }
        var updated = persistedAlarms.filter { $0.leadId != lead.id || !sync.cancelActionIds.contains($0.actionId) }
        for state in sync.schedule {
            updated.removeAll { $0.id == state.id }
            updated.append(state)
            scheduleNotification(state, nowMillis: nowMillis)
        }
        savePersistedAlarms(updated)
    }

    func reconcileLeads(_ leads: [Lead]) {
        latestLeads = leads
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let summaries = leads.map(Self.summary(for:))
        let result = ReminderNotificationPlanner.reconcileLeadSummaries(
            leads: summaries,
            persisted: persistedAlarms,
            syncedLeadIds: syncedLeadIDs,
            nowMillis: nowMillis
        )
        if !result.cancelRequestIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(result.cancelRequestIds))
            center.removeDeliveredNotifications(withIdentifiers: Array(result.cancelRequestIds))
        }
        for state in result.schedule {
            scheduleNotification(state, nowMillis: nowMillis)
        }
        savePersistedAlarms(result.kept)
        refreshDailyDigest(leads: leads)
    }

    func restorePersistedAlarms() {
        guard isAuthorized else { return }
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let kept = persistedAlarms.filter {
            ReminderNotificationPlanner.shouldRestoreAlarm(dueTime: $0.dueTime, nowMillis: nowMillis)
        }
        let expiredIds = Set(persistedAlarms.map(\.id)).subtracting(Set(kept.map(\.id)))
        if !expiredIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(expiredIds))
        }
        for state in kept {
            scheduleNotification(state, nowMillis: nowMillis)
        }
        savePersistedAlarms(kept)
    }

    func refreshDailyDigest(leads: [Lead]) {
        let identifier = ReminderNotificationPlanner.dailyDigestIdentifier
        guard isAuthorized, dailyDigestEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let summaries = leads.map(Self.summary(for:))
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        guard let plan = ReminderNotificationPlanner.buildDailyDigest(leads: summaries, nowMillis: nowMillis) else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.subtitle = plan.summaryText
        content.body = plan.bodyLines.joined(separator: "\n")
        content.sound = .default
        var dateComponents = DateComponents()
        dateComponents.hour = dailyDigestHour
        dateComponents.minute = dailyDigestMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    private func scheduleNotification(_ state: ReminderAlarmState, nowMillis: Int64) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = state.notificationTitle
        content.body = state.notificationBody
        content.sound = .default
        content.userInfo = [
            ReminderNotificationPlanner.extraLeadIdKey: state.leadId,
            ReminderNotificationPlanner.extraReminderIdKey: state.actionId,
            ReminderNotificationPlanner.extraTitleKey: state.notificationTitle,
            ReminderNotificationPlanner.extraContactNameKey: state.notificationBody,
            ReminderNotificationPlanner.extraUrlKey: state.deepLinkURLString
        ]
        let fireDate = ReminderNotificationPlanner.fireDate(dueTime: state.dueTime, nowMillis: nowMillis)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: state.id, content: content, trigger: trigger)
        center.add(request)
    }

    private func savePersistedAlarms(_ alarms: [ReminderAlarmState]) {
        persistedAlarms = alarms.sorted { $0.dueTime == $1.dueTime ? $0.id < $1.id : $0.dueTime < $1.dueTime }
        if let data = try? JSONEncoder().encode(persistedAlarms) {
            defaults.set(data, forKey: alarmsKey)
        }
    }

    private static func summary(for lead: Lead) -> LeadNotificationSummary {
        LeadNotificationSummary(
            id: lead.id,
            name: lead.name,
            followUpMillis: lead.followUpDate.map { Int64($0.timeIntervalSince1970 * 1000) },
            isPaused: lead.isPaused,
            isClosed: lead.isClosed,
            appointments: lead.appointments
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let extractedLeadID = ReminderNotificationPlanner.extractLeadId(fromUserInfo: userInfo)
        guard let leadID = extractedLeadID else {
            completionHandler()
            return
        }
        // Defer UI work to the next main run loop turn so presentation does not race UIKit's notification handling.
        DispatchQueue.main.async {
            Task { @MainActor in
                ReminderNotificationService.shared.deliverLeadDeepLink(leadID)
                completionHandler()
            }
        }
    }
}
