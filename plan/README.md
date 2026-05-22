# Plan

Plan is a minimal macOS planning and reminder app built with SwiftUI, SwiftData, WidgetKit, App Intents, and local notifications.

The app focuses on low-friction planning for short-term execution:

- Today-first task list with priority levels.
- S/A/B/C priority colors.
- Local reminders and snooze actions.
- Lightweight focus sessions.
- Recent focus history and upcoming plans.
- Image attachments for task records.
- macOS desktop widgets with shared App Group snapshots.

## Build

Open `PlanApp.xcodeproj` in Xcode, or build from the command line:

```sh
xcodebuild -project PlanApp.xcodeproj -scheme Plan -destination 'platform=macOS' build
```

Run tests:

```sh
xcodebuild -project PlanApp.xcodeproj -scheme PlanTests -destination 'platform=macOS' test
```
