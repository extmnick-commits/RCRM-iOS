// Executed against the app's actual domain declarations by run-step2-checks.sh.
var assertions = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    precondition(value(), message)
}
let now: Int64 = 1_750_000_000_123
let early = NextAction(id: "early", leadId: "lead", ownerId: "owner", title: "Call", dueTime: now + 10_000)
let late = NextAction(id: "late", leadId: "lead", ownerId: "owner", title: "Email", dueTime: now + 20_000)
var request = OutcomeSaveRequest(operationId: " op/a\\b ", leadId: "lead", ownerId: "owner", outcome: "Connected", nowMillis: now)
func plan(_ request: OutcomeSaveRequest, notes: String = "[Jan 01, 2020]: Old notes", category: String = "Prospect") -> OutcomeSavePlan {
    OutcomeSavePlanner.plan(request, existingNotes: notes, existingCategory: category, pending: [late, early])
}
check(OutcomeSavePlanner.sanitizeOperationId(" \n ") == "outcome", "Blank ID fallback")
let connected = plan(request)
check(connected.activity.id == "act_op_a_b", "Android operation ID sanitization")
check(connected.completeActionId == "early" && connected.completeStatus == .completed, "Complete earliest pending")
check(connected.activity.type == .call, "Connected is a call")
check(connected.lastAttemptedContact == now && connected.lastConnectedContact == now, "Connected contact stamps")
check(connected.notes == nil && connected.isPaused == nil, "No note or lifecycle writes without changes")
request.currentActionId = "late"
check(plan(request).completeActionId == "late", "Explicit action beats earliest")
request.currentActionId = nil; request.resolveCurrentActionIfMissing = false
check(plan(request).completeActionId == nil, "Honor resolution opt-out")
request.resolveCurrentActionIfMissing = true
request.nextAction = NextActionSpec(title: "  Next email  ", dueTime: now + 30_000, type: .email)
let scheduled = plan(request)
check(scheduled.newAction?.id == "next_op_a_b" && scheduled.newAction?.title == "Next email", "Deterministic next action")
check(scheduled.newAction?.workflow == .general && scheduled.newAction?.status == .pending, "General pending next action")
check(scheduled.activity.type == .email, "Scheduled type takes priority")
check(scheduled.isPaused == false && scheduled.isClosed == false && scheduled.writePausedReason, "New work resumes contact")
request.stage = StageChangeSpec(pipelineType: .sales, newStageId: "in_force", stageTitle: "Client / In-Force")
request.note = "  Sent paperwork  "
let stage = plan(request)
check(stage.category == "Prospect, Client", "Add Client category")
check(plan(request, category: "Client").category == nil, "Do not duplicate Client")
check(stage.newAction?.workflow == .sales, "Stage selects workflow")
check(stage.activity.outcome == "Stage Changed: Connected", "Android stage activity outcome")
check(stage.activity.note == "Moved to Client / In-Force stage\n\nSent paperwork", "Android stage note body")
check(stage.notes?.contains(" | eid:act_op_a_b]: Moved to") == true, "Event-tagged note")
check(stage.notes?.hasSuffix("\n\n[Jan 01, 2020]: Old notes") == true, "Prepend existing notes")
check(ContactActivityTimeline.mergeActivityAndNotes([stage.activity], rawNotes: stage.notes!).count == 2, "Deduplicate activity and keep old note")
request.lifecycle = .pause; request.lifecycleReason = "  Vacation  "
let pause = plan(request)
check(pause.completeStatus == .cancelled && pause.newAction == nil, "Pause cancels and suppresses schedule")
check(pause.isPaused == true && pause.isClosed == false && pause.completeReason == "Vacation", "Pause lifecycle and reason")
check(pause.activity.note.hasSuffix("Paused: Vacation"), "Pause reason note")
request.lifecycle = .close
let close = plan(request)
check(close.completeStatus == .completed && close.isClosed == true && close.isPaused == false, "Close completes current action")
check(close.activity.note.hasSuffix("Closed: Vacation"), "Close reason note")
request.lifecycle = .unchanged; request.clearExistingNextAction = true
check(plan(request).completeStatus == .cancelled && plan(request).newAction == nil, "Clear cancels and suppresses schedule")
request.clearExistingNextAction = false; request.nextAction = nil; request.stage = nil
request.outcome = "No answer"
check(plan(request).lastConnectedContact == nil && plan(request).lastAttemptedContact == now, "Failed attempt preserves connected date")
request.outcome = "Meeting completed"
check(plan(request).lastConnectedContact == now && plan(request).activity.type == .meeting, "Meeting is connected")
request.outcome = nil
check(plan(request).lastAttemptedContact == nil && plan(request).completeActionId == nil, "Note-only doesn't finish reminder or stamp contact")
check(OutcomeSavePlanner.activityType(for: "Message sent", scheduled: nil) == .message, "Message type")
check(OutcomeSavePlanner.activityType(for: "Rescheduled", scheduled: nil) == .meeting, "Reschedule type")
check(OutcomeSavePlanner.followUpMillis([late, early]) == early.dueTime, "Earliest pending projection")
var done = early; done.status = .completed
check(OutcomeSavePlanner.followUpMillis([late, done]) == late.dueTime, "Completed action excluded")
check(OutcomeSavePlanner.followUpMillis([late], paused: true) == nil, "Paused clears parent date")
check(OutcomeSavePlanner.followUpMillis([late], closed: true) == nil, "Closed clears parent date")
check(OutcomeSavePlanner.followUpMillis([]) == nil, "No pending clears parent date")
check(scheduled.newAction?.data["dueTime"] is Int64 && scheduled.newAction?.data["createdAt"] is Int64, "Action dates are Int64")
check(stage.activity.data["timestamp"] is Int64 && stage.activity.data["ownerId"] as? String == "owner", "Activity schema")
check(NoteUtils.prependNote("Existing", content: " \n ") == "Existing", "Empty note preserves existing")
let tagged = NoteUtils.prependNote("", content: "Hello 🌌\nSecond line", eventId: "act_test", date: Date(timeIntervalSince1970: Double(now) / 1000))
let parsed = ContactActivityTimeline.parseNotes(tagged)
check(parsed.count == 1 && parsed[0].eventId == "act_test" && parsed[0].content == "Hello 🌌\nSecond line", "Unicode multiline note parsing")
check(parsed[0].timestampMillis != nil, "Parse POSIX note date")
check(NoteUtils.getDisplayNote(tagged) == "Hello 🌌", "getDisplayNote extracts first line of newest note")
check(NoteUtils.getDisplayNote("   ") == "No notes available", "getDisplayNote empty fallback")
let record = ActivityRecord(id: "act_test", type: .call, outcome: "Connected", note: "Hello 🌌\nSecond line", timestamp: now)
check(ContactActivityTimeline.mergeActivityAndNotes([record], rawNotes: tagged).count == 1, "Exact eid deduplication")
let untagged = NoteUtils.prependNote("", content: record.note, date: Date(timeIntervalSince1970: Double(now) / 1000))
check(ContactActivityTimeline.mergeActivityAndNotes([record], rawNotes: untagged).count == 1, "Legacy text/time deduplication")
let distinct = tagged.replacingOccurrences(of: "act_test", with: "act_other")
check(ContactActivityTimeline.mergeActivityAndNotes([record], rawNotes: distinct).count == 2, "Different eid survives same text/time")
let old = "Undated\n" + NoteUtils.prependNote("", content: "Old", date: Date(timeIntervalSince1970: Double(now - 300_000) / 1000))
let merged = ContactActivityTimeline.mergeActivityAndNotes([record], rawNotes: old)
check(merged.first?.id == record.id && merged.last?.timestampMillis == nil, "Newest first, undated last")
check(ContactActivityTimeline.parseNotes("Prefix\n" + tagged).first?.content == "Prefix", "Keep freeform note prefix")
check(ContactActivityTimeline.mergeActivityAndNotes([], rawNotes: "[Oct 01, 2025 09:00 AM]: [Voice Log]: A voice note").first?.outcome == "Voice Note", "Legacy voice note")
check(ContactActivityTimeline.parseTimestamp("2025-10-01") != nil, "ISO legacy date")
check(ContactActivityTimeline.parseTimestamp("Unknown date") == nil, "Unknown date remains undated")
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}
func millis(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Int64 {
    Int64(date(year, month, day, hour, minute).timeIntervalSince1970 * 1000)
}
check(OutcomeSavePlanner.dueDate(for: .today, now: date(2026, 10, 29, 10, 22), calendar: calendar) == date(2026, 10, 29, 17), "Today before 5pm")
check(OutcomeSavePlanner.dueDate(for: .today, now: date(2026, 10, 29, 17), calendar: calendar) == date(2026, 10, 29, 18), "Today at 5pm")
check(OutcomeSavePlanner.dueDate(for: .today, now: date(2026, 10, 29, 23, 45), calendar: calendar) == date(2026, 10, 30, 0), "Today late night rollover")
check(OutcomeSavePlanner.dueDate(for: .tomorrow, now: date(2026, 10, 31, 23), calendar: calendar) == date(2026, 11, 1, 9), "Tomorrow respects DST calendar day")
NSTimeZone.default = calendar.timeZone
check(NoteUtils.prependNote("Old", content: " New ", eventId: "act_fixed", date: date(2026, 10, 29, 9, 5)) == "[Oct 29, 2026 09:05 AM | eid:act_fixed]: New\n\nOld", "Exact Android note header format")

// Step 3: AppointmentAgenda & AppointmentSync checks
let baseNow = millis(2026, 10, 22, 12, 0)
let legacyStart = millis(2026, 10, 26, 9, 0)
let migratedFirst = AppointmentAgenda.migrateAppointments(
    leadId: "lead-1",
    existing: [],
    legacyStartMillis: legacyStart,
    legacyLocation: "  Office  ",
    legacyEventId: 10,
    nowMillis: baseNow
)
check(migratedFirst.count == 1 && migratedFirst[0].id == "legacy:lead-1", "Migrate creates legacy:<leadId> record")
check(migratedFirst[0].startMillis == legacyStart && migratedFirst[0].location == "Office" && migratedFirst[0].eventId == 10, "Migrated legacy fields")
let migratedSecond = AppointmentAgenda.migrateAppointments(
    leadId: "lead-1",
    existing: migratedFirst,
    legacyStartMillis: legacyStart,
    legacyLocation: "Office",
    legacyEventId: 10,
    nowMillis: baseNow + 5_000
)
check(migratedSecond == migratedFirst, "Migration is idempotent")

// parseRecords & toFieldMaps round-trip + invalid filtering
let completedLegacy = AppointmentRecord(id: "legacy:lead-1", startMillis: legacyStart, location: "Office", eventId: 10, status: .completed, originalInstanceTime: nil, updatedAtMillis: baseNow)
let futureAppt = AppointmentRecord(id: "future", startMillis: millis(2026, 11, 2, 9, 0), location: "Client", eventId: 12, status: .scheduled, originalInstanceTime: nil, updatedAtMillis: baseNow)
let withHistory = AppointmentAgenda.migrateAppointments(
    leadId: "lead-1",
    existing: [completedLegacy, futureAppt, futureAppt],
    legacyStartMillis: legacyStart,
    legacyLocation: "Office",
    legacyEventId: 10,
    nowMillis: baseNow
)
check(withHistory.count == 2 && withHistory[0].status == .completed && withHistory[1].id == "future", "Deduplicate and preserve completed legacy history")
let fieldMaps = AppointmentAgenda.toFieldMaps(withHistory)
let roundTrip = AppointmentAgenda.parseRecords(fieldMaps)
check(roundTrip == withHistory, "parseRecords and toFieldMaps round-trip")
let noisyRaw: [Any] = [
    ["id": " ", "startAt": legacyStart],
    ["id": "bad-start", "startAt": 0],
    ["id": "a1", "startAt": legacyStart, "status": "NO-SHOW", "location": "  Zoom  ", "eventId": "42", "updatedAt": 123],
    ["id": "a1", "startAt": legacyStart + 9999, "status": "completed"]
]
let parsedNoisy = AppointmentAgenda.parseRecords(noisyRaw)
check(parsedNoisy.count == 1 && parsedNoisy[0].id == "a1" && parsedNoisy[0].status == .noShow && parsedNoisy[0].eventId == 42 && parsedNoisy[0].location == "Zoom", "parseRecords normalizes status and skips invalid/duplicate entries")

// legacyMirror rules
let pastScheduled = AppointmentRecord(id: "past", startMillis: baseNow - 86_400_000, location: "Past Loc", eventId: 1, status: .scheduled, updatedAtMillis: baseNow)
let soonerFuture = AppointmentRecord(id: "sooner", startMillis: baseNow + 3_600_000, location: "Sooner Loc", eventId: 2, status: .scheduled, updatedAtMillis: baseNow)
let laterFuture = AppointmentRecord(id: "later", startMillis: baseNow + 86_400_000, location: "Later Loc", eventId: 3, status: .scheduled, updatedAtMillis: baseNow)
let mirrorUpcoming = AppointmentAgenda.legacyMirror([completedLegacy, laterFuture, pastScheduled, soonerFuture], nowMillis: baseNow)
check(mirrorUpcoming.appointmentId == "sooner" && mirrorUpcoming.startMillis == soonerFuture.startMillis && mirrorUpcoming.location == "Sooner Loc" && mirrorUpcoming.eventId == 2, "legacyMirror picks earliest upcoming scheduled appointment")
let mirrorFallbackPast = AppointmentAgenda.legacyMirror([completedLegacy, pastScheduled], nowMillis: baseNow)
check(mirrorFallbackPast.appointmentId == "past" && mirrorFallbackPast.startMillis == pastScheduled.startMillis, "legacyMirror falls back to latest past scheduled when none upcoming")
let mirrorEmpty = AppointmentAgenda.legacyMirror([completedLegacy], nowMillis: baseNow)
check(mirrorEmpty.appointmentId == nil && mirrorEmpty.startMillis == nil && mirrorEmpty.location == nil && mirrorEmpty.eventId == nil, "legacyMirror clears when no scheduled appointments remain")

// applyOutcome & reschedule + AppointmentSync conflict checks
let outcomeCompleted = AppointmentAgenda.applyOutcome([soonerFuture, laterFuture], appointmentId: "sooner", outcome: .completed, nowMillis: baseNow + 10)
check(outcomeCompleted[0].status == .completed && outcomeCompleted[0].updatedAtMillis == baseNow + 10 && outcomeCompleted[1] == laterFuture, "applyOutcome marks target completed and preserves others")
let outcomeNoShow = AppointmentAgenda.applyOutcome([soonerFuture], appointmentId: "sooner", outcome: .noShow, nowMillis: baseNow + 20)
check(outcomeNoShow[0].status == .noShow, "applyOutcome marks no_show")
let outcomeCanceled = AppointmentAgenda.applyOutcome([soonerFuture], appointmentId: "sooner", outcome: .canceled, nowMillis: baseNow + 30)
check(outcomeCanceled[0].status == .canceled, "applyOutcome marks canceled")

let movedTime = millis(2026, 10, 27, 16, 0)
let rescheduled = AppointmentAgenda.reschedule([soonerFuture], appointmentId: "sooner", newStartMillis: movedTime, nowMillis: baseNow + 40, rememberInstance: true)
check(rescheduled[0].id == "sooner" && rescheduled[0].startMillis == movedTime && rescheduled[0].status == .scheduled && rescheduled[0].originalInstanceTime == soonerFuture.startMillis, "reschedule updates startMillis and remembers originalInstanceTime")

let newerRecord = AppointmentRecord(id: "sooner", startMillis: movedTime, location: "Office", eventId: 2, status: .scheduled, updatedAtMillis: baseNow + 500)
let staleReschedule = AppointmentSync.applyAppointmentMutation(
    leadId: "lead-1",
    fresh: [newerRecord],
    mutation: .reschedule(appointmentId: "sooner", newStartMillis: movedTime + 3_600_000, nowMillis: baseNow + 600, rememberInstance: false, baseUpdatedAtMillis: baseNow)
)
check(!staleReschedule.changed && staleReschedule.keptNewer && staleReschedule.records[0].startMillis == movedTime, "Reschedule honors baseUpdatedAtMillis conflict check")

let validReschedule = AppointmentSync.applyAppointmentMutation(
    leadId: "lead-1",
    fresh: [newerRecord],
    mutation: .reschedule(appointmentId: "sooner", newStartMillis: movedTime + 3_600_000, nowMillis: baseNow + 600, rememberInstance: false, baseUpdatedAtMillis: baseNow + 500)
)
check(validReschedule.changed && !validReschedule.keptNewer && validReschedule.records[0].startMillis == movedTime + 3_600_000, "Reschedule succeeds when baseUpdatedAtMillis is current")

// upcomingEvents, liveNow, liveBadge, countdownLabel, upNextHeadline
let upNow = millis(2026, 10, 26, 12, 0)
let allDayEvent = AppointmentAgenda.AgendaItem(id: "1", title: "Birthday", startMillis: millis(2026, 10, 26, 0, 0), endMillis: millis(2026, 10, 27, 0, 0), allDay: true)
let canceledEvent = AppointmentAgenda.AgendaItem(id: "2", title: "Canceled", startMillis: millis(2026, 10, 26, 12, 30), endMillis: millis(2026, 10, 26, 13, 30), canceled: true, status: .canceled)
let liveEvent = AppointmentAgenda.AgendaItem(id: "3", title: "Work block", startMillis: millis(2026, 10, 26, 9, 0), endMillis: millis(2026, 10, 26, 17, 0))
let nextEvent = AppointmentAgenda.AgendaItem(id: "4", title: "Appointment: Alex", startMillis: millis(2026, 10, 26, 13, 0), endMillis: millis(2026, 10, 26, 14, 0))
let laterEvent = AppointmentAgenda.AgendaItem(id: "5", title: "Later", startMillis: millis(2026, 10, 26, 15, 0), endMillis: millis(2026, 10, 26, 16, 0))
let farEvent = AppointmentAgenda.AgendaItem(id: "6", title: "Far", startMillis: millis(2026, 10, 27, 13, 0), endMillis: millis(2026, 10, 27, 14, 0))

let upcoming = AppointmentAgenda.upcomingEvents([allDayEvent, canceledEvent, liveEvent, laterEvent, nextEvent, farEvent], nowMillis: upNow)
check(upcoming.map(\.id) == ["3", "4", "5"], "upcomingEvents skips all-day, canceled, and >24h events, sorting live first")
check(AppointmentAgenda.pickUpNext([allDayEvent, canceledEvent, liveEvent, laterEvent, nextEvent, farEvent], nowMillis: upNow)?.id == "3", "pickUpNext selects live event first")
check(AppointmentAgenda.isLiveNow(startMillis: millis(2026, 10, 26, 11, 55), endMillis: millis(2026, 10, 26, 12, 30), nowMillis: upNow), "isLiveNow detects active window")
check(AppointmentAgenda.liveBadge(endMillis: millis(2026, 10, 26, 12, 30), nowMillis: upNow) == "LIVE NOW • Ends in 30m", "liveBadge formats remaining minutes")
check(AppointmentAgenda.countdownLabel(startMillis: millis(2026, 10, 26, 11, 59), nowMillis: upNow, calendar: calendar) == "Now", "countdownLabel Now")
check(AppointmentAgenda.countdownLabel(startMillis: upNow + 30_000, nowMillis: upNow, calendar: calendar) == "In 1m", "countdownLabel rounds up sub-minute")
check(AppointmentAgenda.countdownLabel(startMillis: millis(2026, 10, 26, 12, 45), nowMillis: upNow, calendar: calendar) == "In 45m", "countdownLabel under 1 hour")
check(AppointmentAgenda.countdownLabel(startMillis: millis(2026, 10, 26, 14, 5), nowMillis: upNow, calendar: calendar) == "In 2h 5m", "countdownLabel under 3 hours")
check(AppointmentAgenda.countdownLabel(startMillis: millis(2026, 10, 26, 15, 0), nowMillis: upNow, calendar: calendar) == "Today at 3:00 PM", "countdownLabel Today at time")
check(AppointmentAgenda.countdownLabel(startMillis: millis(2026, 10, 27, 9, 0), nowMillis: upNow, calendar: calendar) == "Tomorrow at 9:00 AM", "countdownLabel Tomorrow at time")
check(AppointmentAgenda.upNextHeadline(startMillis: millis(2026, 10, 26, 15, 0), nowMillis: upNow, calendar: calendar) == "Up Next Today", "upNextHeadline Today")
check(AppointmentAgenda.upNextHeadline(startMillis: millis(2026, 10, 27, 9, 0), nowMillis: upNow, calendar: calendar) == "Up Next Tomorrow", "upNextHeadline Tomorrow")
check(AppointmentAgenda.upNextHeadline(startMillis: millis(2026, 10, 26, 11, 55), nowMillis: upNow, calendar: calendar) == "Happening Now", "upNextHeadline Happening Now")

// relevantAppointments (12h lookback)
let within12h = AppointmentRecord(id: "recent", startMillis: upNow - 6 * 3_600_000, location: "Coffee Shop", status: .scheduled, updatedAtMillis: upNow)
let olderThan12h = AppointmentRecord(id: "too-old", startMillis: upNow - 13 * 3_600_000, location: "Old", status: .scheduled, updatedAtMillis: upNow)
let upcomingForChoice = AppointmentRecord(id: "sooner", startMillis: upNow + 3_600_000, location: "Sooner Loc", status: .scheduled, updatedAtMillis: upNow)
let choices = OutcomeSavePlanner.relevantAppointments(records: [olderThan12h, completedLegacy, within12h, upcomingForChoice], legacyStartMillis: nil, nowMillis: upNow, timeZone: calendar.timeZone)
check(choices.map(\.id) == ["recent", "sooner"] && choices[0].label.hasSuffix(" · Coffee Shop"), "relevantAppointments filters 12h lookback and scheduled status")

// Contact notes section helpers
let sortedNotesSample = "[Oct 01, 2026 09:00 AM]: Older note\n\n[Oct 29, 2026 10:30 AM]: Newer note"
let sortedNotesResult = NoteUtils.sortedNotes(sortedNotesSample)
check(sortedNotesResult.map(\.content) == ["Newer note", "Older note"], "sortedNotes orders newest timestamp first")
check(NoteUtils.sortedNotes("   \n  ").isEmpty, "sortedNotes ignores blank input")
check(NoteUtils.canApplyEditedNotes(remoteNotes: sortedNotesSample, expectedOriginalNotes: sortedNotesSample), "canApplyEditedNotes allows unchanged remote base")
check(!NoteUtils.canApplyEditedNotes(remoteNotes: sortedNotesSample + "\n\nOther", expectedOriginalNotes: sortedNotesSample), "canApplyEditedNotes blocks stale overwrite")

print("Passed \(assertions) Step 2 & Step 3 compatibility checks.")
