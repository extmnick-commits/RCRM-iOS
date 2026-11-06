# RCRM for iOS

A native SwiftUI companion to RCRM for Android. The app provides email/password sign-in, contact management, follow-up feeds, transactional outcome logging, open reminders, and a merged activity timeline using Android's Firestore schema.

## Setup

1. Open `RCRM.xcodeproj` in Xcode. The project uses bundle identifier `com.nickpulido.rcrm` and iOS 26 or later.
2. Set up a separate Firebase development project with Email/Password authentication, Firestore, and test users and data. Register an Apple app using the bundle identifier above. Download its `GoogleService-Info.plist`.
3. Drag that file into the `RCRM` group in Xcode, select **Copy items if needed**, and check the **RCRM** target. The configuration file is excluded from Git. The setup screen appears until a configuration is included in the app bundle.
4. Allow Xcode to resolve Firebase packages. Select a simulator and run. For a physical device, choose your signing team in Signing & Capabilities.
5. Sign in with a development user and verify that only that user's leads appear. The app queries `leads` where `ownerId` equals the authenticated user's UID, matching Android. Firestore security rules must independently enforce access.

The Firebase app previously registered in the existing production project is not a separate development environment. Avoid testing with production customer data until the cross-platform behavior and security rules are verified.

## Scope

Home and Follow-ups share the Android feed rules: Needs Attention includes overdue contacts and contacts without a follow-up; Today includes due and overdue contacts; Upcoming includes future dates. Paused and closed contacts stay out of these feeds.

Log Outcome is available on feed rows and contact details. It atomically writes an idempotent activity, resolves the selected or earliest pending action, optionally schedules a next action, updates pipeline/lifecycle/contact dates, and prepends an event-tagged note. The same operation ID is retained when a save fails and is retried. Reminder controls create, complete, reschedule, and cancel individual actions while updating the parent follow-up date. Completing a reminder creates Android's deterministic reminder-completion activity without recording a contact attempt. Rescheduling preserves appointment links and other reminder metadata.

Contact details listen to `next_actions` and `activity_records`, merging records with legacy notes and removing duplicate event IDs. Child dates and contact-attempt dates are epoch-millisecond integers; parent `followUpDate` is a Firestore timestamp, removed when no pending date remains or the workflow is paused/closed. Writes preserve unrelated Android fields and include authenticated ownership metadata.

Appointments can sync with the calendars on this iPhone, including a Google account added in Settings. New and rescheduled appointments are written there with the same `rcrm://lead/` and `rcrm://appointment/` links Android uses, and calendar events show on the Appointments tab. Local notification delivery alerts for open reminders and appointments, schedules a configurable Daily Briefing digest, and deep-links notification taps directly to the contact.

Device contact synchronization and rapid lead entry are supported via Apple Contacts (`Contacts` / `ContactsUI`) and Quick Smart Log. Contacts can be imported with phone numbers, emails, addresses, and company details directly into RCRM leads, with normalized phone matching to avoid duplicates. Quick Smart Log provides fast follow-up scheduling shortcuts (7 PM Today, 7 PM Tomorrow, +1 Week, +2 Weeks, +1 Month, Custom), action type selection, outcome note capture, and automated Intro SMS drafting with one-tap handoff to Messages. CallKit live call observing and AI are outside this step.

## Verification

Run `bash Tests/run-step2-checks.sh` from this folder. It executes the app's actual Foundation-only domain code against Android compatibility fixtures for outcomes, lifecycle changes, next-action serialization, note/timeline merging, and due-date shortcuts, without Firebase credentials or a simulator. Build the RCRM scheme for iOS Simulator in Xcode to verify the full app.

To run the same checks inside a booted simulator, use `bash Tests/run-step2-checks.sh --simulator <device-UDID>` (find its ID with `xcrun simctl list devices booted`).

When installing a simulator build, leave code signing enabled. For command-line builds use `CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES`; `CODE_SIGNING_ALLOWED=NO` omits the simulator app identity and causes Firebase Auth keychain error `-34018`. A compile-only build does not validate sign-in.

These checks do not connect to Firebase. Use a development account to verify transaction retries, concurrent Android/iOS changes, ownership rules, and live listener updates before testing with customer data.
