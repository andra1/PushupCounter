# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development

This is an iOS app built with Swift 5.9, targeting iOS 17.0. The Xcode project is generated via **XcodeGen** from `project.yml`.

```bash
# Regenerate Xcode project after modifying project.yml
xcodegen generate

# Build
xcodebuild -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'

# Run all tests
xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'
```

No external dependencies — all frameworks are Apple system frameworks.

## Architecture

**SwiftUI + SwiftData + Service layer**, organized as:

- **Models/** — SwiftData `@Model` classes: `DailyRecord`, `PushupSession`. DailyRecord has a cascade-delete relationship to PushupSession.
- **Services/** — Core business logic as `@Observable` classes:
  - `CameraManager` — AVFoundation camera capture + Vision body pose detection
  - `PushupDetector` — State machine (UP/DOWN/UNKNOWN) counting pushups via elbow angle thresholds (<90° = down, >160° = up) with 3-frame debounce
- **Utilities/** — `AngleCalculator` for computing elbow angle from pose keypoints
- **Views/** — SwiftUI views organized by feature (Today, Session, History)

**Data flow:** Camera Frame → Vision Pose Detection → Angle Extraction → PushupDetector state machine → SwiftData persistence → UI updates

## Testing

Tests are in `PushupCounterTests/` using XCTest. Core logic has good coverage:
- `PushupDetectorTests` — State machine transitions, debounce, counting
- `AngleCalculatorTests` — Angle computation and edge cases
- `DailyRecordTests` — Model relationships

## Key Patterns

- `@Observable` for service classes, `@MainActor` on PushupDetector
- Camera processing on background `DispatchQueue`, UI updates dispatched to main
- `[weak self]` in closures for memory safety
- Guard clauses for early returns, try-catch for Vision/persistence operations
- SwiftData `@Query` for reactive data fetching in views
