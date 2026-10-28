# RCRM for iOS

A native iPhone companion to the RCRM Android app. This repository is the starting point for the iOS project; it does not yet contain an Xcode project or application code.

## Get started on a Mac

1. Install Xcode and sign in to GitHub.
2. Clone this repository: `git clone https://github.com/extmnick-commits/RCRM-iOS.git`
3. In Xcode, create a new iOS App named RCRM using Swift and SwiftUI. Save it inside the cloned repository. Choose the bundle identifier and signing team when setting up the project.
4. Run the starter app in the iPhone simulator, then commit the Xcode project and source files.
5. Register a separate iOS app in a Firebase development project and add its configuration and the Firebase SDK using Swift Package Manager. Test authentication and lead access in the development environment before connecting to production.

## First development milestone

Build a basic sign-in screen and a read-only list of leads. Match the Android app's data model and access rules, and test both platforms against the same development data. Never commit passwords, private keys, or API secrets.

## Platform considerations

The Android app is the reference for RCRM workflows and design. iOS contacts, calendar, notifications, phone calls, messaging, and on-device AI use different APIs and require separate implementation and testing. In particular, automatic post-call Smart Log and contact-note synchronization need an early iOS feasibility check.
