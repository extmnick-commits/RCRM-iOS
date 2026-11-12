import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

struct SmsCoachTurn: Equatable {
    var explanation: String
    var message: String
    var alternatives: [String] = []
}

struct SmsChatLine: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    var role: Role
    var text: String
    var suggestedMessage: String?
    var alternatives: [String] = []
}

struct SmsContactContext: Equatable {
    var name: String
    var notes: String
    var category: String = ""
    var company: String = ""
    var jobTitle: String = ""
    var salesStage: String = ""
    var recruitStage: String = ""
    var followUpDate: Date? = nil
    var upcomingAppointment: String? = nil
    var openReminder: String? = nil
    var lastConnectedDate: Date? = nil
    var lastAttemptedDate: Date? = nil
    var targetMarketTraits: [String] = []

    init(
        name: String,
        notes: String,
        category: String = "",
        company: String = "",
        jobTitle: String = "",
        salesStage: String = "",
        recruitStage: String = "",
        followUpDate: Date? = nil,
        upcomingAppointment: String? = nil,
        openReminder: String? = nil,
        lastConnectedDate: Date? = nil,
        lastAttemptedDate: Date? = nil,
        targetMarketTraits: [String] = []
    ) {
        self.name = name
        self.notes = notes
        self.category = category
        self.company = company
        self.jobTitle = jobTitle
        self.salesStage = salesStage
        self.recruitStage = recruitStage
        self.followUpDate = followUpDate
        self.upcomingAppointment = upcomingAppointment
        self.openReminder = openReminder
        self.lastConnectedDate = lastConnectedDate
        self.lastAttemptedDate = lastAttemptedDate
        self.targetMarketTraits = targetMarketTraits
    }
}

struct SmsWritingPreferences: Equatable {
    var tone: String = "Natural"
    var length: String = "Standard"
    var emoji: Bool = false
    var example: String = ""

    var instructions: String {
        let sample = example.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Tone: \(tone). Length: \(length). Emojis: \(emoji ? "allowed" : "avoid")." +
            (sample.isEmpty ? "" : " Writing style example (style only, never copy facts): \(sample)")
    }
}

enum SmsDraftStyle: String, CaseIterable, Identifiable, Equatable {
    case smart = "smart"
    case warm = "warm"
    case direct = "direct"
    case question = "question"
    case reconnect = "reconnect"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .smart: return "Smart Match"
        case .warm: return "Warm"
        case .direct: return "Short"
        case .question: return "Question"
        case .reconnect: return "Follow-Up"
        }
    }

    var iconName: String {
        switch self {
        case .smart: return "sparkles"
        case .warm: return "heart.text.square"
        case .direct: return "bolt.fill"
        case .question: return "questionmark.bubble"
        case .reconnect: return "phone.arrow.up.right"
        }
    }
}

struct SmsQuickPrompt: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let prompt: String
    let iconName: String
}

struct SmsNoteInsight: Equatable {
    var primaryTopic: String?
    var rawBestDetail: String?
    var secondaryTopics: [String]
    var timingCue: String?
    var personalCue: String?
    var nextStepCue: String?
    var missedCallOrVoicemail: Bool
    var stageHighlight: String?
    var detectedIntent: LocalSmsDraft.Intent
    var contextBadges: [String]
}

enum SmsNoteCoach {
    static func firstName(from name: String) -> String {
        let first = SmartLogPlanner.formatFirstName(from: name)
        return first.isEmpty ? "there" : first
    }

    static func noteSummary(_ notes: String) -> String? {
        let insight = analyze(context: SmsContactContext(name: "", notes: notes))
        if let raw = insight.rawBestDetail {
            return clip(raw, max: 85)
        }
        if insight.missedCallOrVoicemail {
            return "Recent voicemail / missed call"
        }
        return nil
    }

    static func analyze(context: SmsContactContext) -> SmsNoteInsight {
        let bodies = latestBodies(context.notes, limit: 8)
        let newestNote = NoteUtils.sortedNotes(context.notes).first
        let missedCall: Bool
        if let note = newestNote, let timestamp = note.timestampMillis {
            let age = Date().timeIntervalSince1970 - Double(timestamp) / 1000
            missedCall = age >= 0 && age < 48 * 60 * 60 && detectsMissedCallOrVoicemail(in: note.content)
        } else {
            missedCall = false
        }

        var scoredCandidates: [(raw: String, phrase: String, score: Int)] = []
        var seenNormalized = Set<String>()

        for (noteIndex, body) in bodies.enumerated() {
            let recencyBonus = max(0, (4 - noteIndex) * 14)
            for rawSentence in sentences(in: body) {
                if isBoilerplateLine(rawSentence) { continue }
                let cleaned = plain(rawSentence)
                guard cleaned.count >= 6 else { continue }
                if isPureMissedCallLine(cleaned) { continue }
                let normKey = cleaned.lowercased()
                guard seenNormalized.insert(normKey).inserted else { continue }
                let itemScore = score(cleaned) + recencyBonus
                let phrased = naturalPhrase(from: cleaned)
                guard !phrased.isEmpty else { continue }
                scoredCandidates.append((raw: cleaned, phrase: phrased, score: itemScore))
            }
        }

        scoredCandidates.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.raw.count > rhs.raw.count
        }

        let best = scoredCandidates.first
        let secondary = scoredCandidates.dropFirst().prefix(3).map(\.phrase)

        let combinedNotes = bodies.joined(separator: ". ")
        // Relative times in undated or old CRM notes are not reliable scheduling options.
        let recentNotes = NoteUtils.sortedNotes(context.notes).filter { note in
            guard let timestamp = note.timestampMillis else { return false }
            let age = Date().timeIntervalSince1970 - Double(timestamp) / 1000
            return age >= 0 && age < 48 * 60 * 60
        }.map(\.content).joined(separator: ". ")
        let timing = extractTimingCue(from: recentNotes)
        let personal = extractPersonalCue(from: combinedNotes, context: context)
        let nextStep = extractNextStepCue(from: combinedNotes, openReminder: context.openReminder)
        let stageHighlight = resolveStageHighlight(context: context, notes: combinedNotes)
        let intentDetection = LocalSmsDraft.detectIntent(
            notes: "\(combinedNotes) \(context.openReminder ?? "") \(context.upcomingAppointment ?? "")",
            category: context.category
        )

        var badges: [String] = []
        if let raw = best?.raw {
            badges.append("Note: \(clip(raw, max: 46))")
        }
        if missedCall {
            badges.append("Left voicemail / missed call")
        }
        if let appt = nonEmpty(context.upcomingAppointment) {
            badges.append("Appt: \(clip(appt, max: 38))")
        }
        if let timing {
            badges.append("Best time: \(timing)")
        }
        if let reminder = nonEmpty(context.openReminder), best == nil {
            badges.append("Reminder: \(clip(reminder, max: 36))")
        }
        if let personal {
            badges.append("Rapport: \(clip(personal, max: 34))")
        }
        if let stageHighlight {
            badges.append("Stage: \(stageHighlight)")
        } else if let cat = nonEmpty(context.category) {
            badges.append(cat)
        }

