import SwiftUI

extension Color {
    static let darkSpaceBlue = Color(hex: 0x070B14), spaceTop = Color(hex: 0x0C1424), spaceBottom = Color(hex: 0x09060F), spaceHaze = Color(hex: 0x24143F)
    static let glassPanel = Color(hex: 0x121A2C).opacity(0.8), glassFrost = Color(hex: 0x243656).opacity(0.4)
    static let neonCyan = Color(hex: 0x2EE7FF), neonGreen = Color(hex: 0x3DFF9A), neonPink = Color(hex: 0xFF3B8D), neonPurple = Color(hex: 0xB14CFF), neonBlue = Color(hex: 0x4C8DFF), neonOrange = Color(hex: 0xFFA726)
    static let textPrimary = Color(hex: 0xF4F7FF), textSecondary = Color(hex: 0x9AA6BD), textMuted = Color(hex: 0x7E8BA3)
    private init(hex: UInt) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}
extension View {
    func frostedGlass(cornerRadius: CGFloat = 20, borderColor: Color = .glassFrost) -> some View {
        background(Color.glassPanel, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(borderColor, lineWidth: 1))
    }
    func neonGlow(color: Color, radius: CGFloat = 8) -> some View { shadow(color: color.opacity(0.55), radius: radius) }
}
struct SpaceBackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.spaceTop, .darkSpaceBlue, .spaceBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.spaceHaze.opacity(0.65), .clear], center: .topTrailing, startRadius: 0, endRadius: 450)
        }.ignoresSafeArea()
    }
}
struct CategoryBadge: View {
    let category: String
    var color: Color { category.localizedCaseInsensitiveContains("Recruit") ? .neonPurple : (category.localizedCaseInsensitiveContains("Client") ? .neonGreen : .neonCyan) }
    var body: some View {
        if !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(category).font(.caption.weight(.semibold)).foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 5).background(color.opacity(0.12), in: Capsule())
        }
    }
}
struct AppointmentStatusBadge: View {
    let status: AppointmentStatus?
    var body: some View {
        if let label = AppointmentAgenda.statusLabel(status) {
            let color: Color = {
                switch status {
                case .completed: return .neonGreen
                case .noShow: return .neonOrange
                case .canceled: return .neonPink
                default: return .neonCyan
                }
            }()
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
        }
    }
}

private func openLocationOrMeeting(_ rawLocation: String?, _ open: OpenURLAction) {
    guard let loc = rawLocation?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty else { return }
    if let webUrl = AppointmentAgenda.extractMeetingOrWebUrl(location: loc), let url = URL(string: webUrl) {
        open(url)
        return
    }
    if let encoded = loc.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
       let mapsUrl = URL(string: "https://maps.apple.com/?q=\(encoded)") {
        open(mapsUrl)
    }
}

private func allAgendaItems(from leads: [Lead]) -> [AppointmentAgenda.AgendaItem] {
    leads.flatMap { lead in
        lead.appointments.map { record in
            AppointmentAgenda.AgendaItem(
                leadId: lead.id,
                ownerId: lead.ownerId,
                appointmentId: record.id,
                leadName: lead.name,
                phone: lead.phone,
                category: lead.category,
                title: "Appointment: \(lead.name)",
                startMillis: record.startMillis,
                location: record.location,
                eventId: record.eventId,
                status: record.status,
                originalInstanceTime: record.originalInstanceTime,
                updatedAtMillis: record.updatedAtMillis
            )
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    var body: some View {
        Group {
            if !session.isConfigured { SetupView() }
            else if let user = session.user { AppShell(userID: user.uid).id(user.uid) }
            else { SignInView() }
        }.preferredColorScheme(.dark).tint(.neonCyan)
    }
}
struct SetupView: View {
    var body: some View { ZStack { SpaceBackgroundView(); VStack(alignment: .leading, spacing: 16) {
        Image(systemName: "gearshape.2.fill").font(.largeTitle).foregroundStyle(Color.neonCyan)
        Text("Connect your development environment").font(.title2.bold())
        Text("Add GoogleService-Info.plist from your Firebase development project to the RCRM folder and Xcode target. Then build the app again.").foregroundStyle(Color.textSecondary)
    }.padding(28) } }
}
struct SignInView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var creatingAccount = false
    var body: some View { ZStack { SpaceBackgroundView(); ScrollView { VStack(alignment: .leading, spacing: 20) {
        Image(systemName: "sparkles.rectangle.stack.fill").font(.system(size: 38)).foregroundStyle(Color.neonCyan)
        Text("RCRM").font(.largeTitle.bold())
        Text(creatingAccount ? "Create your account to get started." : "Your relationships, all in one place.").foregroundStyle(Color.textSecondary)
        VStack(spacing: 14) {
            TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().padding().frostedGlass(cornerRadius: 14)
            SecureField("Password", text: $password).textContentType(creatingAccount ? .newPassword : .password).padding().frostedGlass(cornerRadius: 14)
            if creatingAccount {
                SecureField("Confirm password", text: $confirmation).textContentType(.newPassword).padding().frostedGlass(cornerRadius: 14)
                Text("Use at least 6 characters.").font(.footnote).foregroundStyle(Color.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = session.error { Text(error).font(.footnote).foregroundStyle(Color.neonPink).frame(maxWidth: .infinity, alignment: .leading) }
            Button {
                Task {
                    if creatingAccount { await session.signUp(email: email, password: password, confirmation: confirmation) }
                    else { await session.signIn(email: email, password: password) }
                }
            } label: {
                Group { if session.isLoading { ProgressView() } else { Text(creatingAccount ? "Create account" : "Sign in").bold() } }.frame(maxWidth: .infinity).padding()
            }.background(Color.neonCyan, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black).disabled(session.isLoading)
            Button(creatingAccount ? "Already have an account? Sign in" : "New to RCRM? Create an account") {
                creatingAccount.toggle(); confirmation = ""; session.error = nil
            }.font(.subheadline.weight(.semibold)).disabled(session.isLoading)
        }.padding(20).frostedGlass()
    }.padding(24).frame(maxWidth: 500).frame(maxWidth: .infinity) }.safeAreaPadding(.top, 40) } }
}
struct AppShell: View {
    let userID: String
    @StateObject private var store = LeadsStore()
    @EnvironmentObject private var session: SessionStore
    @State private var showingAdd = false
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(userID: userID, showingAdd: $showingAdd, onOpenAgenda: { selectedTab = 1 })
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sign out") { session.signOut() } } }
            }.tabItem { Label("Home", systemImage: "house") }.tag(0)
            NavigationStack { AppointmentsView(userID: userID) }.tabItem { Label("Appointments", systemImage: "calendar") }.tag(1)
            NavigationStack { FollowUpsView(userID: userID) }.tabItem { Label("Follow-ups", systemImage: "checklist") }.tag(2)
            NavigationStack { PipelinesView(userID: userID) }.tabItem { Label("Pipelines", systemImage: "chart.bar") }.tag(3)
            NavigationStack { ContactsView(userID: userID) }.tabItem { Label("Contacts", systemImage: "person.2") }.tag(4)
        }.environmentObject(store)
            .sheet(isPresented: $showingAdd) { LeadFormSheet(userID: userID) }.environmentObject(store)
            .onAppear { store.start(userID: userID) }.onDisappear { store.stop() }
            .alert("RCRM", isPresented: Binding(get: { store.error != nil || session.error != nil }, set: { if !$0 { store.error = nil; session.error = nil } })) { Button("OK") { store.error = nil; session.error = nil } } message: { Text(store.error ?? session.error ?? "") }
    }
}
private func dueGroup(_ date: Date) -> Int {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return 1 }
    return date < calendar.startOfDay(for: Date()) ? 0 : 2
}
private func followUpFeed(_ leads: [Lead], group: Int) -> [Lead] {
    leads.filter { lead in
        guard !lead.isPaused, !lead.isClosed else { return false }
        guard let date = lead.followUpDate else { return group == 0 && (!lead.name.isEmpty || !lead.phone.isEmpty) }
        let due = dueGroup(date)
        return group == 0 ? due == 0 : (group == 1 ? due <= 1 : due == 2)
    }.sorted {
        if $0.followUpDate == $1.followUpDate { return $0.id < $1.id }
        return ($0.followUpDate ?? .distantFuture) < ($1.followUpDate ?? .distantFuture)
    }
}
struct FollowUpTabs: View {
    @Binding var group: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(["Needs Attention", "Today", "Upcoming"].enumerated()), id: \.offset) { index, title in
                Button { group = index } label: {
                    VStack(spacing: 8) {
                        Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                        Capsule().fill(group == index ? Color.neonCyan : Color.clear).frame(height: 3)
                    }.foregroundStyle(group == index ? Color.neonCyan : Color.textSecondary).frame(maxWidth: .infinity)
                }.buttonStyle(.plain).accessibilityAddTraits(group == index ? .isSelected : [])
            }
        }
    }
}
struct FollowUpFeedRow: View {
    let lead: Lead, userID: String
    let logOutcome: () -> Void
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink { LeadDetailView(leadID: lead.id, userID: userID) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(lead.name).font(.headline).foregroundStyle(Color.textPrimary)
                        Text(lead.followUpDate?.formatted(date: .abbreviated, time: .shortened) ?? "No follow-up scheduled").font(.caption).foregroundStyle(Color.textSecondary)
                        CategoryBadge(category: lead.category)
                    }
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button { contact("tel", lead.phone, openURL) } label: {
                        Label("Call", systemImage: "phone.fill").lineLimit(1)
                    }.disabled(lead.phone.isEmpty)
                    Button { contact("sms", lead.phone, openURL) } label: {
                        Label("Text", systemImage: "message.fill").lineLimit(1)
                    }.disabled(lead.phone.isEmpty)
                }
                Button(action: logOutcome) {
                    Label("Log Outcome", systemImage: "square.and.pencil").lineLimit(1)
                }
            }.buttonStyle(.bordered).font(.subheadline)
        }.padding(.vertical, 6)
    }
}

