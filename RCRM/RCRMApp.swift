import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

@main
struct RCRMApp: App {
    @StateObject private var session = SessionStore()

    init() {
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path) {
            FirebaseApp.configure(options: options)
        }
    }

    var body: some Scene {
        WindowGroup { RootView().environmentObject(session) }
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: User?
    @Published var error: String?
    @Published var isLoading = false
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
            updatedAtMillis: Int64 = 0
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
        calendar: Calendar = .current
    ) -> [AgendaItem] {
        let rangeStart = startOfMonthContaining(monthStartMillis, calendar: calendar)
        let rangeEnd = shiftMonth(rangeStart, delta: 1, calendar: calendar)
        return items
            .filter { $0.startMillis >= rangeStart && $0.startMillis < rangeEnd }
            .filter { item in
                let day = startOfDay(item.startMillis, calendar: calendar)
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
                }
            }
    }
    func createLead(_ lead: Lead, userID: String) async throws {
        try validate(userID)
        let db = Firestore.firestore()
        let ref = db.collection("leads").document()
        var data = lead.data(userID: userID)
        data["timestamp"] = Timestamp(date: Date())
        let batch = db.batch()
        if let date = lead.followUpDate {
            let due = Self.normalized(date)
            data["followUpDate"] = Timestamp(date: due)
            data["reminderMigrationVersion"] = 1
            let action = ref.collection("next_actions").document()
            batch.setData(Self.reminderData(leadID: ref.documentID, userID: userID, date: due).merging(["id": action.documentID], uniquingKeysWith: { _, new in new }), forDocument: action)
        }
        batch.setData(data, forDocument: ref)
        try await batch.commit()
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
    }
    private func validate(_ userID: String) throws {
        guard currentUserID == userID, Auth.auth().currentUser?.uid == userID else { throw StoreError.invalidSession }
    }
    func stop() { listener?.remove(); listener = nil; currentUserID = nil }
    deinit { listener?.remove() }
    enum StoreError: LocalizedError {
        case invalidSession, invalidLead, changedFollowUp, linkedAppointment, invalidReminder, reminderNotOpen, reminderTitle, reminderDate
        case invalidAppointment, newerAppointment, staleNotes
        var errorDescription: String? {
            switch self {
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
                if let snapshot { self.actions = snapshot.documents.map { NextAction(document: $0, leadID: leadID) }.sorted { $0.dueTime == $1.dueTime ? $0.id < $1.id : $0.dueTime < $1.dueTime } }
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
                return
            } catch {
                let nsError = error as NSError, stale = StoreError.changedFollowUp as NSError
                if attempt < 2 && nsError.domain == stale.domain && nsError.code == stale.code { continue }
                throw error
            }
        }
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
    ) async throws {
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