        return SmsNoteInsight(
            primaryTopic: best?.phrase,
            rawBestDetail: best?.raw,
            secondaryTopics: Array(secondary),
            timingCue: timing,
            personalCue: personal,
            nextStepCue: nextStep,
            missedCallOrVoicemail: missedCall,
            stageHighlight: stageHighlight,
            detectedIntent: intentDetection.intent,
            contextBadges: badges
        )
    }

    // Use notes to identify the subject, never as a ready-made SMS fragment.
    private static func smsThreadReference(insight: SmsNoteInsight, context: SmsContactContext) -> String? {
        intentFollowUpLabel(for: insight.detectedIntent, category: context.category)
    }

    private static func intentFollowUpLabel(for intent: LocalSmsDraft.Intent, category: String) -> String? {
        let cat = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if cat.localizedCaseInsensitiveContains("Recruit") || intent == .recruit {
            return "the opportunity we discussed"
        }
        if cat.localizedCaseInsensitiveContains("Client") {
            return "your coverage and accounts"
        }
        switch intent {
        case .insurance: return "your coverage"
        case .investment: return "your retirement goals"
        case .appointment: return "our next steps"
        case .recruit: return "the opportunity we discussed"
        case .checkIn: return "our last conversation"
        }
    }

    static func suggest(name: String, notes: String) -> String {
        suggest(context: SmsContactContext(name: name, notes: notes), style: .smart)
    }

    static func suggest(context: SmsContactContext, style: SmsDraftStyle = .smart) -> String {
        let first = firstName(from: context.name)
        let insight = analyze(context: context)
        let threadOpt = smsThreadReference(insight: insight, context: context)
        let timing = insight.timingCue
        let appt = nonEmpty(context.upcomingAppointment)

        switch style {
        case .smart:
            if let appt {
                let thread = threadOpt ?? "our next steps"
                return sanitize("Hi \(first), looking forward to our upcoming meeting (\(appt)) to go over \(thread). Let me know if that time still works for you!")
            }
            if insight.missedCallOrVoicemail {
                if let thread = threadOpt {
                    let timeFollow = timing.map { " Does \($0) work to connect?" } ?? " Let me know when you have a few minutes to connect."
                    return sanitize("Hi \(first), sorry I missed you earlier! Following up on \(thread).\(timeFollow)")
                }
                return sanitize("Hi \(first), sorry I missed you earlier! Just wanted to touch base — let me know a good time for a quick call.")
            }
            if let thread = threadOpt {
                if let timing {
                    return sanitize("Hi \(first), following up on \(thread). Does \(timing) still work well for us to connect?")
                }
                return sanitize("Hi \(first), following up on \(thread). Let me know a good time to connect.")
            }
            return sanitize(fallbackSuggestion(first: first, context: context, insight: insight, style: .smart))

        case .warm:
            let rapportLead: String
            if let personal = insight.personalCue {
                rapportLead = "Hi \(first), hope you and \(personal) are doing well! "
            } else if let company = nonEmpty(context.company) {
                rapportLead = "Hi \(first), hope things are going great over at \(company)! "
            } else {
                rapportLead = "Hi \(first), hope your week is going well! "
            }
            if let thread = threadOpt {
                let timeAsk = timing.map { "Would \($0) be a good time to catch up?" } ?? "Let me know whenever you have a few minutes to catch up."
                return sanitize("\(rapportLead)Wanted to follow up on \(thread). \(timeAsk)")
            }
            return sanitize(fallbackSuggestion(first: first, context: context, insight: insight, style: .warm))

        case .direct:
            if let appt {
                return sanitize("Hi \(first) — confirming our meeting (\(appt)). Let me know if you need any adjustments.")
            }
            if let thread = threadOpt {
                let timeAsk = timing.map { "Are you free \($0)?" } ?? "When can we connect for 5 minutes?"
                return sanitize("Hi \(first) — checking in on \(thread). \(timeAsk)")
            }
            return sanitize(fallbackSuggestion(first: first, context: context, insight: insight, style: .direct))

        case .question:
            if let appt {
                return sanitize("Hi \(first), does our upcoming meeting (\(appt)) still work well for your schedule?")
            }
            if let thread = threadOpt {
                if let timing {
                    return sanitize("Hi \(first), did you have any questions on \(thread), or would \(timing) work to go through it together?")
                }
                return sanitize("Hi \(first), did you have any questions about \(thread), or is there a good time this week to walk through it?")
            }
            return sanitize(fallbackSuggestion(first: first, context: context, insight: insight, style: .question))

        case .reconnect:
            if let thread = threadOpt {
                return sanitize("Hi \(first), sorry we haven't connected yet! Wanted to circle back on \(thread) — what day works best for a quick sync?")
            }
            return sanitize("Hi \(first), wanted to reach back out and see how things are going! Let me know if you have a few minutes to connect this week.")
        }
    }

    static func preferredSuggestion(context: SmsContactContext, preferences: SmsWritingPreferences) -> String {
        let style: SmsDraftStyle
        switch preferences.tone {
        case "Warm": style = .warm
        case "Professional": style = .direct
        default: style = .smart
        }
        let first = firstName(from: context.name)
        var message = suggest(context: context, style: style)
        if preferences.tone == "Casual" { message = casualize(message, first: first) }
        if preferences.length == "Short" { message = shorten(message, first: first, topic: nil) }
        if preferences.length == "Detailed" {
            message = expandWithContext(message, first: first, insight: analyze(context: context), context: context)
        }
        if preferences.emoji { message = addFriendlyEmoji(to: message) }
        return sanitize(message)
    }

    static func variations(for context: SmsContactContext) -> [(style: SmsDraftStyle, message: String, badge: String)] {
        let insight = analyze(context: context)
        let primaryBadge = insight.contextBadges.first ?? "Profile match"
        return SmsDraftStyle.allCases.map { style in
            (
                style: style,
                message: suggest(context: context, style: style),
                badge: primaryBadge
            )
        }
    }

    static func quickPrompts(for context: SmsContactContext) -> [SmsQuickPrompt] {
        let insight = analyze(context: context)
        var prompts: [SmsQuickPrompt] = []

        prompts.append(SmsQuickPrompt(label: "What should I do?", prompt: "What should I know before I reach out, and what's the best next step?", iconName: "bubble.left.and.text.bubble.right"))
        if insight.rawBestDetail != nil || !insight.secondaryTopics.isEmpty {
            prompts.append(SmsQuickPrompt(label: "Summarize notes", prompt: "Summarize what we know from the notes and best next step", iconName: "doc.text.magnifyingglass"))
        }
        if insight.missedCallOrVoicemail {
            prompts.append(SmsQuickPrompt(label: "Voicemail follow-up", prompt: "Write a warm follow-up to the voicemail I left", iconName: "phone.fill.arrow.up.right"))
        }
        if nonEmpty(context.upcomingAppointment) != nil {
            prompts.append(SmsQuickPrompt(label: "Confirm meeting", prompt: "Confirm our upcoming appointment and keep it friendly", iconName: "calendar.badge.checkmark"))
        }
        if let timing = insight.timingCue {
            prompts.append(SmsQuickPrompt(label: "Ask about \(timing)", prompt: "Ask if \(timing) still works to connect", iconName: "clock"))
        } else {
            prompts.append(SmsQuickPrompt(label: "Offer 2 times", prompt: "Suggest two easy time options to connect", iconName: "calendar.badge.clock"))
        }
        if insight.personalCue != nil || nonEmpty(context.company) != nil {
            prompts.append(SmsQuickPrompt(label: "Personal touch", prompt: "Make it warmer and include their personal or work details from the notes", iconName: "heart"))
        }
        prompts.append(SmsQuickPrompt(label: "Shorter", prompt: "Make it shorter and punchier", iconName: "arrow.down.right.and.arrow.up.left"))
        prompts.append(SmsQuickPrompt(label: "Warmer", prompt: "Make it warmer and more conversational", iconName: "sun.max"))
        prompts.append(SmsQuickPrompt(label: "Try another angle", prompt: "Give me a different angle for this text", iconName: "arrow.triangle.2.circlepath"))

        return prompts
    }

    static func reply(name: String, notes: String, currentDraft: String, prompt: String) -> SmsCoachTurn {
        reply(
            context: SmsContactContext(name: name, notes: notes),
            currentDraft: currentDraft,
            history: [],
            prompt: prompt
        )
    }

    static func reply(
        context: SmsContactContext,
        currentDraft: String,
        history: [SmsChatLine] = [],
        prompt: String
    ) -> SmsCoachTurn {
        let first = firstName(from: context.name)
        let ask = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let insight = analyze(context: context)
        let detail = insight.rawBestDetail
        let topic = smsThreadReference(insight: insight, context: context)
        let draft = currentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let starting = draft.isEmpty ? suggest(context: context, style: .smart) : draft

        guard !ask.isEmpty else {
            return SmsCoachTurn(
                explanation: detail == nil
                    ? "There aren't notes yet, so this is a tailored \(context.category.isEmpty ? "check-in" : context.category.lowercased() + " check-in")."
                    : "This follows the latest note about \(clip(detail ?? "", max: 80)).",
                message: sanitize(starting)
            )
        }

        if let pasted = pastedMessage(from: ask) {
            return SmsCoachTurn(explanation: "Using the exact message you wrote.", message: sanitize(pasted))
        }

        let lower = ask.lowercased()
        if lower.hasPrefix("client reply:") {
            return SmsCoachTurn(
                explanation: "I can't interpret the reply on this device, so here's a general starting point. Edit it to address what they said.",
                message: "Thanks for letting me know! I appreciate the update. Let me know what works best for you."
            )
        }

        // Preserve the draft for conversational requests to add something to it.
        if wantsAddition(lower) {
            if lower.contains("coffee"), !lower.contains("don't add"), !lower.contains("do not add"), !lower.contains("without") {
                let invitation = "Would you like to meet up for coffee and catch up?"
                let updated = starting.lowercased().contains("coffee") ? starting : "\(starting) \(invitation)"
                return SmsCoachTurn(explanation: "I added a coffee catch-up to your draft.", message: updated)
            }
            return SmsCoachTurn(
                explanation: "I can help add that. Try telling me the exact sentence you'd like to include, or revise the draft directly.",
                message: ""
            )
        }

        // Chat stays conversational unless the advisor asked for a new or edited text.
        if !wantsTextDraft(ask) {
            return buildConversationTurn(context: context, insight: insight, ask: ask)
        }

        // 2. Handle "Try another angle" / "Give me options" / "Variations"
        if wantsAlternativeAngle(lower) {
            return buildAlternativeAngleTurn(context: context, insight: insight, currentDraft: starting, history: history)
        }

        // 3. Handle targeted outreach intents (Voicemail, Appointment, Referral, Two Times, Personal Touch)
        var message = starting
        var appliedSpecialIntent: String? = nil

        if wantsVoicemailFollowUp(lower) {
            let timeAsk = extractExplicitTimeFromPrompt(ask) ?? insight.timingCue
            let ending = timeAsk.map { "Does \($0) work for a quick call?" } ?? "Let me know when you have a few minutes to connect."
            if let topic {
                message = "Hi \(first), sorry I missed you earlier — I left a quick voicemail regarding \(topic). \(ending)"
            } else {
                message = "Hi \(first), sorry I missed you earlier — I left a quick voicemail with an update. \(ending)"
            }
            appliedSpecialIntent = "voicemail follow-up"
        } else if wantsAppointmentConfirmation(lower) {
            let apptText = nonEmpty(context.upcomingAppointment) ?? extractExplicitTimeFromPrompt(ask) ?? insight.timingCue
            if let apptText {
                if let topic {
                    message = "Hi \(first), looking forward to our meeting (\(apptText)) to go over \(topic)! Please let me know if that time still works well for you."
                } else {
                    message = "Hi \(first), confirming our upcoming meeting (\(apptText)). Looking forward to connecting — let me know if anything changes on your schedule!"
                }
            } else if let topic {
                message = "Hi \(first), looking forward to our upcoming meeting to review \(topic)! Please let me know if our scheduled time still works best for you."
            } else {
                message = "Hi \(first), looking forward to our upcoming meeting! Please let me know if our scheduled time still works well for you."
            }
            appliedSpecialIntent = "appointment confirmation"
        } else if wantsReferralAsk(lower) {
            if let topic {
                message = "Hi \(first), glad we could connect on \(topic)! If anyone in your circle is also looking for help with this, I'd be honored to take great care of them."
            } else {
                message = "Hi \(first), hope you're doing great! I'm expanding who I'm helping this month — if anyone comes to mind who could use a second opinion on their financial goals, I'd love to be a resource."
            }
            appliedSpecialIntent = "referral outreach"
        } else if wantsTwoTimeOptions(lower) {
            let customTime = extractExplicitTimeFromPrompt(ask) ?? insight.timingCue
            let timeQuestion = customTime.map { "Would \($0) work for a quick call?" } ?? "What are a couple of times that work for a quick call?"
            if let topic {
                message = "Hi \(first), following up on \(topic). \(timeQuestion)"
            } else {
                message = "Hi \(first), wanted to catch up briefly! \(timeQuestion)"
            }
            appliedSpecialIntent = "two time options"
        } else if wantsPersonalTouch(lower) {
            message = suggest(context: context, style: .warm)
            appliedSpecialIntent = "personal rapport details"
        } else if let instruction = instructionBody(from: ask), !isStyleOnly(ask) {
            message = composeFromAdvisorInstruction(
                instruction: instruction,
                first: first,
                topic: topic,
                timingCue: insight.timingCue
            )
        }

        message = applyStyleToneAndTopicTransforms(
            message: message,
            ask: ask,
            lower: lower,
            first: first,
            insight: insight,
            context: context,
            topic: topic,
            appliedSpecialIntent: appliedSpecialIntent
        )

        let explanation = buildTurnExplanation(
            detail: detail,
            insight: insight,
            context: context,
            ask: ask,
            appliedSpecialIntent: appliedSpecialIntent
        )

        return SmsCoachTurn(
            explanation: explanation,
            message: sanitize(message),
            alternatives: []
        )
    }

    /// Shared composable style steps used by `reply` and to post-process on-device model output so "warmer", "shorter", etc. always change the draft.
    private static func applyStyleToneAndTopicTransforms(
        message: String,
        ask: String,
        lower: String,
        first: String,
        insight: SmsNoteInsight,
        context: SmsContactContext,
        topic: String?,
        appliedSpecialIntent: String?
    ) -> String {
        var message = message

        if let explicitTime = extractExplicitTimeFromPrompt(ask),
           appliedSpecialIntent == nil,
           !message.lowercased().contains(explicitTime.lowercased()) {
            message = injectTimeOption(into: message, timePhrase: explicitTime)
        }

        if wantsPersonalTouch(lower), let personal = insight.personalCue, !message.lowercased().contains(personal.lowercased().prefix(8)) {
            message = warm(message, first: first, personalCue: personal, company: context.company)
        }

        if wantsWarmer(lower) {
            let low = message.lowercased()
            // If already warmed once, deepen with an extra supportive line instead of stacking duplicate "hope you're" openers.
            if low.contains("hope you") || low.contains("hope things") {
                message = soften(expandWithContext(message, first: first, insight: insight, context: context))
            } else {
                message = warm(message, first: first, personalCue: insight.personalCue, company: context.company)
            }
        }
        if wantsCasual(lower) {
            message = casualize(message, first: first)
        }
        if wantsDirect(lower) {
            message = direct(message, first: first, topic: topic, timingCue: insight.timingCue)
        }
        if wantsSofter(lower) {
            message = soften(message)
        }
        if wantsLonger(lower) {
            message = expandWithContext(message, first: first, insight: insight, context: context)
        }
        if wantsShorter(lower) {
            message = shorten(message, first: first, topic: topic)
        }
        if wantsQuestion(lower), !message.contains("?") {
            message = ensureEndsWithQuestion(message, timingCue: insight.timingCue)
        }
        if wantsEmoji(lower) {
            message = addFriendlyEmoji(to: message)
        } else if wantsNoEmoji(lower) {
            message = stripEmojis(from: message)
        }
        if let avoided = avoidedTopic(from: lower) {
            message = removeTopic(avoided, from: message, first: first)
        }

        return message
    }

    /// True when the advisor asked to write or edit a text. Everything else is a conversation turn with no new suggestion card.
    static func wantsTextDraft(_ ask: String) -> Bool {
        let trimmed = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        if pastedMessage(from: trimmed) != nil { return true }
        if lower.hasPrefix("client reply:") { return true }
        if wantsAddition(lower) { return true }
        if wantsAlternativeAngle(lower) { return true }
        if wantsVoicemailFollowUp(lower) || wantsAppointmentConfirmation(lower) || wantsReferralAsk(lower) || wantsTwoTimeOptions(lower) {
            return true
        }
        if wantsPersonalTouch(lower), !isAdvisorQuestionAboutContact(lower), !lower.contains("?") {
            return true
        }
        if isStyleOnly(trimmed) || wantsWarmer(lower) || wantsCasual(lower) || wantsDirect(lower) || wantsSofter(lower) || wantsLonger(lower) || wantsShorter(lower) || wantsEmoji(lower) || wantsNoEmoji(lower) {
            return true
        }
        let draftCues = [
            "write ", "draft ", "rewrite", "text them", "text him", "text her", "text this",
            "send a ", "suggest a text", "suggest a message", "give me a text", "give me a message",
            "the text", "the message", "sms", "make it about", "make this about",
            "tell them", "tell him", "tell her", "say that", "ask them", "ask him", "ask her", "ask if",
            "mention ", "include ", "bring up"
        ]
        return draftCues.contains { lower.contains($0) }
    }

    private static func wantsAddition(_ lower: String) -> Bool {
        ["add ", "add in", "include ", "put in ", "work in "].contains { lower.contains($0) }
    }

    /// After the on-device LLM returns text, optionally run the style pipeline for tone chips and style-only prompts — not for full rewrites the model already composed.
    static func shouldPostProcessAppleReply(prompt: String) -> Bool {
        let ask = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ask.isEmpty, wantsTextDraft(ask) else { return false }
        let lower = ask.lowercased()
        if isAdvisorQuestionAboutContact(lower) { return false }
        if wantsAlternativeAngle(lower) { return false }
        if lower.hasPrefix("client reply:") { return false }
        if pastedMessage(from: ask) != nil { return false }
        if wantsPersonalTouch(lower) { return true }
        return isStyleOnly(ask) || wantsWarmer(lower) || wantsCasual(lower) || wantsDirect(lower)
            || wantsSofter(lower) || wantsLonger(lower) || wantsShorter(lower)
            || wantsQuestion(lower) || wantsEmoji(lower) || wantsNoEmoji(lower)
            || avoidedTopic(from: lower) != nil
            || extractExplicitTimeFromPrompt(ask) != nil
    }

    /// After the on-device LLM returns text, run the same style pipeline so chip prompts and free-text edits behave like the offline coach.
    static func refineDraftForPrompt(
        context: SmsContactContext,
        draft: String,
        prompt: String
    ) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return sanitize(draft) }
        let first = firstName(from: context.name)
        let insight = analyze(context: context)
        let topic = smsThreadReference(insight: insight, context: context)
        let lower = trimmedPrompt.lowercased()
        let message = sanitize(draft.trimmingCharacters(in: .whitespacesAndNewlines))
        return sanitize(
            applyStyleToneAndTopicTransforms(
                message: message,
                ask: trimmedPrompt,
                lower: lower,
                first: first,
                insight: insight,
                context: context,
                topic: topic,
                appliedSpecialIntent: nil
            )
        )
    }

    // MARK: - Note Parsing & Natural Phrase Conversion

    private static func latestBodies(_ notes: String, limit: Int = 6) -> [String] {
        let parsed = NoteUtils.sortedNotes(notes).map {
            $0.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        if !parsed.isEmpty { return Array(parsed.prefix(limit)) }
        let raw = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? [] : [raw]
    }

    private static func bestDetail(from notes: String) -> String? {
        analyze(context: SmsContactContext(name: "", notes: notes)).rawBestDetail
    }

    private static func sentences(in text: String) -> [String] {
        let cleanedVoice = text.replacingOccurrences(of: #"(?i)\[voice log\]:?\s*"#, with: "", options: .regularExpression)
        return cleanedVoice.components(separatedBy: CharacterSet(charactersIn: ".!?\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isBoilerplateLine(_ sentence: String) -> Bool {
        let lower = sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return true }
        if lower.hasPrefix("moved to ") && lower.hasSuffix(" stage") { return true }
        if lower.hasPrefix("paused:") || lower.hasPrefix("closed:") { return true }
        let exactBoilerplate: Set<String> = [
            "connected", "no answer", "voicemail left", "left voicemail", "left vm",
            "message sent", "meeting completed", "no-show", "rescheduled", "reminder completed",
            "called", "texted", "emailed"
        ]
        return exactBoilerplate.contains(lower)
    }

    private static func isPureMissedCallLine(_ cleaned: String) -> Bool {
        let lower = cleaned.lowercased()
        let missedPhrases: Set<String> = [
            "left voicemail", "left a voicemail", "left vm", "no answer",
            "didn't answer", "did not answer", "went to voicemail", "missed call",
            "tried calling", "called no answer"
        ]
        return missedPhrases.contains(lower)
    }

    private static func detectsMissedCallOrVoicemail(in text: String) -> Bool {
        let lower = text.lowercased()
        let cues = ["voicemail", "left vm", "no answer", "didn't answer", "missed call", "went to vm"]
        return cues.contains { lower.contains($0) }
    }

    private static func plain(_ sentence: String) -> String {
        var text = sentence.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: #"^(?:[-•*]\s*)"#, with: "", options: .regularExpression)
        let prefixes = [
            "connected - ", "connected: ", "left voicemail about ", "left a voicemail about ",
            "left vm about ", "talked about ", "talked with them about ", "talked with him about ",
            "talked with her about ", "discussed ", "spoke about ", "spoke with them about ",
            "spoke with him about ", "spoke with her about ", "conversation about ", "chatted about ",
            "he said ", "she said ", "they said ", "said ", "says ", "mentioned ", "mentions ",
            "follow up on ", "following up on ", "follow up about ", "need to follow up on ",
            "note: ", "notes: ", "outcome: "
        ]
        var changed = true
        while changed {
            changed = false
            let lower = text.lowercased()
            for prefix in prefixes where lower.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
                break
            }
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " .,-:"))
    }

    static func naturalPhrase(from rawDetail: String, maxLength: Int = 95) -> String {
        var text = plain(rawDetail)
        guard !text.isEmpty else { return "" }

        // Transform 3rd-person lead-ins into natural 2nd-person gerunds or noun phrases
        let verbLeadTransformations: [(prefix: String, verbToGerund: Bool)] = [
            ("he wants to ", true), ("she wants to ", true), ("they want to ", true),
            ("client wants to ", true), ("prospect wants to ", true), ("wants to ", true),
            ("wanted to ", true), ("he would like to ", true), ("she would like to ", true),
            ("would like to ", true), ("looking to ", true), ("he is looking to ", true),
            ("she is looking to ", true), ("needs to ", true), ("he needs to ", true),
            ("she needs to ", true), ("asked to ", true), ("he asked to ", true),
            ("she asked to ", true), ("waiting to ", true)
        ]

        let lower = text.lowercased()
        var convertedVerbLead = false
        for item in verbLeadTransformations where lower.hasPrefix(item.prefix) {
            let remainder = String(text.dropFirst(item.prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            text = item.verbToGerund ? toGerundPhrase(remainder) : remainder
            convertedVerbLead = true
            break
        }

        if !convertedVerbLead {
            let nounLeadPrefixes = [
                "he is interested in ", "she is interested in ", "they are interested in ",
                "interested in ", "looking into ", "he is looking into ", "she is looking into ",
                "asking about ", "asked about ", "he asked about ", "she asked about ",
                "inquired about ", "questions about ", "has questions about "
            ]
            let currentLower = text.lowercased()
            for prefix in nounLeadPrefixes where currentLower.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Convert 3rd-person pronouns in the phrase to 2nd-person ("your" / "you")
        text = replaceThirdPersonPronouns(in: text)

        // Lowercase initial character unless it's an acronym (IRA, IUL, BOP, FNA, 401k) or proper noun
        text = normalizeLeadingCase(text)

        return clip(text, max: maxLength)
    }

    private static func toGerundPhrase(_ phrase: String) -> String {
        let parts = phrase.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard let firstWord = parts.first else { return phrase }
        let rest = parts.count > 1 ? " " + parts[1] : ""
        let lowerVerb = firstWord.lowercased()

        let gerundMap: [String: String] = [
            "review": "reviewing", "compare": "comparing", "discuss": "discussing",
            "schedule": "scheduling", "set": "setting", "roll": "rolling",
            "rollover": "rolling over", "move": "moving", "transfer": "transferring",
            "update": "updating", "add": "adding", "increase": "increasing",
            "lower": "lowering", "check": "checking", "see": "seeing",
            "get": "getting", "start": "starting", "open": "opening",
            "apply": "applying", "finish": "finishing", "complete": "completing",
            "reschedule": "rescheduling", "confirm": "confirming", "attend": "attending",
            "join": "joining", "learn": "learning", "explore": "exploring",
            "protect": "protecting", "cover": "covering", "save": "saving",
            "invest": "investing", "talk": "talking", "meet": "meeting",
            "go": "going", "look": "looking", "find": "finding", "wait": "waiting"
        ]

        if let mapped = gerundMap[lowerVerb] {
            return mapped + rest
        }
        return phrase
    }

    private static func replaceThirdPersonPronouns(in text: String) -> String {
        var result = text
        let replacements: [(pattern: String, template: String)] = [
            (#"(?i)\b(?:his|her|their)\b"#, "your"),
            (#"(?i)\b(?:him|them)\b"#, "you"),
            (#"(?i)\b(?:he|she)\s+has\b"#, "you have"),
            (#"(?i)\b(?:he|she)\s+is\b"#, "you're"),
            (#"(?i)\b(?:he's|she's|they're)\b"#, "you're")
        ]
        for item in replacements {
            result = result.replacingOccurrences(of: item.pattern, with: item.template, options: .regularExpression)
        }
        return result
    }

    private static func normalizeLeadingCase(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let firstWord = text.split(separator: " ").first.map(String.init) ?? text
        let preservedPrefixes = ["IRA", "IUL", "BOP", "FNA", "IBA", "Roth", "Zoom", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        if preservedPrefixes.contains(where: { firstWord.hasPrefix($0) }) {
            return text
        }
        // If first word is all caps (2+ letters), keep it
        if firstWord.count >= 2 && firstWord == firstWord.uppercased() && firstWord.rangeOfCharacter(from: .letters) != nil {
            return text
        }
        var copy = text
        if let firstChar = copy.first {
            copy.replaceSubrange(copy.startIndex...copy.startIndex, with: String(firstChar).lowercased())
        }
        return copy
    }

    private static func score(_ sentence: String) -> Int {
        let lower = sentence.lowercased()
        var value = min(sentence.count, 130)
        let highSignalCues = [
            "quote", "policy", "coverage", "insurance", "term", "iul", "whole life", "premium",
            "beneficiary", "beneficiaries", "underwriting", "rollover", "401k", "403b", "ira",
            "roth", "pension", "annuity", "portfolio", "invest", "retirement", "fna",
            "bop", "iba", "licensing", "exam", "interview", "overview", "opportunity",
            "recruit", "appointment", "meeting", "schedule", "reschedule", "zoom",
            "$", "k ", "000"
        ]
        let mediumSignalCues = [
            "follow", "call", "text", "email", "send", "packet", "comparison", "numbers",
            "options", "spouse", "wife", "husband", "kids", "children", "family", "mortgage",
            "home", "tomorrow", "today", "monday", "tuesday", "wednesday", "thursday", "friday",
            "next week", "after "
        ]
        for cue in highSignalCues where lower.contains(cue) { value += 45 }
        for cue in mediumSignalCues where lower.contains(cue) { value += 25 }
        if isBoilerplateLine(sentence) { value -= 200 }
        return value
    }

    private static func extractTimingCue(from notes: String) -> String? {
        guard !notes.isEmpty else { return nil }
        let patterns = [
            #"(?i)\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+(?:morning|afternoon|evening|after\s+\d+(?::\d+)?\s*(?:am|pm)?)"#,
            #"(?i)\b(?:after|around|before)\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#,
            #"(?i)\b(?:this|next)\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|weekend|month)\b"#,
            #"(?i)\b(?:tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#,
            #"(?i)\b(?:in the\s+)?(?:morning|afternoon|evening)s?\b"#
        ]
        let ns = notes as NSString
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: notes, range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty { return raw }
            }
        }
        return nil
    }

    private static func extractPersonalCue(from notes: String, context: SmsContactContext) -> String? {
        let ns = notes as NSString
        // Check for named spouse/partner e.g. "wife Sarah", "husband Mark", "spouse Alex"
        if let regex = try? NSRegularExpression(pattern: #"(?:\bwife|\bhusband|\bspouse|\bpartner)\s+([A-Z][a-z]{2,15})"#),
           let match = regex.firstMatch(in: notes, range: NSRange(location: 0, length: ns.length)),
           match.numberOfRanges > 1 {
            let spouseName = ns.substring(with: match.range(at: 1))
            return spouseName
        }
        let lower = notes.lowercased()
        if lower.contains("kids") || lower.contains("children") || lower.contains("family") || lower.contains("baby") {
            return "your family"
        }
        if lower.contains("wife") || lower.contains("husband") || lower.contains("spouse") {
            return "your family"
        }
        if context.targetMarketTraits.contains(where: { $0.caseInsensitiveCompare("Children") == .orderedSame || $0.caseInsensitiveCompare("Married") == .orderedSame }) {
            return "your family"
        }
        return nil
    }

    private static func extractNextStepCue(from notes: String, openReminder: String?) -> String? {
        let patterns = [
            #"(?i)\b(?:send|email|text|share|prepare|run)\s+(?:over\s+)?(?:the\s+|a\s+|his\s+|her\s+|their\s+)?([a-z0-9\s$\-]{4,38})"#,
            #"(?i)\b(?:confirm|reschedule|book|set up)\s+(?:our\s+|the\s+)?([a-z0-9\s]{4,32})"#
        ]
        let ns = notes as NSString
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: notes, range: NSRange(location: 0, length: ns.length)) {
                let matched = ns.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: " .,-"))
                if matched.count >= 8 { return replaceThirdPersonPronouns(in: matched) }
            }
        }
        if let rem = nonEmpty(openReminder), rem.lowercased() != "follow up" && rem.lowercased() != "reminder" {
            return rem
        }
        return nil
    }

    private static func resolveStageHighlight(context: SmsContactContext, notes: String) -> String? {
        if context.category.localizedCaseInsensitiveContains("Recruit"),
           let stage = nonEmpty(context.recruitStage),
           stage.lowercased() != "recruit prospect" {
            return stage
        }
        if let stage = nonEmpty(context.salesStage),
           stage.lowercased() != "new lead" {
            return stage
        }
        if let regex = try? NSRegularExpression(pattern: #"Moved to (.+?) stage"#),
           let match = regex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
           match.numberOfRanges > 1 {
            return (notes as NSString).substring(with: match.range(at: 1))
        }
        return nil
    }

    private static func fallbackSuggestion(
        first: String,
        context: SmsContactContext,
        insight: SmsNoteInsight,
        style: SmsDraftStyle
    ) -> String {
        let isRecruit = context.category.localizedCaseInsensitiveContains("Recruit") || insight.detectedIntent == .recruit
        let isClient = context.category.localizedCaseInsensitiveContains("Client")
        let company = nonEmpty(context.company)

        if isRecruit {
            switch style {
            case .direct:
                return "Hi \(first) — touching base on the business overview. When do you have 10 minutes to connect?"
            case .question:
                return "Hi \(first), have you had a chance to think about the partnership opportunity we discussed?"
            case .warm, .smart, .reconnect:
                if let company {
                    return "Hi \(first), hope things are going well at \(company)! Wanted to follow up on the business opportunity and see when you have a few minutes to connect."
                }
                return "Hi \(first), hope your week is going well! Wanted to follow up on the business opportunity — let me know a good time to connect."
            }
        }

        if isClient {
            switch style {
            case .direct:
                return "Hi \(first) — checking in for your periodic account and coverage review. What day this week works for a quick call?"
            case .question:
                return "Hi \(first), how have things been going? Wanted to check if you have any questions on your coverage or accounts."
            case .warm, .smart, .reconnect:
                if let personal = insight.personalCue {
                    return "Hi \(first), hope you and \(personal) are doing great! Just checking in to see if you need anything with your coverage or accounts."
                }
                return "Hi \(first), hope you're doing well! Just checking in to see if you had any questions on your coverage or if anything has changed on your end."
            }
        }

        switch style {
        case .direct:
            return "Hi \(first) — checking in on our next steps. When do you have a few minutes for a quick call?"
        case .question:
            return "Hi \(first), how is your week going? Let me know if there's a good time for us to connect briefly."
        case .warm:
            if let company {
                return "Hi \(first), hope everything is going well at \(company)! Just checking in — let me know when you have a few minutes to connect."
            }
            return "Hi \(first), hope your week is off to a great start! Just checking in — let me know when you have a few minutes to connect."
        case .smart, .reconnect:
            return "Hi \(first), just checking in. Let me know when you have a few minutes to connect."
        }
    }

    // MARK: - Advisor Prompt Analysis & Conversational Co-Pilot

    private static func pastedMessage(from ask: String) -> String? {
        let lower = ask.lowercased()
        for prefix in ["use this:", "send this:", "text this:"] where lower.hasPrefix(prefix) {
            let body = ask.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : body
        }
        return nil
    }

    private static func isAdvisorQuestionAboutContact(_ lower: String) -> Bool {
        let questionTriggers = [
            "what do we know", "what do you know", "summarize", "summary", "what's in the notes",
            "what is in the notes", "what are the notes", "read the notes", "what did we talk about",
            "what did we discuss", "last time", "catch me up", "brief me", "who is this",
            "who is ", "tell me about ", "what's the best angle", "what is the best angle",
            "why did you", "why this", "when should i", "best time to", "what's the next step"
        ]
        if questionTriggers.contains(where: { lower.contains($0) }) {
            // Make sure they didn't explicitly say "write a text that says..."
            if !lower.hasPrefix("write ") && !lower.hasPrefix("text ") && !lower.hasPrefix("say ") && !lower.hasPrefix("tell them") {
                return true
            }
        }
        return false
    }

    private static func contactFactPoints(context: SmsContactContext, insight: SmsNoteInsight) -> [String] {
        let first = firstName(from: context.name)
        var points: [String] = []

        if let raw = insight.rawBestDetail {
            points.append("Latest note focus: \(raw).")
        } else {
            points.append("No detailed notes are saved for \(first) yet.")
        }
        if !insight.secondaryTopics.isEmpty {
            points.append("Earlier note context: \(insight.secondaryTopics.joined(separator: "; ")).")
        }
        if insight.missedCallOrVoicemail {
            points.append("Recent attempt: Left voicemail / missed call.")
        }
        if let timing = insight.timingCue {
            points.append("Preferred timing mentioned: \(timing).")
        }
        if let appt = nonEmpty(context.upcomingAppointment) {
            points.append("Upcoming appointment: \(appt).")
        }
        if let rem = nonEmpty(context.openReminder) {
            points.append("Open reminder: \(rem).")
        }
        if let personal = insight.personalCue {
            points.append("Personal rapport cue: \(personal).")
        }
        if let company = nonEmpty(context.company) {
            let role = nonEmpty(context.jobTitle).map { "\($0) at \(company)" } ?? company
            points.append("Work: \(role).")
        }
        if let stage = insight.stageHighlight {
            points.append("Pipeline stage: \(stage).")
        } else if let cat = nonEmpty(context.category) {
            points.append("Category: \(cat).")
        }
        return points
    }

    private static func mentionsContactContext(_ lower: String, first: String) -> Bool {
        let cues = [
            "note", "notes", "job", "work", "company", "wife", "husband", "family", "kids",
            "stage", "appointment", "meeting", "reminder", "follow", "next step", "pipeline",
            "who is", "about him", "about her", "about them", "this contact", "this lead",
            first.lowercased()
        ]
        return cues.contains { lower.contains($0) }
    }

    /// Answers in the thread only. A suggestion card is reserved for draft requests.
    private static func buildConversationTurn(
        context: SmsContactContext,
        insight: SmsNoteInsight,
        ask: String
    ) -> SmsCoachTurn {
        let first = firstName(from: context.name)
        let lower = ask.lowercased()
        let points = contactFactPoints(context: context, insight: insight)
        let facts = points.joined(separator: " ")

        if isAdvisorQuestionAboutContact(lower) || mentionsContactContext(lower, first: first) {
            let answer = facts.isEmpty
                ? "I don't have detailed notes on \(first) yet. Tell me what you want to cover and I can draft the text."
                : "\(facts) Ask me anything else, or tell me how you want the text to change."
            return SmsCoachTurn(explanation: answer, message: "", alternatives: [])
        }

        if ask.contains("?") {
            let known = facts.isEmpty ? "" : " What I do have: \(facts)"
            return SmsCoachTurn(
                explanation: "I can talk through \(first)'s record and change the text whenever you ask. I don't have anything saved that answers that directly.\(known)",
                message: "",
                alternatives: []
            )
        }

        return SmsCoachTurn(
            explanation: "Noted. I'll keep that in mind for \(first). Ask me anything else, or say if you want it reflected in the text.",
            message: "",
            alternatives: []
        )
    }

    private static func wantsAlternativeAngle(_ lower: String) -> Bool {
        let triggers = [
            "another angle", "different angle", "try another", "another option", "other option",
            "give me options", "show options", "3 options", "three options", "variations",
            "something else", "something different", "rewrite", "try again"
        ]
        return triggers.contains { lower.contains($0) }
    }

    private static func buildAlternativeAngleTurn(
        context: SmsContactContext,
        insight: SmsNoteInsight,
        currentDraft: String,
        history: [SmsChatLine]
    ) -> SmsCoachTurn {
        let allVariations = variations(for: context)
        let previousMessages = Set(history.compactMap(\.suggestedMessage) + [currentDraft])
        let nextPick = allVariations.first(where: { !previousMessages.contains($0.message) })
            ?? allVariations.first(where: { $0.message != currentDraft })
            ?? allVariations[0]

        let detailText = insight.rawBestDetail.map { " while keeping it tied to \(clip($0, max: 65))" } ?? ""
        let explanation = "Switched to a \(nextPick.style.label.lowercased()) angle\(detailText). Reply with what to change, or ask for another angle."
        return SmsCoachTurn(
            explanation: explanation,
            message: nextPick.message,
            alternatives: []
        )
    }

    private static func wantsVoicemailFollowUp(_ lower: String) -> Bool {
        lower.contains("voicemail") || lower.contains("left vm") || lower.contains("left a vm") || lower.contains("missed call") || lower.contains("missed them") || lower.contains("missed him") || lower.contains("missed her")
    }

    private static func wantsAppointmentConfirmation(_ lower: String) -> Bool {
        lower.contains("confirm") && (lower.contains("appointment") || lower.contains("meeting") || lower.contains("appt") || lower.contains("time")) ||
        lower.contains("remind") && (lower.contains("appointment") || lower.contains("meeting") || lower.contains("appt"))
    }

    private static func wantsReferralAsk(_ lower: String) -> Bool {
        lower.contains("referral") || lower.contains("refer ") || lower.contains("know anyone") || lower.contains("introductions")
    }

    private static func wantsTwoTimeOptions(_ lower: String) -> Bool {
        lower.contains("2 times") || lower.contains("two times") || lower.contains("two options") || lower.contains("couple times") || lower.contains("two time")
    }

    private static func wantsPersonalTouch(_ lower: String) -> Bool {
        lower.contains("personal") || lower.contains("rapport") || lower.contains("family") || lower.contains("spouse") || lower.contains("wife") || lower.contains("husband") || lower.contains("kids") || lower.contains("company") || lower.contains("work")
    }

    private static func isStyleOnly(_ ask: String) -> Bool {
        let lower = ask.lowercased()
        let style = [
            "short", "shorter", "brief", "longer", "warm", "warmer", "friendly",
            "direct", "professional", "casual", "nicer", "softer", "question",
            "punchy", "punchier", "concise", "emoji", "emojis", "polite", "kinder", "salesy"
        ]
        guard style.contains(where: { lower.contains($0) }) else { return false }
        let fillers = [
            "make", "it", "a", "bit", "more", "less", "please", "can", "you", "the",
            "text", "message", "and", "to", "this", "that", "sound", "be", "way",
            "little", "much", "with", "without", "no", "add", "an"
        ]
        let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !fillers.contains($0) && !style.contains($0) }
        return words.isEmpty
    }

    private static func instructionBody(from ask: String) -> String? {
        var text = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip trailing "and don't mention..." so it doesn't leak into the body before removal
        for avoidLead in [" and don't mention ", " and do not mention ", " but don't mention ", " without mentioning "] {
            if let range = text.lowercased().range(of: avoidLead) {
                text = String(text[..<range.lowerBound])
            }
        }
        let leadIns = [
            "can you ", "could you ", "please ", "i want you to ", "i need you to ",
            "help me ", "write a text that ", "write a text to ", "write a text ",
            "draft a text that ", "draft a text ", "text them ", "text him ", "text her ",
            "tell them ", "tell him ", "tell her ", "say that ", "say ",
            "ask them if ", "ask him if ", "ask her if ", "ask them ", "ask him ", "ask her ",
            "ask if ", "ask ", "mention that ", "mention ", "include ", "bring up ",
            "make it about ", "make this about ", "it should ", "the text should "
        ]
        var lower = text.lowercased()
        var stripped = true
        while stripped {
            stripped = false
            for lead in leadIns where lower.hasPrefix(lead) {
                text = String(text.dropFirst(lead.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                lower = text.lowercased()
                stripped = true
                break
            }
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        guard text.count >= 3, !isStyleOnly(text) else { return nil }
        return text
    }

    private static func composeFromAdvisorInstruction(
        instruction: String,
        first: String,
        topic: String?,
        timingCue: String?
    ) -> String {
        let converted = replaceThirdPersonPronouns(in: instruction)
        let lowerConverted = converted.lowercased()

        // If the instruction looks like a conditional or question body (e.g. "they are free Thursday", "you have 5 minutes")
        let startsLikeQuestionClause = ["you're free", "you are free", "you have", "thursday works", "friday works", "tomorrow works", "today works", "next week works", "we can", "they can"].contains {
            lowerConverted.hasPrefix($0)
        }

        var message: String
        if startsLikeQuestionClause {
            message = "Hi \(first), wanted to check if \(converted)?"
        } else {
            message = "Hi \(first), \(finishSentence(converted))"
        }

        if let topic, !lowerConverted.contains(topic.lowercased().prefix(16)) {
            if !message.lowercased().contains(topic.lowercased().prefix(16)) {
                message += " Following up on \(topic)."
            }
        }
        return message
    }

    private static func extractExplicitTimeFromPrompt(_ ask: String) -> String? {
        extractTimingCue(from: ask)
    }

    private static func injectTimeOption(into message: String, timePhrase: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().contains("let me know a good time to connect") {
            return trimmed.replacingOccurrences(
                of: "Let me know a good time to connect.",
                with: "Does \(timePhrase) work to connect?",
                options: .caseInsensitive
            )
        }
        return "\(trimmed) Does \(timePhrase) work for you?"
    }

    private static func wantsShorter(_ lower: String) -> Bool {
        lower.contains("shorter") || lower.contains("brief") || lower.contains("too long") || lower.contains("punchy") || lower.contains("punchier") || lower.contains("concise") || (lower.contains("short") && !lower.contains("shortly"))
    }

    private static func wantsLonger(_ lower: String) -> Bool {
        lower.contains("longer") || lower.contains("more detail") || lower.contains("expand")
    }

    private static func wantsWarmer(_ lower: String) -> Bool {
        lower.contains("warm") || lower.contains("friendly") || lower.contains("nicer") || lower.contains("kinder")
    }

    private static func wantsSofter(_ lower: String) -> Bool {
        lower.contains("softer") || lower.contains("less salesy") || lower.contains("no pressure") || lower.contains("low pressure") || lower.contains("gentle")
    }

    private static func wantsCasual(_ lower: String) -> Bool {
        lower.contains("casual") || lower.contains("relaxed") || lower.contains("chill") || lower.contains("less formal")
    }

    private static func wantsDirect(_ lower: String) -> Bool {
        lower.contains("direct") || lower.contains("professional") || lower.contains("straight") || lower.contains("business")
    }

    private static func wantsQuestion(_ lower: String) -> Bool {
        lower.contains("question") || lower.hasPrefix("ask") || lower.contains(" ask ")
    }

    private static func wantsEmoji(_ lower: String) -> Bool {
        (lower.contains("emoji") || lower.contains("smiley")) && !wantsNoEmoji(lower)
    }

    private static func wantsNoEmoji(_ lower: String) -> Bool {
        lower.contains("no emoji") || lower.contains("without emoji") || lower.contains("remove emoji")
    }

    private static func avoidedTopic(from lower: String) -> String? {
        for lead in ["don't mention ", "do not mention ", "dont mention ", "leave out ", "without mentioning ", "remove "] {
            guard let range = lower.range(of: lead) else { continue }
            let rest = lower[range.upperBound...]
            let topic = rest.split(whereSeparator: { ",.!?\n".contains($0) }).first.map(String.init) ?? ""
            var cleaned = topic.trimmingCharacters(in: .whitespacesAndNewlines)
            for article in ["the ", "their ", "his ", "her ", "my ", "our "] where cleaned.hasPrefix(article) {
                cleaned = String(cleaned.dropFirst(article.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
            if cleaned.count >= 3 && cleaned != "emoji" && cleaned != "emojis" { return cleaned }
        }
        return nil
    }

    private static func shorten(_ message: String, first: String, topic: String?) -> String {
        let parts = message.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let firstPart = parts.first {
            // If first part is only "Hi Alex, hope you're doing well", include the meat from part 2
            if firstPart.lowercased().contains("hope you") && parts.count > 1 {
                let concise = "Hi \(first), \( normalizeLeadingCase(parts[1]) )."
                if concise.count <= 140 { return concise }
            }
            var line = firstPart
            if !".!?".contains(line.last ?? " ") { line += "." }
            if line.count <= 145 { return line }
        }
        if let topic {
            return "Hi \(first) — checking in on \( clip(topic, max: 60) ). Free for a quick call?"
        }
        return clip(message, max: 130)
    }

    private static func expandWithContext(
        _ message: String,
        first: String,
        insight: SmsNoteInsight,
        context: SmsContactContext
    ) -> String {
        var result = message
        if !result.lowercased().contains("questions") {
            result += " I'm happy to answer any questions when we connect."
        }
        return result
    }

    private static func warm(_ message: String, first: String, personalCue: String?, company: String) -> String {
        let lower = message.lowercased()
        if lower.contains("hope you") || lower.contains("hope things") { return message }
        let body = droppingGreeting(message, first: first)
        if let personalCue, !lower.contains(personalCue.lowercased()) {
            return "Hi \(first), hope you and \(personalCue) are doing well! \(body)"
        }
        if let comp = nonEmpty(company), !lower.contains(comp.lowercased()) {
            return "Hi \(first), hope things are going well at \(comp)! \(body)"
        }
        return "Hi \(first), hope you're doing well! \(body)"
    }

    private static func casualize(_ message: String, first: String) -> String {
        let body = droppingGreeting(message, first: first)
            .replacingOccurrences(of: "Following up on ", with: "Just circling back on ")
            .replacingOccurrences(of: "Let me know a good time to connect.", with: "Let me know whenever you're free for a quick chat!")
        return "Hey \(first)! \(body)"
    }

    private static func soften(_ message: String) -> String {
        var text = message
        if !text.lowercased().contains("no rush") && !text.lowercased().contains("whenever") {
            text = text.replacingOccurrences(of: "Let me know a good time to connect.", with: "No rush at all — just let me know whenever works best for you.")
            if text == message {
                text += " No rush at all, just whenever works best for you."
            }
        }
        return text
    }

    private static func direct(_ message: String, first: String, topic: String?, timingCue: String?) -> String {
        return "Hi \(first) — \(droppingGreeting(message, first: first))"
    }

    private static func ensureEndsWithQuestion(_ message: String, timingCue: String?) -> String {
        let trimmed = message.trimmingCharacters(in: CharacterSet(charactersIn: ".! "))
        if trimmed.lowercased().hasSuffix("let me know a good time to connect") {
            let base = String(trimmed.dropLast("let me know a good time to connect".count)).trimmingCharacters(in: CharacterSet(charactersIn: ".! "))
            let timeAsk = timingCue.map { "Would \($0) work for a quick call?" } ?? "What time works best for us to connect?"
            return base.isEmpty ? timeAsk : "\(base). \(timeAsk)"
        }
        return trimmed + "?"
    }

    private static func addFriendlyEmoji(to message: String) -> String {
        if message.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) {
            return message
        }
        return message + " 👋"
    }

    private static func stripEmojis(from message: String) -> String {
        let filtered = message.unicodeScalars.filter { !$0.properties.isEmojiPresentation }
        return String(String.UnicodeScalarView(filtered)).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeTopic(_ avoided: String, from message: String, first: String) -> String {
        let clauses = message.components(separatedBy: ". ")
        let filtered = clauses.filter { !$0.localizedCaseInsensitiveContains(avoided) }
        if !filtered.isEmpty && filtered.count < clauses.count {
            var rebuilt = filtered.joined(separator: ". ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !rebuilt.lowercased().hasPrefix("hi ") && !rebuilt.lowercased().hasPrefix("hey ") {
                rebuilt = "Hi \(first), \(normalizeLeadingCase(rebuilt))"
            }
            if !".!?".contains(rebuilt.last ?? " ") { rebuilt += "." }
            return rebuilt
        }
        var cleaned = message.replacingOccurrences(of: avoided, with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: " ,", with: ",")
        cleaned = cleaned.replacingOccurrences(of: " .", with: ".")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func droppingGreeting(_ message: String, first: String) -> String {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let greetings = ["hi \(first),", "hi \(first)!", "hi \(first) —", "hi \(first) -", "hey \(first),", "hey \(first)!"]
        let lower = text.lowercased()
        for greeting in greetings where lower.hasPrefix(greeting.lowercased()) {
            text = String(text.dropFirst(greeting.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        if let firstChar = text.first {
            text.replaceSubrange(text.startIndex...text.startIndex, with: String(firstChar).uppercased())
        }
        return text
    }

    private static func finishSentence(_ text: String) -> String {
        var line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = line.first else { return line }
        line.replaceSubrange(line.startIndex...line.startIndex, with: String(first).uppercased())
        if !".!?".contains(line.last ?? " ") { line += "." }
        return line
    }

    private static func buildTurnExplanation(
        detail: String?,
        insight: SmsNoteInsight,
        context: SmsContactContext,
        ask: String,
        appliedSpecialIntent: String?
    ) -> String {
        if let special = appliedSpecialIntent {
            if let detail {
                return "Tailored this for \(special) and connected it to the note about \(clip(detail, max: 75))."
            }
            return "Tailored this for \(special) based on \(firstName(from: context.name))'s profile."
        }
        if detail == nil {
            if let appt = nonEmpty(context.upcomingAppointment) {
                return "Used what you asked along with the upcoming appointment (\(appt))."
            }
            return "There aren't notes on this contact yet, so I wrote this from your request. Add a note anytime if you want future drafts to pull from it."
        }
        if isStyleOnly(ask) {
            return "Updated the tone and kept it grounded in the note about \(clip(detail ?? "", max: 80))."
        }
        return "Combined your request with the note about \(clip(detail ?? "", max: 80))."
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clip(_ text: String, max: Int) -> String {
        let clean = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > max else { return clean }
        let end = clean.index(clean.startIndex, offsetBy: max)
        let prefix = String(clean[..<end])
        if let space = prefix.lastIndex(of: " ") {
            return String(prefix[..<space]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sanitize(_ message: String) -> String {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count > 2 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if text.count > 320 { text = clip(text, max: 320) }
        return text
    }
}

enum SmsCoachEngine {
    static func reply(
        context: SmsContactContext,
        currentDraft: String,
        history: [SmsChatLine],
        prompt: String,
        preferences: SmsWritingPreferences = SmsWritingPreferences()
    ) async -> SmsCoachTurn {
        let localFallback = SmsNoteCoach.reply(
            context: context,
            currentDraft: currentDraft,
            history: history,
            prompt: prompt
        )
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if SystemLanguageModel.default.isAvailable {
                do {
                    let generated = try await AppleSmsCoach.reply(
                        context: context,
                        currentDraft: currentDraft,
                        history: history,
                        prompt: prompt,
                        preferences: preferences
                    )
                    let raw = SmsNoteCoach.sanitize(generated.message)
                    if !raw.isEmpty {
                        return SmsCoachTurn(
                            explanation: generated.explanation,
                            message: raw,
                            alternatives: []
                        )
                    } else if !generated.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return SmsCoachTurn(explanation: generated.explanation, message: "", alternatives: [])
                    }
                } catch {
                    return localFallback
                }
            }
        }
        #endif
        return localFallback
    }

    static func reply(
        name: String,
        notes: String,
        currentDraft: String,
        history: [SmsChatLine],
        prompt: String
    ) async -> SmsCoachTurn {
        await reply(
            context: SmsContactContext(name: name, notes: notes),
            currentDraft: currentDraft,
            history: history,
            prompt: prompt
        )
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct SmsCoachReply {
    @Guide(description: "The advisor-facing reply. Answer their latest message directly, in as many sentences as the question needs. When they are only chatting or asking a question, this is the whole reply. Do not paste the SMS here.")
    var explanation: String

    @Guide(description: "A ready-to-send SMS only when the advisor asked you to write, rewrite, or edit a text. Leave this empty when they are chatting or asking a question. Plain text, no quotation marks, under 300 characters, first person from the advisor to the contact.")
    var message: String
}

@available(iOS 26.0, *)
enum AppleSmsCoach {
    static func reply(
        context: SmsContactContext,
        currentDraft: String,
        history: [SmsChatLine],
        prompt: String,
        preferences: SmsWritingPreferences
    ) async throws -> SmsCoachTurn {
        let trimmedNotes = context.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let insight = SmsNoteCoach.analyze(context: context)
        let profileFacts = [
            context.category.isEmpty ? nil : "Category: \(context.category)",
            context.company.isEmpty ? nil : "Company: \(context.company)",
            context.jobTitle.isEmpty ? nil : "Role: \(context.jobTitle)",
            insight.stageHighlight.map { "Pipeline stage: \($0)" },
            context.upcomingAppointment.map { "Upcoming appointment: \($0)" },
            context.openReminder.map { "Open reminder: \($0)" },
            insight.timingCue.map { "Preferred timing in notes: \($0)" },
            insight.personalCue.map { "Personal rapport detail: \($0)" }
        ].compactMap { $0 }.joined(separator: "\n")

        let session = LanguageModelSession(instructions: """
        You are an on-device assistant sitting with a financial professional. Talk with them about whatever they ask, and also help them write one SMS to this contact when they want a text.
        Answer the latest message directly in `explanation`. Use the conversation so far. When the question is about this contact, use only facts from the profile, notes, or what the advisor just said — never invent meetings, dollar amounts, family details, appointments, or promises. For other questions, answer normally from general knowledge.
        Put a complete, ready-to-send SMS in `message` when they ask you to write or change the draft, including indirect conversational requests such as "I like it, can you add meeting for coffee?" Treat follow-up requests as edits to the current draft, keeping earlier requested details unless asked to remove them. If they are only chatting, asking for advice, or discussing options without requesting a change, leave `message` empty. Ask a brief clarification in `explanation` when an edit is ambiguous.
        Treat CRM notes and reminders as private background, not wording to copy into an SMS. Write a fresh, natural message. Mention only details useful for the recipient; omit internal observations, sensitive details, timestamps, labels, and log text. Only use exact wording when the advisor explicitly asks to send those words.
        Ignore raw stage-transition logs like "Moved to ... stage" when phrasing a text. Convert third-person notes ("he wants", "her 401k") into natural second-person phrasing ("your 401k").
        Preserve the current draft when asked to edit it; change only what the advisor requested. If the advisor provides a client reply, respond to its meaning using the contact context; do not repeat private notes. Treat examples as style only, never as facts or wording to copy.
        Today's date is \(Date().formatted(date: .long, time: .omitted)). Dates and relative times in old or undated notes are not current scheduling commitments; do not propose them unless the advisor confirms them. Never invent availability.
        Writing preferences: \(preferences.instructions)
        Do not give personalized product, legal, or investment advice. You may explain ideas in general terms. Sound like a real person: clear, warm, and direct.
        Contact name: \(context.name.isEmpty ? "the contact" : context.name)
        \(profileFacts.isEmpty ? "" : "Profile details:\n\(profileFacts)\n")
        Contact notes:
        \(trimmedNotes.isEmpty ? "No notes yet." : trimmedNotes)
        """)
        let prior = history.suffix(16).map { line -> String in
            switch line.role {
            case .user: return "Advisor: \(line.text)"
            case .assistant:
                var row = "Assistant: \(line.text)"
                if let suggested = line.suggestedMessage, !suggested.isEmpty {
                    row += "\nSuggested text: \(suggested)"
                }
                return row
            }
        }.joined(separator: "\n")
        let draft = currentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = try await session.respond(to: """
        Conversation so far:
        \(prior.isEmpty ? "(none)" : prior)

        Current draft:
        \(draft.isEmpty ? "(none yet)" : draft)

        Advisor says:
        \(prompt)
        """, generating: SmsCoachReply.self)
        let explanation = response.content.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = response.content.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return SmsCoachTurn(
            explanation: explanation.isEmpty ? "Here's a text based on the notes and what you asked." : explanation,
            message: message
        )
    }
}
#endif

struct SmsCoachSheet: View {
    let context: SmsContactContext
    let currentDraft: String
    var onUse: (String) -> Void

    init(
        context: SmsContactContext,
        currentDraft: String,
        onUse: @escaping (String) -> Void
    ) {
        self.context = context
        self.currentDraft = currentDraft
        self.onUse = onUse
    }

    init(
        contactName: String,
        notes: String,
        currentDraft: String,
        onUse: @escaping (String) -> Void
    ) {
        self.context = SmsContactContext(name: contactName, notes: notes)
        self.currentDraft = currentDraft
        self.onUse = onUse
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("smsCoachTone") private var preferredTone = "Natural"
    @AppStorage("smsCoachLength") private var preferredLength = "Standard"
    @AppStorage("smsCoachEmoji") private var preferredEmoji = false
    @AppStorage("smsCoachExample") private var preferredExample = ""
    @State private var showingPreferences = false
    @State private var showingReply = false
    @State private var clientReply = ""
    @State private var activeMessage: String?
    @State private var messages: [SmsChatLine] = []
    @State private var draftPrompt = ""
    @State private var isResponding = false
    @State private var appliedMessage: String?
    @State private var copiedMessage: String?
    @FocusState private var promptFocused: Bool

    private var preferences: SmsWritingPreferences {
        SmsWritingPreferences(tone: preferredTone, length: preferredLength, emoji: preferredEmoji, example: preferredExample)
    }
    private var firstName: String { SmsNoteCoach.firstName(from: context.name) }
    private var insight: SmsNoteInsight { SmsNoteCoach.analyze(context: context) }
    private var quickPrompts: [SmsQuickPrompt] { SmsNoteCoach.quickPrompts(for: context) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextHeaderCard
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { line in
                                chatBubble(line)
                                    .id(line.id)
                            }
                            if isResponding {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Thinking…")
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                quickPromptBar
                HStack {
                    Button { showingReply = true } label: { Label("Reply to a message", systemImage: "text.bubble") }
                    Spacer()
                    Button { showingPreferences = true } label: { Label("Writing style", systemImage: "slider.horizontal.3") }
                }
                .font(.caption.weight(.semibold)).foregroundStyle(Color.neonCyan)
                .padding(.horizontal, 18).padding(.vertical, 8)

                composer
            }
            .background { SpaceBackgroundView() }
            .navigationTitle("Ask AI · \(firstName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: seedConversation)
        .sheet(isPresented: $showingPreferences) {
            NavigationStack {
                Form {
                    Picker("Tone", selection: $preferredTone) {
                        ForEach(["Natural", "Casual", "Professional", "Warm"], id: \.self) { Text($0) }
                    }
                    Picker("Length", selection: $preferredLength) {
                        ForEach(["Short", "Standard", "Detailed"], id: \.self) { Text($0) }
                    }
                    Toggle("Use emojis", isOn: $preferredEmoji)
                    Section("Example of your writing (optional)") {
                        TextField("Paste a message you wrote", text: $preferredExample, axis: .vertical).lineLimit(3...6)
                        Text("The on-device AI uses this as a style guide when available. Avoid including private details.").font(.caption).foregroundStyle(Color.textSecondary)
                    }
                }
                .navigationTitle("Writing style")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingPreferences = false } } }
            }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingReply) {
            NavigationStack {
                Form {
                    Section("Client's message") {
                        TextEditor(text: $clientReply).frame(minHeight: 140)
                    }
                    Text("The reply and contact context are used to suggest an editable response.").font(.caption).foregroundStyle(Color.textSecondary)
                }
                .navigationTitle("Reply to a message")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingReply = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Suggest reply") {
                            let reply = clientReply.trimmingCharacters(in: .whitespacesAndNewlines)
                            showingReply = false
                            clientReply = ""
                            sendPrompt("Client reply: \(reply)")
                        }.disabled(clientReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResponding)
                    }
                }
            }.preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var contextHeaderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.caption.bold())
                    .foregroundStyle(Color.neonCyan)
                Text("What AI knows about \(firstName)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.neonCyan)
                Spacer()
                Text(insight.detectedIntent.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.neonGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.neonGreen.opacity(0.14), in: Capsule())
            }

            if insight.contextBadges.isEmpty {
                Text("No notes yet — tell AI what you want to say or add a quick note.")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(insight.contextBadges, id: \.self) { badge in
                            Text(badge)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.glassFrost, in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(12)
        .frostedGlass(cornerRadius: 14, borderColor: Color.neonCyan.opacity(0.35))
    }

    private var quickPromptBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickPrompts) { item in
                    Button {
                        sendPrompt(item.prompt)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item.iconName)
                                .font(.caption2)
                            Text(item.label)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Color.neonCyan)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Color.neonCyan.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Color.neonCyan.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isResponding)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.darkSpaceBlue.opacity(0.85))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask me anything, or how to change the text…", text: $draftPrompt, axis: .vertical)
                .lineLimit(1...4)
                .focused($promptFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frostedGlass(cornerRadius: 16)
            Button {
                sendPrompt(draftPrompt)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.bold())
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Color.neonCyan, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isResponding || draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(Color.darkSpaceBlue.opacity(0.92))
    }

    @ViewBuilder
    private func chatBubble(_ line: SmsChatLine) -> some View {
        VStack(alignment: line.role == .user ? .trailing : .leading, spacing: 8) {
            Text(line.text)
                .font(.subheadline)
                .foregroundStyle(line.role == .user ? Color.black : Color.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    line.role == .user ? Color.neonCyan : Color.glassPanel,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(line.role == .user ? Color.clear : Color.glassFrost, lineWidth: 1)
                )
                .frame(maxWidth: line.role == .user ? 320 : 560, alignment: line.role == .user ? .trailing : .leading)

            if let suggested = line.suggestedMessage, !suggested.isEmpty {
                suggestionCard(suggested, isPrimary: true)
            }

            if !line.alternatives.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Alternate angles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.leading, 4)
                    ForEach(line.alternatives, id: \.self) { alt in
                        suggestionCard(alt, isPrimary: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: line.role == .user ? .trailing : .leading)
    }

    @ViewBuilder
    private func suggestionCard(_ suggested: String, isPrimary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(suggested)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)

            HStack(spacing: 14) {
                Button {
                    onUse(suggested)
                    activeMessage = suggested
                    appliedMessage = suggested
                } label: {
                    Label(
                        appliedMessage == suggested ? "In your draft" : "Use this text",
                        systemImage: appliedMessage == suggested ? "checkmark.circle.fill" : "text.badge.plus"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appliedMessage == suggested ? Color.neonGreen : Color.neonCyan)
                }
                .buttonStyle(.plain)

                Button {
                    copyToClipboard(suggested)
                } label: {
                    Label(
                        copiedMessage == suggested ? "Copied" : "Copy",
                        systemImage: copiedMessage == suggested ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(copiedMessage == suggested ? Color.neonGreen : Color.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(suggested.count) chars")
                    .font(.caption2)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frostedGlass(
            cornerRadius: 14,
            borderColor: isPrimary ? Color.neonCyan.opacity(0.45) : Color.glassFrost
        )
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
        copiedMessage = text
    }

    private func seedConversation() {
        guard messages.isEmpty else { return }
        let currentInsight = insight
        let explanation: String
        if currentInsight.rawBestDetail != nil {
            var extra: [String] = []
            if currentInsight.missedCallOrVoicemail { extra.append("your recent voicemail/call attempt") }
            if let timing = currentInsight.timingCue { extra.append("their timing preference (\(timing))") }
            if let appt = context.upcomingAppointment, !appt.isEmpty { extra.append("your upcoming appointment (\(appt))") }
            let extraText = extra.isEmpty ? "" : " I also factored in \(extra.joined(separator: " and "))."
            explanation = "I used the contact's notes to identify the follow-up topic.\(extraText) Here's one draft. Ask me anything about \(firstName), or tell me how to change the text."
        } else if let appt = context.upcomingAppointment, !appt.isEmpty {
            explanation = "I see an upcoming appointment with \(firstName) (\(appt)). Here's a confirmation text — ask me to adjust the tone or include anything specific."
        } else {
            explanation = "There aren't detailed notes on \(firstName) yet, so I tailored this to their profile. Tell me what you want to mention or tap a chip below."
        }
        let existing = currentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let starter = existing.isEmpty ? SmsNoteCoach.preferredSuggestion(context: context, preferences: preferences) : existing
        activeMessage = starter
        appliedMessage = existing.isEmpty ? nil : existing
        messages = [
            SmsChatLine(
                role: .assistant,
                text: explanation,
                suggestedMessage: starter,
                alternatives: []
            )
        ]
    }

    private func sendPrompt(_ rawPrompt: String) {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }
        if draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines) == prompt {
            draftPrompt = ""
        }
        promptFocused = false
        let history = messages
        messages.append(SmsChatLine(role: .user, text: prompt, suggestedMessage: nil))
        isResponding = true
        let latestSuggested = history.compactMap(\.suggestedMessage).last
        let trimmedDraft = currentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeDraft = activeMessage ?? latestSuggested ?? (trimmedDraft.isEmpty ? SmsNoteCoach.suggest(context: context, style: .smart) : trimmedDraft)
        let activePreferences = preferences
        let activeContext = context
        Task {
            let turn = await SmsCoachEngine.reply(
                context: activeContext,
                currentDraft: activeDraft,
                history: history,
                prompt: prompt,
                preferences: activePreferences
            )
            await MainActor.run {
                let suggested = turn.message.trimmingCharacters(in: .whitespacesAndNewlines)
                if !suggested.isEmpty {
                    activeMessage = suggested
                }
                messages.append(
                    SmsChatLine(
                        role: .assistant,
                        text: turn.explanation,
                        suggestedMessage: suggested.isEmpty ? nil : suggested,
                        alternatives: turn.alternatives
                    )
                )
                isResponding = false
            }
        }
    }
}
