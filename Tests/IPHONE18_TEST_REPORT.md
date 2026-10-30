# iPhone 18 Pro verification — October 29, 2026

Device: iPhone 18 Pro simulator, iOS 27.0. Debug app built with the iOS Simulator 27.1 SDK and local signing enabled.

## Passed

- Installed and launched the app; checked sign-in and account form rendering and empty sign-in validation.
- Diagnosed Firebase Auth keychain error `-34018` in the compile-only installation. Rebuilt with simulator code signing enabled; sign-in and contact loading then succeeded.
- Confirmed the signed app retained sign-in and loaded contacts after reinstall/relaunch.
- Ran all 54 domain compatibility checks as an iOS Simulator executable inside this device. See `run-step2-checks.sh --simulator <booted-device-UDID>`.
- Created the dedicated `Step 2 Simulator Test 2026-10-29` contact.
- Saved Connected with a Client / In-Force stage change, note, and next action due tomorrow at 9 AM. Verified Client was appended to the category, the stage and contact dates updated, the reminder appeared, and the timeline displayed the activity once.
- Checked reminder title validation, then created an earlier reminder due today at 5 PM. The parent follow-up moved to the earlier pending reminder.
- Rescheduled the earlier reminder to tomorrow. The parent date updated and both reminders remained open.
- Completed one reminder. A single Reminder completed activity appeared above the earlier outcome, the other reminder remained open, and contact-attempt/connection dates were preserved.
- Cancelled the remaining reminder. Open reminders became empty and the parent follow-up cleared.
- Saved Pause with a reason. Paused state persisted.
- Saved No answer with a new reminder. The contact resumed and appeared in Today in Follow-ups.
- Opened Log Outcome directly from the feed row and saved Close with a test-completion reason. The contact disappeared from Today.
- Replaced the adaptive action row with a two-row layout after detecting wrapped labels and an iOS 27 button-sizing issue. Removed a duplicate navigation arrow. Rebuilt, reinstalled, and visually verified legible action labels and a single arrow on Home and Follow-ups.

## Test data and limits

The test contact is retained as closed, with a test-completion reason, and no pending reminders. Existing contacts were not edited. Calls and texts were not sent.

These manual checks cover ordinary live Firebase saves and listener updates. They do not exercise a forced network failure, transaction contention between Android and iOS, every Firestore ownership-rule branch, local notification delivery, or physical-device behavior.