struct UpNextBannerView: View {
    let items: [AppointmentAgenda.AgendaItem]
    let nowMillis: Int64
    let onOpenAgenda: () -> Void
    let onLogOutcome: (AppointmentAgenda.AgendaItem) -> Void
    @Environment(\.openURL) private var openURL
    @State private var currentIndex = 0

    private var safeIndex: Int {
        guard !items.isEmpty else { return 0 }
        return min(max(0, currentIndex), items.count - 1)
    }

    var body: some View {
        if !items.isEmpty {
            let item = items[safeIndex]
            let isLive = AppointmentAgenda.isLiveNow(startMillis: item.startMillis, endMillis: item.endMillis, nowMillis: nowMillis)
            let headline = AppointmentAgenda.upNextHeadline(startMillis: item.startMillis, nowMillis: nowMillis).uppercased()
            let countdown = AppointmentAgenda.countdownLabel(startMillis: item.startMillis, nowMillis: nowMillis, locale: .current)
            let liveText = AppointmentAgenda.liveBadge(endMillis: item.endMillis, nowMillis: nowMillis)
            let timeRange = "\(item.startDate.formatted(date: .omitted, time: .shortened)) – \(item.endDate.formatted(date: .omitted, time: .shortened))"
            let meetingUrl = AppointmentAgenda.extractMeetingOrWebUrl(location: item.location)
            let locationChip = AppointmentAgenda.locationChipLabel(location: item.location, meetingUrl: meetingUrl)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(headline)
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(isLive ? Color.neonPink : Color.neonCyan)
                    Spacer()
                    if items.count > 1 {
                        Button {
                            currentIndex = (safeIndex - 1 + items.count) % items.count
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption.bold())
                                .foregroundStyle(Color.neonCyan)
                                .frame(width: 28, height: 28)
                                .background(Color.neonCyan.opacity(0.12), in: Circle())
                                .overlay(Circle().stroke(Color.neonCyan.opacity(0.65), lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel("Previous upcoming event")
                        Text("\(safeIndex + 1)/\(items.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                        Button {
                            currentIndex = (safeIndex + 1) % items.count
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(Color.neonCyan)
                                .frame(width: 28, height: 28)
                                .background(Color.neonCyan.opacity(0.12), in: Circle())
                                .overlay(Circle().stroke(Color.neonCyan.opacity(0.65), lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel("Next upcoming event")
                    }
                    if isLive {
                        Text(liveText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.neonPink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.neonPink.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.neonPink.opacity(0.9), lineWidth: 1))
                            .neonGlow(color: .neonPink, radius: 6)
                    } else {
                        Text(countdown)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.neonGreen)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.neonGreen.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.neonGreen.opacity(0.7), lineWidth: 1))
                    }
                }
                Text(item.title)
                    .font(.headline.bold())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Text(timeRange)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                    HStack(spacing: 6) {
                        Circle().fill(Color.neonBlue).frame(width: 8, height: 8)
                        Text("RCRM")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.neonBlue.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                }
                if !item.leadName.isEmpty {
                    Text("🔗 Lead: \(item.leadName)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.neonCyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.neonCyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.neonCyan.opacity(0.7), lineWidth: 1))
                }
                if let locationChip, let loc = item.location, !loc.isEmpty {
                    Button {
                        openLocationOrMeeting(loc, openURL)
                    } label: {
                        HStack(spacing: 6) {
                            Text(locationChip)
                            Text("· \(loc)").lineLimit(1)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.neonPurple.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.neonPurple.opacity(0.7), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 10) {
                    Button(action: onOpenAgenda) {
                        Text("Open Agenda")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(Color.neonCyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.neonCyan.opacity(0.8), lineWidth: 1))
                    }.buttonStyle(.plain)
                    Button {
                        onLogOutcome(item)
                    } label: {
                        Text("Log Outcome")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(Color.neonGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.neonGreen.opacity(0.8), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            .padding(16)
            .frostedGlass(cornerRadius: 20, borderColor: isLive ? .neonPink.opacity(0.85) : .neonCyan.opacity(0.75))
        }
    }
}

private struct AppointmentOutcomeContext: Identifiable {
    let lead: Lead
    let appointmentID: String?
    var id: String { "\(lead.id)|\(appointmentID ?? "")" }
}

private struct AppointmentEditorContext: Identifiable {
    let lead: Lead?
    let existing: AppointmentRecord?
    var id: String { "\(lead?.id ?? "new")|\(existing?.id ?? "new")" }
}

struct HomeView: View {
    let userID: String
    @EnvironmentObject private var store: LeadsStore
    @Binding var showingAdd: Bool
    var onOpenAgenda: () -> Void = {}
    @State private var group = 0
    @State private var outcomeContext: AppointmentOutcomeContext?
    @State private var nowMillis = Int64(Date().timeIntervalSince1970 * 1000)

    private var upcomingItems: [AppointmentAgenda.AgendaItem] {
        AppointmentAgenda.upcomingEvents(allAgendaItems(from: store.leads), nowMillis: nowMillis)
    }

    var body: some View { ZStack { SpaceBackgroundView(); ScrollView { VStack(alignment: .leading, spacing: 20) {
        Text("RCRM").font(.title2.bold())
        if !upcomingItems.isEmpty {
            UpNextBannerView(
                items: upcomingItems,
                nowMillis: nowMillis,
                onOpenAgenda: onOpenAgenda,
                onLogOutcome: { item in
                    if let lead = store.leads.first(where: { $0.id == item.leadId }) {
                        outcomeContext = AppointmentOutcomeContext(lead: lead, appointmentID: item.appointmentId)
                    }
                }
            )
        }
        VStack(alignment: .leading, spacing: 20) {
            HStack { metric("Contacts", store.leads.count, .neonCyan); metric("Overdue", store.leads.filter { !$0.isPaused && !$0.isClosed && ($0.followUpDate.map { dueGroup($0) == 0 } ?? false) }.count, .neonPink); metric("Today", store.leads.filter { !$0.isPaused && !$0.isClosed && ($0.followUpDate.map { dueGroup($0) == 1 } ?? false) }.count, .neonGreen) }
            Button { showingAdd = true } label: { Label("Quick add lead", systemImage: "plus").bold().frame(maxWidth: .infinity).padding() }.background(Color.neonCyan, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
        }.padding(20).frostedGlass()
        FollowUpTabs(group: $group)
        if store.isLoading { ProgressView("Loading contacts…") }
        else if followUpFeed(store.leads, group: group).isEmpty { ContentUnavailableView("You're all caught up", systemImage: "checkmark.circle", description: Text("No contacts in this group.")) }
        else { LazyVStack(spacing: 12) {
            ForEach(followUpFeed(store.leads, group: group)) { lead in
                FollowUpFeedRow(lead: lead, userID: userID) { outcomeContext = AppointmentOutcomeContext(lead: lead, appointmentID: nil) }.padding(16).frostedGlass()
            }
        } }
    }.padding() } }.navigationTitle("Home")
        .onAppear { nowMillis = Int64(Date().timeIntervalSince1970 * 1000) }
        .sheet(item: $outcomeContext) { ctx in
            OutcomeSheetView(lead: ctx.lead, userID: userID, appointmentID: ctx.appointmentID)
        }
    }
    private func metric(_ label: String, _ value: Int, _ color: Color) -> some View { VStack(alignment: .leading, spacing: 5) { Text("\(value)").font(.title.bold()).foregroundStyle(color); Text(label).font(.caption).foregroundStyle(Color.textSecondary) }.frame(maxWidth: .infinity, alignment: .leading) }
}

struct AppointmentsView: View {
    let userID: String
    @EnvironmentObject private var store: LeadsStore
    @Environment(\.openURL) private var openURL
    @State private var monthStartMillis = AppointmentAgenda.startOfMonthContaining(Int64(Date().timeIntervalSince1970 * 1000))
    @State private var selectedDayMillis: Int64? = nil
    @State private var monthWindow: AppointmentAgenda.MonthWindow = .upcoming
    @State private var editorContext: AppointmentEditorContext?
    @State private var outcomeContext: AppointmentOutcomeContext?
    @State private var workingID: String?
    @State private var errorMessage: String?

    private var todayStartMillis: Int64 {
        AppointmentAgenda.startOfDay(Int64(Date().timeIntervalSince1970 * 1000))
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date(timeIntervalSince1970: Double(monthStartMillis) / 1000))
    }

    private var dayCells: [AppointmentAgenda.DayCellModel] {
        AppointmentAgenda.buildDayCells(
            monthStartMillis: monthStartMillis,
            todayStartMillis: todayStartMillis,
            selectedDayMillis: selectedDayMillis,
            locale: .current
        )
    }

    private var allItems: [AppointmentAgenda.AgendaItem] {
        allAgendaItems(from: store.leads)
    }

    private var daysWithEvents: Set<Int64> {
        let rangeStart = AppointmentAgenda.startOfMonthContaining(monthStartMillis)
        let rangeEnd = AppointmentAgenda.shiftMonth(rangeStart, delta: 1)
        return Set(
            allItems
                .filter { $0.startMillis >= rangeStart && $0.startMillis < rangeEnd && $0.status != .canceled }
                .map { AppointmentAgenda.startOfDay($0.startMillis) }
        )
    }

    private var visibleEntries: [AppointmentAgenda.AgendaItem] {
        AppointmentAgenda.visibleItems(
            allItems,
            monthStartMillis: monthStartMillis,
            monthWindow: monthWindow,
            selectedDayMillis: selectedDayMillis,
            todayStartMillis: todayStartMillis
        )
    }

    var body: some View {
        ZStack {
            SpaceBackgroundView()
            VStack(spacing: 14) {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            monthStartMillis = AppointmentAgenda.shiftMonth(monthStartMillis, delta: -1)
                            selectedDayMillis = nil
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                                .foregroundStyle(Color.neonCyan)
                                .frame(width: 36, height: 36)
                                .frostedGlass(cornerRadius: 12)
                        }.buttonStyle(.plain).accessibilityLabel("Previous month")

                        Text(monthTitle)
                            .font(.headline.bold())
                            .foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity)

                        Button("Today") {
                            monthStartMillis = AppointmentAgenda.startOfMonthContaining(Int64(Date().timeIntervalSince1970 * 1000))
                            selectedDayMillis = nil
                            monthWindow = .upcoming
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.neonCyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frostedGlass(cornerRadius: 12, borderColor: .neonCyan.opacity(0.6))

                        Button {
                            monthStartMillis = AppointmentAgenda.shiftMonth(monthStartMillis, delta: 1)
                            selectedDayMillis = nil
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.headline)
                                .foregroundStyle(Color.neonCyan)
                                .frame(width: 36, height: 36)
                                .frostedGlass(cornerRadius: 12)
                        }.buttonStyle(.plain).accessibilityLabel("Next month")
                    }

                    HStack(spacing: 8) {
                        ForEach(AppointmentAgenda.MonthWindow.allCases) { window in
                            let selected = (selectedDayMillis == nil && monthWindow == window)
                            Button {
                                selectedDayMillis = nil
                                monthWindow = window
                            } label: {
                                Text(window.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(selected ? Color.neonCyan : Color.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(selected ? Color.neonCyan.opacity(0.18) : Color.clear, in: Capsule())
                                    .overlay(Capsule().stroke(selected ? Color.neonCyan : Color.glassFrost, lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(dayCells) { cell in
                                    let hasEvent = daysWithEvents.contains(cell.dayStartMillis)
                                    Button {
                                        if selectedDayMillis == cell.dayStartMillis {
                                            selectedDayMillis = nil
                                        } else {
                                            selectedDayMillis = cell.dayStartMillis
                                        }
                                    } label: {
                                        VStack(spacing: 4) {
                                            Text(cell.dowLabel)
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(cell.selected ? Color.darkSpaceBlue : (cell.isToday ? Color.neonCyan : Color.textSecondary))
                                            Text("\(cell.dayOfMonth)")
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(cell.selected ? Color.darkSpaceBlue : Color.textPrimary)
                                            Circle()
                                                .fill(hasEvent ? (cell.selected ? Color.darkSpaceBlue : Color.neonCyan) : Color.clear)
                                                .frame(width: 6, height: 6)
                                        }
                                        .frame(width: 48, height: 64)
                                        .background(
                                            cell.selected ? Color.neonCyan : (cell.isToday ? Color.neonCyan.opacity(0.14) : Color.glassPanel),
                                            in: RoundedRectangle(cornerRadius: 14)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(cell.selected || cell.isToday ? Color.neonCyan : Color.glassFrost, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .id(cell.dayStartMillis)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .onAppear { scrollDayStrip(proxy) }
                        .onChange(of: monthStartMillis) { _, _ in scrollDayStrip(proxy) }
                    }
                }
                .padding(16)
                .frostedGlass()
                .padding(.horizontal)

                if store.isLoading && store.leads.isEmpty {
                    Spacer()
                    ProgressView("Loading agenda…")
                    Spacer()
                } else if visibleEntries.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        selectedDayMillis != nil ? "No appointments on this day" : (monthWindow == .upcoming ? "No upcoming appointments this month" : "No appointments this month"),
                        systemImage: "calendar.badge.clock",
                        description: Text(selectedDayMillis != nil ? "Tap the selected day again to view the month, or tap + to schedule." : (monthWindow == .upcoming ? "Switch to All Month to see earlier days, or tap + to schedule." : "Tap + to schedule an appointment with any contact."))
                    )
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(visibleEntries) { item in
                                AgendaEntryCard(
                                    item: item,
                                    userID: userID,
                                    isWorking: workingID == item.id,
                                    onLogOutcome: {
                                        if let lead = store.leads.first(where: { $0.id == item.leadId }) {
                                            outcomeContext = AppointmentOutcomeContext(lead: lead, appointmentID: item.appointmentId)
                                        }
                                    },
                                    onReschedule: {
                                        if let lead = store.leads.first(where: { $0.id == item.leadId }) {
                                            let record = lead.appointments.first(where: { $0.id == item.appointmentId })
                                                ?? AppointmentRecord(id: item.appointmentId, startMillis: item.startMillis, location: item.location, eventId: item.eventId, status: item.status, originalInstanceTime: item.originalInstanceTime, updatedAtMillis: item.updatedAtMillis)
                                            editorContext = AppointmentEditorContext(lead: lead, existing: record)
                                        }
                                    },
                                    onCancel: {
                                        cancelAppointment(item)
                                    },
                                    onMarkOutcome: { outcome in
                                        markVisitOutcome(item, outcome: outcome)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle("Appointments")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorContext = AppointmentEditorContext(lead: nil, existing: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Schedule appointment")
                .disabled(store.leads.isEmpty)
            }
        }
        .sheet(item: $editorContext) { ctx in
            AppointmentFormSheet(userID: userID, initialLead: ctx.lead, existing: ctx.existing)
        }
        .sheet(item: $outcomeContext) { ctx in
            OutcomeSheetView(lead: ctx.lead, userID: userID, appointmentID: ctx.appointmentID)
        }
        .alert("Appointments", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func scrollDayStrip(_ proxy: ScrollViewProxy) {
        let starts = dayCells.map(\.dayStartMillis)
        let index = AppointmentAgenda.dayStripAnchorIndex(dayStarts: starts, todayStart: todayStartMillis, selectedDay: selectedDayMillis)
        if starts.indices.contains(index) {
            withAnimation {
                proxy.scrollTo(starts[index], anchor: .center)
            }
        }
    }

    private func cancelAppointment(_ item: AppointmentAgenda.AgendaItem) {
        markVisitOutcome(item, outcome: .canceled)
    }

    private func markVisitOutcome(_ item: AppointmentAgenda.AgendaItem, outcome: AppointmentOutcome) {
        guard workingID == nil else { return }
        workingID = item.id
        Task {
            defer { workingID = nil }
            do {
                try await store.recordAppointmentOutcome(
                    leadID: item.leadId,
                    userID: userID,
                    appointmentID: item.appointmentId,
                    outcome: outcome,
                    baseUpdatedAtMillis: item.updatedAtMillis
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct AgendaEntryCard: View {
    let item: AppointmentAgenda.AgendaItem
    let userID: String
    let isWorking: Bool
    let onLogOutcome: () -> Void
    let onReschedule: () -> Void
    let onCancel: () -> Void
    let onMarkOutcome: (AppointmentOutcome) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.neonCyan)
                    Text(item.leadName.isEmpty ? item.title : item.leadName)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                HStack(spacing: 6) {
                    AppointmentStatusBadge(status: item.status)
                    CategoryBadge(category: item.category)
                }
            }

            if let loc = item.location, !loc.isEmpty {
                Button {
                    openLocationOrMeeting(loc, openURL)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: AppointmentAgenda.extractMeetingOrWebUrl(location: loc) != nil ? "video.fill" : "mappin.and.ellipse")
                        Text(loc).lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.neonPurple.opacity(0.16), in: Capsule())
                    .overlay(Capsule().stroke(Color.neonPurple.opacity(0.6), lineWidth: 1))
                }.buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button(action: onLogOutcome) {
                        Label("Log Outcome", systemImage: "square.and.pencil").lineLimit(1)
                    }
                    Button(action: onReschedule) {
                        Label("Reschedule", systemImage: "calendar.badge.clock").lineLimit(1)
                    }
                }
                HStack(spacing: 10) {
                    if item.status == .scheduled {
                        Button(role: .destructive, action: onCancel) {
                            Label("Cancel", systemImage: "xmark.circle").lineLimit(1)
                        }
                    }
                    if !item.leadId.isEmpty {
                        NavigationLink {
                            LeadDetailView(leadID: item.leadId, userID: userID)
                        } label: {
                            Label("Open Contact", systemImage: "person.crop.circle").lineLimit(1)
                        }
                    }
                    Menu {
                        Button("Mark Completed") { onMarkOutcome(.completed) }
                        Button("Mark No-Show") { onMarkOutcome(.noShow) }
                        if item.status != .canceled {
                            Button("Cancel Appointment", role: .destructive) { onCancel() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More appointment actions")
                }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
            .disabled(isWorking)

            if isWorking {
                ProgressView("Updating…").font(.caption)
            }
        }
        .padding(16)
        .frostedGlass()
    }
}

struct AppointmentFormSheet: View {
    let userID: String
    let initialLead: Lead?
    let existing: AppointmentRecord?
    @EnvironmentObject private var store: LeadsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLeadID: String
    @State private var date: Date
    @State private var location: String
    @State private var note = ""
    @State private var scheduleReminder = true
    @State private var saving = false
    @State private var error: String?

    init(userID: String, initialLead: Lead? = nil, existing: AppointmentRecord? = nil) {
        self.userID = userID
        self.initialLead = initialLead
        self.existing = existing
        _selectedLeadID = State(initialValue: initialLead?.id ?? "")
        _date = State(initialValue: existing?.startDate ?? OutcomeSavePlanner.dueDate(for: .tomorrow))
        _location = State(initialValue: existing?.location ?? initialLead?.appointmentLocation ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    if let initialLead {
                        LabeledContent("Contact", value: initialLead.name)
                    } else {
                        Picker("Contact", selection: $selectedLeadID) {
                            Text("Select a contact").tag("")
                            ForEach(store.leads) { lead in
                                Text(lead.name).tag(lead.id)
                            }
                        }
                    }
                }.listRowBackground(Color.glassPanel)

                Section("Date & Location") {
                    DueQuickButtons(date: $date)
                    DatePicker("Date and time", selection: $date)
                    TextField("Location or meeting link (https://...)", text: $location)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }.listRowBackground(Color.glassPanel)

                if existing == nil {
                    Section("Reminder") {
                        Toggle("Create linked follow-up reminder", isOn: $scheduleReminder)
                    }.listRowBackground(Color.glassPanel)
                }

                Section("Note") {
                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }.listRowBackground(Color.glassPanel)

                if let error {
                    Section { Text(error).foregroundStyle(Color.neonPink) }.listRowBackground(Color.glassPanel)
                }
            }
            .scrollContentBackground(.hidden)
            .background { SpaceBackgroundView() }
            .navigationTitle(existing == nil ? "Schedule Appointment" : "Reschedule Appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }
                        .disabled(saving || resolvedLeadID.isEmpty)
                }
            }
            .onAppear {
                if selectedLeadID.isEmpty, let first = store.leads.first {
                    selectedLeadID = first.id
                }
            }
            .interactiveDismissDisabled(saving)
            .disabled(saving)
        }.preferredColorScheme(.dark).tint(.neonCyan)
    }

    private var resolvedLeadID: String {
        initialLead?.id ?? selectedLeadID
    }

    private func save() {
        guard !saving, !resolvedLeadID.isEmpty else { return }
        saving = true
        error = nil
        Task {
            do {
                if let existing {
                    try await store.rescheduleAppointment(
                        leadID: resolvedLeadID,
                        userID: userID,
                        appointmentID: existing.id,
                        newDate: date,
                        location: location,
                        baseUpdatedAtMillis: existing.updatedAtMillis,
                        note: note
                    )
                } else {
                    try await store.saveAppointment(
                        leadID: resolvedLeadID,
                        userID: userID,
                        startDate: date,
                        location: location,
                        note: note,
                        scheduleReminder: scheduleReminder
                    )
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

struct ContactRow: View {
    let lead: Lead
    @Environment(\.openURL) private var openURL
    var body: some View { HStack {
        VStack(alignment: .leading, spacing: 6) { Text(lead.name).font(.headline); if !lead.phone.isEmpty { Text(lead.phone).font(.subheadline).foregroundStyle(Color.textSecondary) }; CategoryBadge(category: lead.category) }
        Spacer()
        if !lead.phone.isEmpty { Button { contact("tel", lead.phone, openURL) } label: { Image(systemName: "phone.fill") }.buttonStyle(.borderless).accessibilityLabel("Call \(lead.name)"); Button { contact("sms", lead.phone, openURL) } label: { Image(systemName: "message.fill") }.buttonStyle(.borderless).accessibilityLabel("Text \(lead.name)") }
    }.padding(.vertical, 5) }
}
private func contact(_ scheme: String, _ value: String, _ open: OpenURLAction) {
    let allowed = scheme == "mailto" ? CharacterSet.urlQueryAllowed : CharacterSet(charactersIn: "+0123456789")
    let sanitized = scheme == "mailto" ? value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" : String(value.unicodeScalars.filter { allowed.contains($0) })
    guard !sanitized.isEmpty, let url = URL(string: "\(scheme):\(sanitized)") else { return }; open(url)
}
struct ContactsView: View {
    let userID: String
    @EnvironmentObject private var store: LeadsStore
    @State private var search = ""
    @State private var category = "All"
    @State private var showingAdd = false
    @State private var toDelete: Lead?
    var filtered: [Lead] { store.leads.filter { lead in
        (category == "All" || lead.categories.contains { $0.caseInsensitiveCompare(category) == .orderedSame }) && (search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || [lead.name, lead.phone, lead.email, lead.company, lead.notes, lead.category].contains { $0.localizedCaseInsensitiveContains(search) })
    } }
    var body: some View { ZStack { SpaceBackgroundView(); VStack(spacing: 0) {
        ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(["All", "Prospect", "Recruit", "Client"], id: \.self) { item in Button(item) { category = item }.font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 8).background(category == item ? Color.neonCyan.opacity(0.22) : Color.glassPanel, in: Capsule()) } }.padding(.horizontal).padding(.vertical, 8) }
        if store.isLoading && store.leads.isEmpty { Spacer(); ProgressView("Loading contacts…"); Spacer() }
        else if filtered.isEmpty { Spacer(); ContentUnavailableView("No contacts found", systemImage: "person.crop.circle.badge.questionmark", description: Text("Add a contact or adjust your search.")); Spacer() }
        else { List(filtered) { lead in NavigationLink { LeadDetailView(leadID: lead.id, userID: userID) } label: { ContactRow(lead: lead) }.listRowBackground(Color.glassPanel).swipeActions { Button(role: .destructive) { toDelete = lead } label: { Label("Delete", systemImage: "trash") } } }.scrollContentBackground(.hidden) }
    } }.navigationTitle("Contacts").searchable(text: $search, prompt: "Search contacts").toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add contact") } }
        .sheet(isPresented: $showingAdd) { LeadFormSheet(userID: userID) }
        .confirmationDialog("Delete this contact?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) { Button("Delete", role: .destructive) { if let lead = toDelete { Task { do { try await store.deleteLead(lead, userID: userID) } catch { store.error = error.localizedDescription } } }; toDelete = nil } } message: { Text("This removes the contact. Its related activity and actions are not automatically deleted.") }
    }
}
struct FollowUpsView: View {
    let userID: String
    @EnvironmentObject private var store: LeadsStore
    @State private var group = 0
    @State private var outcomeLead: Lead?
    var leads: [Lead] { followUpFeed(store.leads, group: group) }
    var body: some View { ZStack { SpaceBackgroundView(); VStack {
        FollowUpTabs(group: $group).padding()
        if store.isLoading { ProgressView("Loading follow-ups…") }
        else if leads.isEmpty { ContentUnavailableView("No follow-ups", systemImage: "checkmark.circle", description: Text("No contacts in this group.")) }
        else { List(leads) { lead in
            FollowUpFeedRow(lead: lead, userID: userID) { outcomeLead = lead }.listRowBackground(Color.glassPanel)
        }.scrollContentBackground(.hidden) }
    } }.navigationTitle("Follow-ups")
        .sheet(item: $outcomeLead) { OutcomeSheetView(lead: $0, userID: userID) }
    }
}

private struct StageTransitionRequest: Identifiable {
    let lead: Lead
    let stage: StageChangeSpec
    var id: String { "\(lead.id)|\(stage.pipelineType.rawValue)|\(stage.newStageId)" }
}

struct PipelinesView: View {
    let userID: String
    @EnvironmentObject private var store: LeadsStore
    @Environment(\.openURL) private var openURL
    @State private var pipeline: PipelineType = .sales
    @State private var searchQuery = ""
    @State private var selectedStageIndex = 0
    @State private var transitionRequest: StageTransitionRequest?

    private var stages: [(id: String, title: String)] {
        if pipeline == .sales {
            return SalesStage.allCases.map { ($0.id, $0.title) }
        } else {
            return RecruitStage.allCases.map { ($0.id, $0.title) }
        }
    }

    private var activeLeads: [Lead] {
        store.leads.filter { lead in
            let matchesType: Bool
            if pipeline == .sales {
                matchesType = !lead.category.localizedCaseInsensitiveContains("Recruit")
                    || lead.category.localizedCaseInsensitiveContains("Client")
                    || lead.category.localizedCaseInsensitiveContains("Prospect")
            } else {
                matchesType = lead.categories.contains { $0.caseInsensitiveCompare("Recruit") == .orderedSame }
                    || lead.category.localizedCaseInsensitiveContains("Recruit")
            }
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || lead.name.localizedCaseInsensitiveContains(query)
                || lead.phone.localizedCaseInsensitiveContains(query)
            return matchesType && matchesSearch
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func leads(forStageID stageID: String) -> [Lead] {
        activeLeads.filter { lead in
            pipeline == .sales ? lead.salesStage.id == stageID : lead.recruitStage.id == stageID
        }
    }

    private var safeStageIndex: Int {
        guard !stages.isEmpty else { return 0 }
        return min(max(0, selectedStageIndex), stages.count - 1)
    }

    private var conversionRate: Int {
        let total = activeLeads.count
        guard total > 0, let lastStage = stages.last else { return 0 }
        let converted = leads(forStageID: lastStage.id).count
        return (converted * 100) / total
    }

    private var accentColor: Color {
        pipeline == .sales ? .neonCyan : .neonPurple
    }

    var body: some View {
        ZStack {
            SpaceBackgroundView()
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.textSecondary)
                    TextField("Search pipelines...", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.textSecondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frostedGlass(cornerRadius: 24)
                .padding(.horizontal)

                HStack(spacing: 0) {
                    ForEach(PipelineType.allCases) { type in
                        let isSelected = pipeline == type
                        let color: Color = type == .sales ? .neonCyan : .neonPurple
                        Button {
                            pipeline = type
                            selectedStageIndex = 0
                        } label: {
                            Text(type.label)
                                .font(.subheadline.weight(isSelected ? .bold : .regular))
                                .foregroundStyle(isSelected ? color : Color.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(isSelected ? color.opacity(0.2) : Color.clear, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                .frostedGlass(cornerRadius: 24)
                .padding(.horizontal)

                HStack {
                    Text("Total Active: \(activeLeads.count)")
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("Conversion Rate: \(conversionRate)%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(pipeline == .sales ? Color.neonCyan : Color.neonPink)
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                            let count = leads(forStageID: stage.id).count
                            let isSelected = safeStageIndex == index
                            let pillAccent: Color = pipeline == .sales ? .neonCyan : .neonPink
                            Button {
                                selectedStageIndex = index
                            } label: {
                                Text("\(stage.title) (\(count))")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(isSelected ? pillAccent : Color.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? pillAccent.opacity(0.2) : Color.glassPanel, in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(isSelected ? pillAccent : Color.glassFrost, lineWidth: 1)
                                    )
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                let stage = stages[safeStageIndex]
                let stageLeads = leads(forStageID: stage.id)
                if stageLeads.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "No leads in this stage.",
                        systemImage: "tray",
                        description: Text("Select another stage pill above or move contacts into \(stage.title).")
                    )
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(stageLeads) { lead in
                                LeadPipelineCardView(
                                    lead: lead,
                                    userID: userID,
                                    pipelineType: pipeline,
                                    stages: stages,
                                    currentStageIndex: safeStageIndex,
                                    onCall: { contact("tel", lead.phone, openURL) },
                                    onStageChange: { newIndex in
                                        guard stages.indices.contains(newIndex) else { return }
                                        let target = stages[newIndex]
                                        transitionRequest = StageTransitionRequest(
                                            lead: lead,
                                            stage: StageChangeSpec(pipelineType: pipeline, newStageId: target.id, stageTitle: target.title)
                                        )
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle("Visual Pipelines")
        .onChange(of: searchQuery) { _, newValue in
            let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty, let match = activeLeads.first else { return }
            let targetStageID = pipeline == .sales ? match.salesStage.id : match.recruitStage.id
            if let idx = stages.firstIndex(where: { $0.id == targetStageID }) {
                selectedStageIndex = idx
            }
        }
        .sheet(item: $transitionRequest) { req in
            OutcomeSheetView(lead: req.lead, userID: userID, initialStageChange: req.stage)
        }
    }
}

struct LeadPipelineCardView: View {
    let lead: Lead
    let userID: String
    let pipelineType: PipelineType
    let stages: [(id: String, title: String)]
    let currentStageIndex: Int
    let onCall: () -> Void
    let onStageChange: (Int) -> Void

    private var accentColor: Color {
        pipelineType == .sales ? .neonCyan : .neonPurple
    }

    private var tmColor: Color {
        switch lead.targetMarketPoints {
        case 4...5: return .neonGreen
        case 3: return .neonOrange
        default: return .neonPink
        }
    }

    private var isMissingPlan: Bool {
        lead.followUpDate == nil && !lead.isPaused && !lead.isClosed
    }

    private var isOverdue: Bool {
        guard let followUp = lead.followUpDate else { return false }
        return followUp < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                LeadDetailView(leadID: lead.id, userID: userID)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        Text("\(lead.name)\(lead.isPinned ? " 🔥" : "")")
                            .font(.headline.bold())
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("\(lead.targetMarketPoints)/5 TM • \(lead.targetMarketPoints * 20)%")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tmColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tmColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(tmColor.opacity(0.5), lineWidth: 1))
                    }

                    Text(NoteUtils.getDisplayNote(lead.notes))
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)

                    if let followUp = lead.followUpDate {
                        Text("Follow-up: \(followUp.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(Color.neonBlue)
                    }
                    if isMissingPlan {
                        Text("Needs a next step")
                            .font(.caption.bold())
                            .foregroundStyle(Color.neonPink)
                    } else if isOverdue {
                        Text("Overdue")
                            .font(.caption.bold())
                            .foregroundStyle(Color.neonPink)
                    }
                    if let lastConnected = lead.lastConnectedContact {
                        Text("Last connected: \(lastConnected.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack {
                if currentStageIndex > 0 {
                    Button {
                        onStageChange(currentStageIndex - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.footnote.bold())
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.glassPanel, in: Circle())
                            .overlay(Circle().stroke(Color.glassFrost, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityLabel("Previous Stage")
                } else {
                    Spacer().frame(width: 32, height: 32)
                }

                Spacer()
                Text(stages[currentStageIndex].title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accentColor)
                Spacer()

                if currentStageIndex < stages.count - 1 {
                    Button {
                        onStageChange(currentStageIndex + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.footnote.bold())
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.glassPanel, in: Circle())
                            .overlay(Circle().stroke(Color.glassFrost, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityLabel("Next Stage")
                } else {
                    Spacer().frame(width: 32, height: 32)
                }

                Button(action: onCall) {
                    Image(systemName: "phone.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.neonGreen)
                        .frame(width: 32, height: 32)
                        .background(Color.neonGreen.opacity(0.18), in: Circle())
                        .overlay(Circle().stroke(Color.neonGreen.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(lead.phone.isEmpty)
                .accessibilityLabel("Call \(lead.name)")
            }
        }
        .padding(16)
        .frostedGlass(borderColor: accentColor.opacity(0.35))
    }
}

struct LeadDetailView: View {
    let leadID: String, userID: String
    @EnvironmentObject private var store: LeadsStore
    @Environment(\.openURL) private var openURL
    @StateObject private var activity = LeadActivityStore()
    @State private var editing = false
    @State private var editingNotes = false
    @State private var quickNote = ""
    @State private var savingNote = false
    @State private var showAllNotes = false
    @FocusState private var quickNoteFocused: Bool
    @State private var loggingOutcome = false
    @State private var addingReminder = false
    @State private var schedulingAppointment = false
    @State private var reschedulingAppointment: AppointmentRecord?
    @State private var outcomeAppointment: AppointmentRecord?
    @State private var rescheduling: NextAction?
    @State private var outcomeAction: NextAction?
    @State private var workingActionID: String?
    @State private var actionError: String?
    private var openActions: [NextAction] { activity.actions.filter { $0.status == .pending } }
    var body: some View {
        Group {
            if let lead = store.leads.first(where: { $0.id == leadID }) {
                List {
                    Section { HStack {
                        action("Call", "phone.fill", "tel", lead.phone)
                        action("Text", "message.fill", "sms", lead.phone)
                        action("Email", "envelope.fill", "mailto", lead.email)
                    }.frame(maxWidth: .infinity)
                        Button { loggingOutcome = true } label: { Label("Log Outcome", systemImage: "square.and.pencil").bold().frame(maxWidth: .infinity) }
                    }.listRowBackground(Color.glassPanel)
                    Section("Contact") {
                        detail("Phone", lead.phone); detail("Email", lead.email); detail("Address", lead.address)
                        detail("Company", lead.company); detail("Title", lead.title); detail("Category", lead.category)
                    }.listRowBackground(Color.glassPanel)
                    Section("Pipeline") {
                        LabeledContent("Sales stage", value: lead.salesStage.title); LabeledContent("Recruit stage", value: lead.recruitStage.title)
                        LabeledContent("Target market", value: "\(lead.targetMarketPoints) / 5")
                        LabeledContent("Paused", value: lead.isPaused ? "Yes" : "No"); LabeledContent("Closed", value: lead.isClosed ? "Yes" : "No")
                        if let reason = lead.pausedReason, !reason.isEmpty { LabeledContent("Workflow reason", value: reason) }
                    }.listRowBackground(Color.glassPanel)
                    Section("Follow-up") {
                        dateDetail("Follow-up", lead.followUpDate); dateDetail("Last attempted", lead.lastAttemptedContact); dateDetail("Last connected", lead.lastConnectedContact)
                    }.listRowBackground(Color.glassPanel)
                    notesSection(lead)
                    appointmentsSection(lead)
                    remindersSection
                    Section("Activity Timeline") {
                        if activity.activitiesLoading { ProgressView("Loading activity…") }
                        if let error = activity.activitiesError { Text(error).foregroundStyle(Color.neonPink) }
                        let items = ContactActivityTimeline.mergeActivityAndNotes(activity.activities, rawNotes: lead.notes)
                        if items.isEmpty && !activity.activitiesLoading && activity.activitiesError == nil { Text("No activity yet.").foregroundStyle(Color.textSecondary) }
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    Label(item.outcome, systemImage: item.isActivityRecord ? "clock.arrow.circlepath" : "note.text").font(.headline).foregroundStyle(item.isActivityRecord ? Color.neonCyan : Color.neonPurple)
                                    Spacer(); Text(item.type.title).font(.caption).foregroundStyle(Color.textSecondary)
                                }
                                if !item.note.isEmpty { Text(item.note).textSelection(.enabled) }
                                if let stage = item.stageContext { Text(stage).font(.caption).foregroundStyle(Color.neonGreen) }
                                Text(item.dateDisplay).font(.caption).foregroundStyle(Color.textSecondary)
                            }.padding(.vertical, 6)
                        }
                    }.listRowBackground(Color.glassPanel)
                }.scrollContentBackground(.hidden).background { SpaceBackgroundView() }.navigationTitle(lead.name).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
                    .sheet(isPresented: $editing) { LeadFormSheet(userID: userID, existing: lead) }
                    .sheet(isPresented: $editingNotes) { ContactNotesSheet(lead: lead, userID: userID) }
                    .sheet(isPresented: $loggingOutcome) { OutcomeSheetView(lead: lead, userID: userID) }
                    .sheet(item: $outcomeAction) { OutcomeSheetView(lead: lead, userID: userID, currentActionID: $0.id) }
                    .sheet(item: $outcomeAppointment) { OutcomeSheetView(lead: lead, userID: userID, appointmentID: $0.id) }
                    .sheet(isPresented: $schedulingAppointment) { AppointmentFormSheet(userID: userID, initialLead: lead) }
                    .sheet(item: $reschedulingAppointment) { AppointmentFormSheet(userID: userID, initialLead: lead, existing: $0) }
                    .sheet(isPresented: $addingReminder) { ReminderSheetView(leadID: leadID, userID: userID) }
                    .sheet(item: $rescheduling) { ReminderSheetView(leadID: leadID, userID: userID, existing: $0) }
            } else { ContentUnavailableView("Contact unavailable", systemImage: "person.crop.circle.badge.questionmark").background { SpaceBackgroundView() } }
        }.onAppear { activity.start(leadID: leadID, userID: userID) }.onDisappear { activity.stop() }
            .alert("Action couldn't be saved", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) { Button("OK") { actionError = nil } } message: { Text(actionError ?? "") }
    }
    private func notesSection(_ lead: Lead) -> some View {
        let parsedNotes = NoteUtils.sortedNotes(lead.notes)
        let displayedNotes = showAllNotes ? parsedNotes : Array(parsedNotes.prefix(1))
        let trimmedQuickNote = quickNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return Section("Notes") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Add a note about this contact…", text: $quickNote, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($quickNoteFocused)
                    .disabled(savingNote)
                if !trimmedQuickNote.isEmpty || quickNoteFocused {
                    HStack(spacing: 12) {
                        Button {
                            saveQuickNote()
                        } label: {
                            if savingNote {
                                ProgressView("Saving…")
                            } else {
                                Label("Add Note", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.neonCyan)
                        .foregroundStyle(.black)
                        .disabled(trimmedQuickNote.isEmpty || savingNote)

                        if !quickNote.isEmpty && !savingNote {
                            Button("Clear") {
                                quickNote = ""
                                quickNoteFocused = false
                            }
                            .buttonStyle(.bordered)
                            .font(.subheadline)
                        }
                    }
                }
            }
            .padding(.vertical, 4)

            if !parsedNotes.isEmpty {
                ForEach(Array(displayedNotes.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.content)
                            .font(.body)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(showAllNotes ? nil : 3)
                            .textSelection(.enabled)
                        if item.date != "Unknown date" {
                            Text(item.date)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                if parsedNotes.count > 1 {
                    Button {
                        showAllNotes.toggle()
                    } label: {
                        Label(
                            showAllNotes ? "Show less" : "Show all notes (\(parsedNotes.count))",
                            systemImage: showAllNotes ? "chevron.up" : "chevron.down"
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.neonCyan)
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
                Button {
                    editingNotes = true
                } label: {
                    Label(parsedNotes.isEmpty ? "Open Notes Editor" : "Edit Notes", systemImage: "square.and.pencil")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.neonPurple)
                }
                .buttonStyle(.borderless)
            }
        }.listRowBackground(Color.glassPanel)
    }
    private func saveQuickNote() {
        let trimmed = quickNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !savingNote else { return }
        savingNote = true
        Task {
            defer { savingNote = false }
            do {
                try await store.addContactNote(leadID: leadID, userID: userID, note: trimmed)
                quickNote = ""
                quickNoteFocused = false
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
    private func appointmentsSection(_ lead: Lead) -> some View {
        Section("Appointments") {
            Button { schedulingAppointment = true } label: { Label("Schedule appointment", systemImage: "calendar.badge.plus") }
            let sorted = lead.appointments.sorted {
                if ($0.status == .scheduled) != ($1.status == .scheduled) { return $0.status == .scheduled }
                return $0.startMillis < $1.startMillis
            }
            if sorted.isEmpty {
                Text("No appointments scheduled.").foregroundStyle(Color.textSecondary)
            }
            ForEach(sorted) { appt in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(appt.startDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        Spacer()
                        if appt.status == .scheduled {
                            Text("Scheduled")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.neonCyan)
                        } else {
                            AppointmentStatusBadge(status: appt.status)
                        }
                    }
                    if let loc = appt.location, !loc.isEmpty {
                        Button {
                            openLocationOrMeeting(loc, openURL)
                        } label: {
                            Label(loc, systemImage: AppointmentAgenda.extractMeetingOrWebUrl(location: loc) != nil ? "video.fill" : "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(Color.neonPurple)
                        }.buttonStyle(.borderless)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Button { outcomeAppointment = appt } label: {
                                Label("Log Outcome", systemImage: "square.and.pencil").lineLimit(1)
                            }
                            Button { reschedulingAppointment = appt } label: {
                                Label("Reschedule", systemImage: "calendar.badge.clock").lineLimit(1)
                            }
                        }
                        if appt.status == .scheduled {
                            Button(role: .destructive) {
                                cancelLeadAppointment(appt)
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle").lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                    .disabled(workingActionID != nil)
                }.padding(.vertical, 4)
            }
        }.listRowBackground(Color.glassPanel)
    }
    private func cancelLeadAppointment(_ appt: AppointmentRecord) {
        guard workingActionID == nil else { return }
        workingActionID = appt.id
        Task {
            defer { workingActionID = nil }
            do {
                try await store.recordAppointmentOutcome(
                    leadID: leadID,
                    userID: userID,
                    appointmentID: appt.id,
                    outcome: .canceled,
                    baseUpdatedAtMillis: appt.updatedAtMillis
                )
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
    private var remindersSection: some View {
        Section("Open Reminders") {
            Button { addingReminder = true } label: { Label("Add reminder", systemImage: "plus.circle") }
            if activity.actionsLoading { ProgressView("Loading reminders…") }
            if let error = activity.actionsError { Text(error).foregroundStyle(Color.neonPink) }
            if openActions.isEmpty && !activity.actionsLoading && activity.actionsError == nil { Text("No open reminders.").foregroundStyle(Color.textSecondary) }
            ForEach(openActions) { reminder in
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(reminder.title.isEmpty ? "Follow up" : reminder.title).font(.headline); Spacer(); Text(reminder.type.title).font(.caption).foregroundStyle(Color.neonCyan) }
                    Text(reminder.dueTime > 0 ? reminder.dueDate.formatted(date: .abbreviated, time: .shortened) : "No due date")
                        .font(.caption).foregroundStyle(reminder.dueTime > 0 && reminder.dueDate < Date() ? Color.neonPink : Color.textSecondary)
                    if !reminder.notes.isEmpty { Text(reminder.notes).font(.subheadline) }
                    if reminder.appointmentId?.isEmpty == false { Label("Linked appointment", systemImage: "calendar").font(.caption).foregroundStyle(Color.textSecondary) }
                    ViewThatFits(in: .horizontal) {
                        HStack { reminderControls(reminder) }
                        VStack(alignment: .leading) { reminderControls(reminder) }
                    }.buttonStyle(.bordered).disabled(workingActionID != nil)
                    if workingActionID == reminder.id { ProgressView("Saving…") }
                }.padding(.vertical, 6)
            }
        }.listRowBackground(Color.glassPanel)
    }
    @ViewBuilder private func reminderControls(_ reminder: NextAction) -> some View {
        Button("Complete") { mutate(reminder, complete: true) }
        Menu("More") {
            Button("Log Outcome") { outcomeAction = reminder }
            Button("Reschedule") { rescheduling = reminder }
            Button("Cancel reminder", role: .destructive) { mutate(reminder, complete: false) }
        }
    }
    private func mutate(_ reminder: NextAction, complete: Bool) {
        guard workingActionID == nil else { return }
        workingActionID = reminder.id
        Task {
            defer { workingActionID = nil }
            do {
                if complete { try await store.completeReminder(leadID: leadID, userID: userID, actionID: reminder.id) }
                else { try await store.cancelReminder(leadID: leadID, userID: userID, actionID: reminder.id) }
            } catch { actionError = error.localizedDescription }
        }
    }
    private func detail(_ label: String, _ value: String) -> some View { LabeledContent(label, value: value.isEmpty ? "—" : value) }
    private func dateDetail(_ label: String, _ date: Date?) -> some View { LabeledContent(label, value: date?.formatted(date: .abbreviated, time: .shortened) ?? "—") }
    private func action(_ label: String, _ image: String, _ scheme: String, _ value: String) -> some View {
        Button { contact(scheme, value, openURL) } label: { Label(label, systemImage: image).frame(maxWidth: .infinity) }.disabled(value.isEmpty).buttonStyle(.borderless)
    }
}
struct LeadFormSheet: View {
    let userID: String
    let existing: Lead?
    @EnvironmentObject private var store: LeadsStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Lead
    @State private var hasFollowUp: Bool
    @State private var followUp: Date
    @State private var saving = false
    @State private var error: String?
    init(userID: String, existing: Lead? = nil) {
        self.userID = userID; self.existing = existing
        _draft = State(initialValue: existing ?? Lead())
        _hasFollowUp = State(initialValue: existing?.followUpDate != nil)
        _followUp = State(initialValue: existing?.followUpDate ?? Date())
    }
    var body: some View { NavigationStack {
        Form {
            Section("Contact") {
                TextField("Name", text: $draft.name)
                TextField("Phone", text: $draft.phone).keyboardType(.phonePad)
                TextField("Email", text: $draft.email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Address", text: $draft.address); TextField("Company", text: $draft.company); TextField("Title", text: $draft.title)
            }.listRowBackground(Color.glassPanel)
            Section("Categories") {
                ForEach(["Prospect", "Recruit", "Client"], id: \.self) { category in
                    Toggle(category, isOn: Binding(get: { draft.categories.contains { $0.caseInsensitiveCompare(category) == .orderedSame } }, set: { enabled in
                        var categories = draft.categories.filter { $0.caseInsensitiveCompare(category) != .orderedSame }
                        if enabled { categories.append(category) }; draft.category = categories.joined(separator: ", ")
                    }))
                }
            }.listRowBackground(Color.glassPanel)
            Section("Pipeline") {
                Picker("Sales stage", selection: $draft.salesStage) { ForEach(SalesStage.allCases) { Text($0.title).tag($0) } }
                Picker("Recruit stage", selection: $draft.recruitStage) { ForEach(RecruitStage.allCases) { Text($0.title).tag($0) } }
                Toggle("Paused", isOn: $draft.isPaused); if draft.isPaused { TextField("Pause reason", text: Binding(get: { draft.pausedReason ?? "" }, set: { draft.pausedReason = $0.isEmpty ? nil : $0 })) }
                Toggle("Closed", isOn: $draft.isClosed)
            }.listRowBackground(Color.glassPanel)
            Section("Target market · \(draft.targetMarketPoints) / 5") {
                Toggle("Married", isOn: $draft.tmMarried); Toggle("Age 25–55", isOn: $draft.tmAge); Toggle("Children", isOn: $draft.tmChildren); Toggle("Homeowner", isOn: $draft.tmHomeowner); Toggle("Occupation", isOn: $draft.tmOccupation)
            }.listRowBackground(Color.glassPanel)
            Section("Follow-up") { Toggle("Set follow-up", isOn: $hasFollowUp); if hasFollowUp { DatePicker("Date and time", selection: $followUp) }; Text("Changing or clearing this date updates the earliest open reminder. Other reminders remain open.").font(.caption).foregroundStyle(Color.textSecondary) }.listRowBackground(Color.glassPanel)
            Section("Notes") { TextEditor(text: $draft.notes).frame(minHeight: 100).scrollContentBackground(.hidden) }.listRowBackground(Color.glassPanel)
            if let error { Section { Text(error).foregroundStyle(Color.neonPink) }.listRowBackground(Color.glassPanel) }
        }.scrollContentBackground(.hidden).background { SpaceBackgroundView() }
            .navigationTitle(existing == nil ? "New contact" : "Edit contact").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(saving || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.category.isEmpty) }
            }
    } }
    private func save() {
        saving = true; error = nil
        var lead = draft
        lead.name = lead.name.trimmingCharacters(in: .whitespacesAndNewlines)
        lead.followUpDate = hasFollowUp ? followUp : nil
        Task {
            do {
                if let existing { try await store.updateLead(lead, original: existing, userID: userID) }
                else { try await store.createLead(lead, userID: userID) }
                dismiss()
            } catch { self.error = error.localizedDescription; saving = false }
        }
    }
}
struct OutcomeSheetView: View {
    let lead: Lead
    let userID: String
    var currentActionID: String? = nil
    var appointmentID: String? = nil
    var initialStageChange: StageChangeSpec? = nil
    @EnvironmentObject private var store: LeadsStore
    @Environment(\.dismiss) private var dismiss
    @State private var operationID = UUID().uuidString
    @State private var outcome = ""
    @State private var note = ""
    @State private var changeStage: Bool
    @State private var pipeline: PipelineType
    @State private var salesStage: SalesStage
    @State private var recruitStage: RecruitStage
    @State private var scheduleNext = false
    @State private var nextTitle = "Follow up"
    @State private var nextType: ActionType = .call
    @State private var dueDate = OutcomeSavePlanner.dueDate(for: .today)
    @State private var linkedAppointmentID = ""
    @State private var clearExisting = false
    @State private var lifecycle: WorkflowLifecycle = .unchanged
    @State private var reason = ""
    @State private var saving = false
    @State private var error: String?

    init(
        lead: Lead,
        userID: String,
        currentActionID: String? = nil,
        appointmentID: String? = nil,
        initialStageChange: StageChangeSpec? = nil
    ) {
        self.lead = lead
        self.userID = userID
        self.currentActionID = currentActionID
        self.appointmentID = appointmentID
        self.initialStageChange = initialStageChange
        if let stage = initialStageChange {
            _changeStage = State(initialValue: true)
            _pipeline = State(initialValue: stage.pipelineType)
            _salesStage = State(initialValue: SalesStage(rawValue: stage.newStageId) ?? lead.salesStage)
            _recruitStage = State(initialValue: RecruitStage(rawValue: stage.newStageId) ?? lead.recruitStage)
        } else {
            _changeStage = State(initialValue: false)
            _salesStage = State(initialValue: lead.salesStage)
            _recruitStage = State(initialValue: lead.recruitStage)
            _pipeline = State(initialValue: lead.categories.contains("Recruit") ? .recruiting : .sales)
        }
        if appointmentID != nil {
            _outcome = State(initialValue: "Meeting completed")
        }
    }

    private let outcomes = ["Connected", "No answer", "Voicemail left", "Message sent", "Meeting completed", "No-show", "Rescheduled"]

    private var appointmentChoices: [AppointmentChoice] {
        OutcomeSavePlanner.relevantAppointments(
            records: lead.appointments,
            legacyStartMillis: lead.appointmentDate.map { Int64($0.timeIntervalSince1970 * 1000) },
            nowMillis: Int64(Date().timeIntervalSince1970 * 1000),
            locale: .current
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lead.name).font(.title2.bold())
                        Text("Record what happened and choose the next step.").foregroundStyle(Color.textSecondary)
                    }
                    panel(changeStage ? "Outcome (optional)" : "Outcome") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                            ForEach(outcomes, id: \.self) { choice in
                                Button { outcome = outcome == choice ? "" : choice } label: {
                                    Text(choice).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .foregroundStyle(outcome == choice ? Color.neonCyan : Color.textPrimary)
                                        .background(outcome == choice ? Color.neonCyan.opacity(0.16) : Color.glassFrost, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(outcome == choice ? Color.neonCyan : Color.clear))
                                }.buttonStyle(.plain).accessibilityAddTraits(outcome == choice ? .isSelected : [])
                            }
                        }
                    }
                    panel("Pipeline") {
                        Toggle("Change pipeline stage", isOn: $changeStage)
                        if changeStage {
                            Picker("Pipeline", selection: $pipeline) { ForEach(PipelineType.allCases) { Text($0.label).tag($0) } }
                            if pipeline == .sales { Picker("Stage", selection: $salesStage) { ForEach(SalesStage.allCases) { Text($0.title).tag($0) } } }
                            else { Picker("Stage", selection: $recruitStage) { ForEach(RecruitStage.allCases) { Text($0.title).tag($0) } } }
                        }
                    }
                    panel("Note") {
                        TextField("Add a note (optional)", text: $note, axis: .vertical).lineLimit(4...8).padding(12).frostedGlass(cornerRadius: 12)
                    }
                    panel("Next Action") {
                        Toggle("Schedule next action", isOn: $scheduleNext).disabled(lifecycle != .unchanged || clearExisting)
                        if scheduleNext && lifecycle == .unchanged && !clearExisting {
                            TextField("Title", text: $nextTitle).padding(12).frostedGlass(cornerRadius: 12)
                            Picker("Action type", selection: $nextType) { ForEach(ActionType.allCases, id: \.self) { Text($0.title).tag($0) } }
                            DueQuickButtons(date: $dueDate)
                            DatePicker("Due", selection: $dueDate)
                            if !appointmentChoices.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Existing appointments (12h lookback)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.textSecondary)
                                    ForEach(appointmentChoices, id: \.startMillis) { choice in
                                        let isSelected = linkedAppointmentID == choice.id && !choice.id.isEmpty
                                        Button {
                                            if isSelected {
                                                linkedAppointmentID = ""
                                            } else {
                                                linkedAppointmentID = choice.id
                                                dueDate = Date(timeIntervalSince1970: Double(choice.startMillis) / 1000)
                                                nextType = .meeting
                                                if nextTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nextTitle == "Follow up" {
                                                    nextTitle = "Appointment"
                                                }
                                            }
                                        } label: {
                                            HStack {
                                                Image(systemName: isSelected ? "checkmark.circle.fill" : "calendar")
                                                Text(choice.label).font(.caption.weight(.medium)).lineLimit(1)
                                                Spacer()
                                            }
                                            .padding(10)
                                            .foregroundStyle(isSelected ? Color.neonCyan : Color.textPrimary)
                                            .background(isSelected ? Color.neonCyan.opacity(0.16) : Color.glassFrost, in: RoundedRectangle(cornerRadius: 10))
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.neonCyan : Color.clear, lineWidth: 1))
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        Toggle("Clear current reminder", isOn: $clearExisting).disabled(lifecycle != .unchanged || scheduleNext)
                        Text("Logging an outcome finishes the selected or earliest open reminder. Other reminders stay open.")
                            .font(.caption).foregroundStyle(Color.textSecondary)
                    }
                    panel("Workflow") {
                        Picker("Lifecycle", selection: $lifecycle) { ForEach(WorkflowLifecycle.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                        if lifecycle != .unchanged {
                            TextField(lifecycle == .pause ? "Pause reason (optional)" : "Close reason (optional)", text: $reason, axis: .vertical)
                                .padding(12).frostedGlass(cornerRadius: 12)
                            Text("This removes the contact from the follow-up feed. Scheduling new work through an outcome resumes it.")
                                .font(.caption).foregroundStyle(Color.textSecondary)
                        }
                    }
                    if let error { Text(error).foregroundStyle(Color.neonPink).accessibilityLabel("Save failed: \(error)") }
                    Button { save() } label: {
                        HStack { if saving { ProgressView() }; Text(saving ? "Saving…" : "Save outcome").bold() }.frame(maxWidth: .infinity).padding()
                    }.background(Color.neonCyan, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black).disabled(saving)
                }.padding()
            }.background { SpaceBackgroundView() }.navigationTitle("Log Outcome").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) } }
                .interactiveDismissDisabled(saving).disabled(saving)
        }.tint(.neonCyan).preferredColorScheme(.dark)
    }
    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { Text(title).font(.headline).foregroundStyle(Color.neonCyan); content() }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18).frostedGlass()
    }
    private func save() {
        guard !saving else { return }
        guard !outcome.isEmpty || changeStage || lifecycle != .unchanged else { error = "Choose an outcome, or use Pause or Close."; return }
        let scheduling = scheduleNext && !clearExisting && lifecycle == .unchanged
        guard !scheduling || !nextTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Add a title for the next action."; return }
        var request = OutcomeSaveRequest(operationId: operationID, leadId: lead.id, ownerId: userID)
        request.outcome = outcome; request.note = note; request.currentActionId = currentActionID
        request.appointmentId = appointmentID
        if changeStage {
            request.stage = StageChangeSpec(pipelineType: pipeline, newStageId: pipeline == .sales ? salesStage.rawValue : recruitStage.rawValue,
                stageTitle: pipeline == .sales ? salesStage.title : recruitStage.title)
        }
        request.nextAction = scheduling ? NextActionSpec(
            title: nextTitle,
            dueTime: Int64(dueDate.timeIntervalSince1970 * 1000),
            type: nextType,
            appointmentId: linkedAppointmentID.isEmpty ? nil : linkedAppointmentID
        ) : nil
        request.clearExistingNextAction = clearExisting && !scheduling && lifecycle == .unchanged
        request.lifecycle = lifecycle; request.lifecycleReason = reason
        saving = true; error = nil
        Task {
            do { try await store.saveOutcome(request); dismiss() }
            catch { self.error = error.localizedDescription; saving = false }
        }
    }
}
struct DueQuickButtons: View {
    @Binding var date: Date
    var body: some View {
        HStack {
            Button("Today") { date = OutcomeSavePlanner.dueDate(for: .today) }
            Button("Tomorrow") { date = OutcomeSavePlanner.dueDate(for: .tomorrow) }
        }.buttonStyle(.bordered)
    }
}
struct ReminderSheetView: View {
    let leadID: String, userID: String
    var existing: NextAction? = nil
    @EnvironmentObject private var store: LeadsStore
    @Environment(\.dismiss) private var dismiss
    @State private var actionID = UUID().uuidString
    @State private var title = ""
    @State private var notes = ""
    @State private var type: ActionType = .toDo
    @State private var date: Date
    @State private var saving = false
    @State private var error: String?
    init(leadID: String, userID: String, existing: NextAction? = nil) {
        self.leadID = leadID; self.userID = userID; self.existing = existing
        _date = State(initialValue: existing?.dueDate ?? OutcomeSavePlanner.dueDate(for: .today))
    }
    var body: some View {
        NavigationStack {
            Form {
                if let existing { Section("Reminder") { Text(existing.title); Text(existing.type.title).foregroundStyle(Color.textSecondary) }.listRowBackground(Color.glassPanel) }
                else { Section("Reminder") {
                    TextField("Title", text: $title)
                    Picker("Type", selection: $type) { ForEach(ActionType.allCases, id: \.self) { Text($0.title).tag($0) } }
                    TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(3...6)
                }.listRowBackground(Color.glassPanel) }
                Section("Due") { DueQuickButtons(date: $date); DatePicker("Date and time", selection: $date) }.listRowBackground(Color.glassPanel)
                if let error { Section { Text(error).foregroundStyle(Color.neonPink) }.listRowBackground(Color.glassPanel) }
            }.scrollContentBackground(.hidden).background { SpaceBackgroundView() }
                .navigationTitle(existing == nil ? "New reminder" : "Reschedule reminder").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { save() }.disabled(saving) }
                }.interactiveDismissDisabled(saving).disabled(saving)
        }.preferredColorScheme(.dark).tint(.neonCyan)
    }
    private func save() {
        guard !saving else { return }
        saving = true; error = nil
        Task {
            do {
                if let existing { try await store.rescheduleReminder(leadID: leadID, userID: userID, actionID: existing.id, date: date) }
                else { try await store.createReminder(leadID: leadID, userID: userID, actionID: actionID, title: title, notes: notes, type: type, date: date) }
                dismiss()
            } catch { self.error = error.localizedDescription; saving = false }
        }
    }
}
struct ContactNotesSheet: View {
    let lead: Lead
    let userID: String
    @EnvironmentObject private var store: LeadsStore
    @Environment(\.dismiss) private var dismiss
    @State private var notesText: String
    @State private var saving = false
    @State private var error: String?
    init(lead: Lead, userID: String) {
        self.lead = lead
        self.userID = userID
        _notesText = State(initialValue: lead.notes)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $notesText)
                        .frame(minHeight: 220)
                        .scrollContentBackground(.hidden)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Existing dated entries are kept in this field.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .listRowBackground(Color.glassPanel)
                if let error {
                    Section {
                        Text(error).foregroundStyle(Color.neonPink)
                    }.listRowBackground(Color.glassPanel)
                }
            }
            .scrollContentBackground(.hidden)
            .background { SpaceBackgroundView() }
            .navigationTitle(lead.name.isEmpty ? "Notes" : "\(lead.name) · Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { save() }.disabled(saving) }
            }
            .interactiveDismissDisabled(saving)
            .disabled(saving)
        }.preferredColorScheme(.dark).tint(.neonCyan)
    }
    private func save() {
        guard !saving else { return }
        if notesText == lead.notes {
            dismiss()
            return
        }
        saving = true
        error = nil
        Task {
            do {
                try await store.updateContactNotes(leadID: lead.id, userID: userID, notes: notesText, originalNotes: lead.notes)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}
