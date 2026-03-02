# PushupCounter Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an iOS app that counts pushups via on-device pose detection and gates social media apps behind a daily pushup goal using Apple's Screen Time API.

**Architecture:** SwiftUI + SwiftData single-app with two app extensions (ShieldConfigurationExtension, DeviceActivityMonitorExtension). Core pushup detection uses Apple Vision framework body pose estimation processed through a testable state machine. App blocking uses FamilyControls/ManagedSettings/DeviceActivity. Targets iOS 17.0+ (SwiftData and @Observable require iOS 17; Screen Time API available since iOS 16).

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftData, AVFoundation, Vision, FamilyControls, ManagedSettings, ManagedSettingsUI, DeviceActivity, XcodeGen

---

## Prerequisites

Before starting implementation:

1. **Apple Developer Program membership** ($99/year) — required for FamilyControls entitlement
2. **Install XcodeGen** — `brew install xcodegen`
3. **Xcode 15+** installed with iOS 17+ SDK
4. **Physical iOS device** for testing (Screen Time APIs and camera don't work in Simulator)
5. **Enable Developer Mode** on the test device (Settings → Privacy & Security → Developer Mode)
6. **Apple Developer Portal setup:**
   - Register an App ID: `com.pushupcounter.app`
   - Enable capabilities: Family Controls, App Groups (`group.com.pushupcounter.shared`)
   - Create development provisioning profile with these capabilities

> **Note on FamilyControls entitlement:** During development, the entitlement works automatically on your personal device. For App Store distribution, you must request Apple's approval for the production entitlement.

---

## Task 1: Project Scaffolding

**Files:**
- Create: `project.yml`
- Create: `PushupCounter/PushupCounterApp.swift`
- Create: `PushupCounter/PushupCounter.entitlements`
- Create: `ShieldConfigurationExtension/ShieldConfigurationExtension.swift`
- Create: `ShieldConfigurationExtension/ShieldConfigurationExtension.entitlements`
- Create: `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift`
- Create: `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.entitlements`
- Create: `PushupCounterTests/PushupCounterTests.swift`

### Step 1: Create directory structure

```bash
mkdir -p PushupCounter/{Models,Services,Views/{Onboarding,Today,Session,History,Settings},Utilities}
mkdir -p PushupCounterTests
mkdir -p ShieldConfigurationExtension
mkdir -p DeviceActivityMonitorExtension
```

### Step 2: Create project.yml for XcodeGen

```yaml
# project.yml
name: PushupCounter
options:
  bundleIdPrefix: com.pushupcounter
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "15.0"
  generateEmptyDirectories: true
settings:
  base:
    SWIFT_VERSION: "5.9"
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: "" # TODO: Fill in your Apple Developer Team ID
targets:
  PushupCounter:
    type: application
    platform: iOS
    sources:
      - PushupCounter
    entitlements:
      path: PushupCounter/PushupCounter.entitlements
    info:
      properties:
        CFBundleDisplayName: PushupCounter
        NSCameraUsageDescription: "PushupCounter needs camera access to detect and count your pushups in real-time."
        UILaunchScreen: {}
        UIRequiredDeviceCapabilities:
          - armv7
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "1"
        PRODUCT_BUNDLE_IDENTIFIER: com.pushupcounter.app
    dependencies:
      - target: ShieldConfigurationExtension
      - target: DeviceActivityMonitorExtension

  ShieldConfigurationExtension:
    type: app-extension
    platform: iOS
    sources:
      - ShieldConfigurationExtension
    entitlements:
      path: ShieldConfigurationExtension/ShieldConfigurationExtension.entitlements
    info:
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.ManagedSettingsUI.shield-configuration
          NSExtensionPrincipalClass: "$(PRODUCT_MODULE_NAME).ShieldConfigurationExtension"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.pushupcounter.app.shield-config
        GENERATE_INFOPLIST_FILE: YES

  DeviceActivityMonitorExtension:
    type: app-extension
    platform: iOS
    sources:
      - DeviceActivityMonitorExtension
    entitlements:
      path: DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.entitlements
    info:
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.deviceactivity.monitor
          NSExtensionPrincipalClass: "$(PRODUCT_MODULE_NAME).DeviceActivityMonitorExtension"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.pushupcounter.app.activity-monitor
        GENERATE_INFOPLIST_FILE: YES

  PushupCounterTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - PushupCounterTests
    dependencies:
      - target: PushupCounter

schemes:
  PushupCounter:
    build:
      targets:
        PushupCounter: all
        ShieldConfigurationExtension: all
        DeviceActivityMonitorExtension: all
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - PushupCounterTests
```

### Step 3: Create entitlements files

**PushupCounter/PushupCounter.entitlements:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.family-controls</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.pushupcounter.shared</string>
    </array>
</dict>
</plist>
```

**ShieldConfigurationExtension/ShieldConfigurationExtension.entitlements:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.family-controls</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.pushupcounter.shared</string>
    </array>
</dict>
</plist>
```

**DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.entitlements:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.family-controls</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.pushupcounter.shared</string>
    </array>
</dict>
</plist>
```

### Step 4: Create placeholder Swift files

**PushupCounter/PushupCounterApp.swift:**
```swift
import SwiftUI
import SwiftData

@main
struct PushupCounterApp: App {
    var body: some Scene {
        WindowGroup {
            Text("PushupCounter")
        }
    }
}
```

**ShieldConfigurationExtension/ShieldConfigurationExtension.swift:**
```swift
import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        ShieldConfiguration()
    }
}
```

**DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift:**
```swift
import DeviceActivity

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
    }
}
```

**PushupCounterTests/PushupCounterTests.swift:**
```swift
import XCTest
@testable import PushupCounter

final class PushupCounterTests: XCTestCase {
    func testProjectBuilds() {
        XCTAssertTrue(true)
    }
}
```

### Step 5: Generate Xcode project and verify build

```bash
cd /path/to/PushupCounter
xcodegen generate
```

Expected: `⚙  Generating plists...` → `Created project PushupCounter.xcodeproj`

### Step 6: Build and run tests

```bash
xcodebuild test \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:PushupCounterTests \
  | tail -5
```

Expected: `** TEST SUCCEEDED **`

### Step 7: Commit

```bash
git add -A
git commit -m "feat: scaffold Xcode project with XcodeGen, extensions, and test target"
```

---

## Task 2: SwiftData Models

**Files:**
- Create: `PushupCounter/Models/UserSettings.swift`
- Create: `PushupCounter/Models/DailyRecord.swift`
- Create: `PushupCounter/Models/PushupSession.swift`
- Test: `PushupCounterTests/DailyRecordTests.swift`

### Step 1: Write the failing test for DailyRecord

**PushupCounterTests/DailyRecordTests.swift:**
```swift
import XCTest
import SwiftData
@testable import PushupCounter

final class DailyRecordTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: UserSettings.self, DailyRecord.self, PushupSession.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    func testDailyRecordTotalPushups_noSessions_returnsZero() {
        let record = DailyRecord(date: Date())
        context.insert(record)
        XCTAssertEqual(record.totalPushups, 0)
    }

    func testDailyRecordTotalPushups_multipleSessions_returnsSumOfCounts() {
        let record = DailyRecord(date: Date())
        context.insert(record)

        let session1 = PushupSession(startTime: Date(), endTime: Date(), count: 15)
        session1.dailyRecord = record
        record.sessions.append(session1)

        let session2 = PushupSession(startTime: Date(), endTime: Date(), count: 20)
        session2.dailyRecord = record
        record.sessions.append(session2)

        context.insert(session1)
        context.insert(session2)

        XCTAssertEqual(record.totalPushups, 35)
    }

    func testUserSettingsDefaults() {
        let settings = UserSettings()
        context.insert(settings)
        XCTAssertEqual(settings.dailyGoal, 30)
        XCTAssertTrue(settings.soundEnabled)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }
}
```

### Step 2: Run test to verify it fails

```bash
xcodebuild test \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:PushupCounterTests/DailyRecordTests \
  2>&1 | tail -10
```

Expected: FAIL — `UserSettings`, `DailyRecord`, `PushupSession` not defined.

### Step 3: Implement SwiftData models

**PushupCounter/Models/UserSettings.swift:**
```swift
import Foundation
import SwiftData

@Model
final class UserSettings {
    var dailyGoal: Int = 30
    var selectedAppsData: Data?
    var soundEnabled: Bool = true
    var hasCompletedOnboarding: Bool = false

    init(dailyGoal: Int = 30, soundEnabled: Bool = true) {
        self.dailyGoal = dailyGoal
        self.soundEnabled = soundEnabled
    }
}
```

**PushupCounter/Models/DailyRecord.swift:**
```swift
import Foundation
import SwiftData

@Model
final class DailyRecord {
    var date: Date
    var goalMet: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \PushupSession.dailyRecord)
    var sessions: [PushupSession] = []

    var totalPushups: Int {
        sessions.reduce(0) { $0 + $1.count }
    }

    init(date: Date, goalMet: Bool = false) {
        self.date = date
    }
}
```

**PushupCounter/Models/PushupSession.swift:**
```swift
import Foundation
import SwiftData

@Model
final class PushupSession {
    var startTime: Date
    var endTime: Date
    var count: Int
    var dailyRecord: DailyRecord?

    init(startTime: Date, endTime: Date, count: Int) {
        self.startTime = startTime
        self.endTime = endTime
        self.count = count
    }
}
```

### Step 4: Run test to verify it passes

```bash
xcodebuild test \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:PushupCounterTests/DailyRecordTests \
  2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

### Step 5: Commit

```bash
git add PushupCounter/Models/ PushupCounterTests/DailyRecordTests.swift
git commit -m "feat: add SwiftData models for UserSettings, DailyRecord, PushupSession"
```

---

## Task 3: AngleCalculator (TDD)

**Files:**
- Create: `PushupCounter/Utilities/AngleCalculator.swift`
- Test: `PushupCounterTests/AngleCalculatorTests.swift`

### Step 1: Write the failing tests

**PushupCounterTests/AngleCalculatorTests.swift:**
```swift
import XCTest
@testable import PushupCounter

final class AngleCalculatorTests: XCTestCase {

    func testStraightLine_returns180Degrees() {
        // Points in a straight line: A--B--C
        let angle = AngleCalculator.angle(
            a: CGPoint(x: 0, y: 0),
            b: CGPoint(x: 1, y: 0),
            c: CGPoint(x: 2, y: 0)
        )
        XCTAssertEqual(angle, 180.0, accuracy: 0.1)
    }

    func testRightAngle_returns90Degrees() {
        // A is above B, C is to the right of B
        let angle = AngleCalculator.angle(
            a: CGPoint(x: 0, y: 1),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 1, y: 0)
        )
        XCTAssertEqual(angle, 90.0, accuracy: 0.1)
    }

    func test45Degrees() {
        // BA = (1,1), BC = (1,0) → cos = 1/√2 → 45°
        let angle = AngleCalculator.angle(
            a: CGPoint(x: 1, y: 1),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 1, y: 0)
        )
        XCTAssertEqual(angle, 45.0, accuracy: 0.1)
    }

    func test120Degrees() {
        // BA = (1,0), BC = (-1, √3) → cos = -0.5 → 120°
        let angle = AngleCalculator.angle(
            a: CGPoint(x: 1, y: 0),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: -1, y: sqrt(3.0))
        )
        XCTAssertEqual(angle, 120.0, accuracy: 0.1)
    }

    func testZeroDegrees_sameDirection() {
        // A and C are in the same direction from B
        let angle = AngleCalculator.angle(
            a: CGPoint(x: 2, y: 0),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 1, y: 0)
        )
        XCTAssertEqual(angle, 0.0, accuracy: 0.1)
    }

    func testDegenerateInput_zeroLengthVector_returnsZero() {
        // A and B are the same point → zero-length vector
        let angle = AngleCalculator.angle(
            a: CGPoint(x: 0, y: 0),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 1, y: 0)
        )
        XCTAssertEqual(angle, 0.0, accuracy: 0.1)
    }
}
```

### Step 2: Run test to verify it fails

```bash
xcodebuild test \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:PushupCounterTests/AngleCalculatorTests \
  2>&1 | tail -5
```

Expected: FAIL — `AngleCalculator` not defined.

### Step 3: Implement AngleCalculator

**PushupCounter/Utilities/AngleCalculator.swift:**
```swift
import Foundation

enum AngleCalculator {
    /// Computes the angle at point `b` formed by the triangle a-b-c, in degrees.
    /// Returns 0 if any vector has zero length.
    static func angle(a: CGPoint, b: CGPoint, c: CGPoint) -> Double {
        let ba = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let bc = CGVector(dx: c.x - b.x, dy: c.y - b.y)

        let dot = ba.dx * bc.dx + ba.dy * bc.dy
        let magBA = sqrt(ba.dx * ba.dx + ba.dy * ba.dy)
        let magBC = sqrt(bc.dx * bc.dx + bc.dy * bc.dy)

        guard magBA > 0, magBC > 0 else { return 0 }

        let cosAngle = max(-1, min(1, dot / (magBA * magBC)))
        return acos(cosAngle) * 180.0 / .pi
    }
}
```

### Step 4: Run test to verify it passes

```bash
xcodebuild test \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:PushupCounterTests/AngleCalculatorTests \
  2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

### Step 5: Commit

```bash
git add PushupCounter/Utilities/AngleCalculator.swift PushupCounterTests/AngleCalculatorTests.swift
git commit -m "feat: add AngleCalculator with TDD tests"
```

---

## Task 4: PushupDetector State Machine (TDD)

**Files:**
- Create: `PushupCounter/Services/PushupDetector.swift`
- Test: `PushupCounterTests/PushupDetectorTests.swift`

### Step 1: Write the failing tests

**PushupCounterTests/PushupDetectorTests.swift:**
```swift
import XCTest
@testable import PushupCounter

final class PushupDetectorTests: XCTestCase {

    private var detector: PushupDetector!

    override func setUp() {
        detector = PushupDetector()
    }

    // MARK: - Initial State

    func testInitialState_countIsZero() {
        XCTAssertEqual(detector.count, 0)
    }

    func testInitialState_phaseIsUnknown() {
        XCTAssertEqual(detector.phase, .unknown)
    }

    func testInitialState_bodyNotDetected() {
        XCTAssertFalse(detector.bodyDetected)
    }

    // MARK: - Body Detection

    func testNilAngle_bodyNotDetected() {
        detector.processAngle(nil)
        XCTAssertFalse(detector.bodyDetected)
    }

    func testValidAngle_bodyDetected() {
        feedAngle(170, frames: 1)
        XCTAssertTrue(detector.bodyDetected)
    }

    // MARK: - Phase Transitions (with debounce = 3 frames)

    func testHighAngle_transitionsToUp() {
        feedAngle(170, frames: 3)
        XCTAssertEqual(detector.phase, .up)
    }

    func testLowAngle_transitionsToDown() {
        feedAngle(80, frames: 3)
        XCTAssertEqual(detector.phase, .down)
    }

    func testMidAngle_noTransition() {
        feedAngle(120, frames: 10)
        XCTAssertEqual(detector.phase, .unknown)
    }

    // MARK: - Debounce

    func testSingleFrame_noTransition() {
        feedAngle(170, frames: 1)
        XCTAssertEqual(detector.phase, .unknown)
    }

    func testTwoFrames_noTransition() {
        feedAngle(170, frames: 2)
        XCTAssertEqual(detector.phase, .unknown)
    }

    func testThreeFrames_transitionsToUp() {
        feedAngle(170, frames: 3)
        XCTAssertEqual(detector.phase, .up)
    }

    // MARK: - Counting

    func testDownToUp_incrementsCount() {
        // Get to DOWN state
        feedAngle(80, frames: 3)
        XCTAssertEqual(detector.phase, .down)

        // Transition to UP → count should increment
        feedAngle(170, frames: 3)
        XCTAssertEqual(detector.phase, .up)
        XCTAssertEqual(detector.count, 1)
    }

    func testUpToDown_doesNotIncrementCount() {
        // Get to UP state
        feedAngle(170, frames: 3)
        XCTAssertEqual(detector.phase, .up)

        // Transition to DOWN → count should NOT increment
        feedAngle(80, frames: 3)
        XCTAssertEqual(detector.phase, .down)
        XCTAssertEqual(detector.count, 0)
    }

    func testFullPushupCycle_countsOne() {
        // UP → DOWN → UP = 1 pushup
        feedAngle(170, frames: 3)  // UP
        feedAngle(80, frames: 3)   // DOWN
        feedAngle(170, frames: 3)  // UP → count = 1
        XCTAssertEqual(detector.count, 1)
    }

    func testTwoPushups() {
        feedAngle(170, frames: 3)  // UP
        feedAngle(80, frames: 3)   // DOWN
        feedAngle(170, frames: 3)  // UP → count = 1
        feedAngle(80, frames: 3)   // DOWN
        feedAngle(170, frames: 3)  // UP → count = 2
        XCTAssertEqual(detector.count, 2)
    }

    func testMidAngleBetweenPhases_doesNotCount() {
        feedAngle(170, frames: 3)  // UP
        feedAngle(80, frames: 3)   // DOWN
        feedAngle(120, frames: 5)  // mid-range, no transition
        feedAngle(170, frames: 3)  // UP → count = 1
        XCTAssertEqual(detector.count, 1)
    }

    // MARK: - Reset

    func testReset_clearsEverything() {
        feedAngle(170, frames: 3)
        feedAngle(80, frames: 3)
        feedAngle(170, frames: 3)
        XCTAssertEqual(detector.count, 1)

        detector.reset()
        XCTAssertEqual(detector.count, 0)
        XCTAssertEqual(detector.phase, .unknown)
        XCTAssertFalse(detector.bodyDetected)
    }

    // MARK: - Helpers

    private func feedAngle(_ angle: Double, frames: Int) {
        for _ in 0..<frames {
            detector.processAngle(angle)
        }
    }
}
```

### Step 2: Run test to verify it fails

```bash
xcodebuild test \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:PushupCounterTests/PushupDetectorTests \
  2>&1 | tail -5
```

Expected: FAIL — `PushupDetector` not defined.

### Step 3: Implement PushupDetector

**PushupCounter/Services/PushupDetector.swift:**
```swift
import Observation

enum PushupPhase: Equatable {
    case up
    case down
    case unknown
}

@Observable
final class PushupDetector {
    private(set) var count: Int = 0
    private(set) var phase: PushupPhase = .unknown
    private(set) var bodyDetected: Bool = false

    private var pendingPhase: PushupPhase = .unknown
    private var consecutiveFrames: Int = 0

    private let debounceThreshold = 3
    private let downAngleThreshold: Double = 90
    private let upAngleThreshold: Double = 160

    func processAngle(_ angle: Double?) {
        guard let angle else {
            bodyDetected = false
            return
        }
        bodyDetected = true

        let detected: PushupPhase
        if angle < downAngleThreshold {
            detected = .down
        } else if angle > upAngleThreshold {
            detected = .up
        } else {
            return
        }

        if detected == pendingPhase {
            consecutiveFrames += 1
        } else {
            pendingPhase = detected
            consecutiveFrames = 1
        }

        if consecutiveFrames >= debounceThreshold && detected != phase {
            let previous = phase
            phase = detected
            if previous == .down && detected == .up {
                count += 1
            }
        }
    }

    func reset() {
        count = 0
        phase = .unknown
        bodyDetected = false
        pendingPhase = .unknown
        consecutiveFrames = 0
    }
}
```

### Step 4: Run test to verify it passes

```bash
xcodebuild test \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:PushupCounterTests/PushupDetectorTests \
  2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

### Step 5: Commit

```bash
git add PushupCounter/Services/PushupDetector.swift PushupCounterTests/PushupDetectorTests.swift
git commit -m "feat: add PushupDetector state machine with TDD tests"
```

---

## Task 5: Screen Time Manager

**Files:**
- Create: `PushupCounter/Services/ScreenTimeManager.swift`

### Step 1: Implement ScreenTimeManager

**PushupCounter/Services/ScreenTimeManager.swift:**
```swift
import FamilyControls
import ManagedSettings
import DeviceActivity
import Observation

extension DeviceActivityName {
    static let daily = Self("com.pushupcounter.daily")
}

@Observable
final class ScreenTimeManager {
    private(set) var isAuthorized = false
    var selection = FamilyActivitySelection()

    private let store = ManagedSettingsStore()
    private let center = DeviceActivityCenter()

    static let sharedDefaults = UserDefaults(suiteName: "group.com.pushupcounter.shared")

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
    }

    func saveSelection() {
        let data = try? PropertyListEncoder().encode(selection)
        Self.sharedDefaults?.set(data, forKey: "selectedApps")
        applyShields()
        scheduleDailyMonitoring()
    }

    func loadSelection() {
        guard let data = Self.sharedDefaults?.data(forKey: "selectedApps"),
              let saved = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return
        }
        selection = saved
    }

    func applyShields() {
        let tokens = selection.applicationTokens
        store.shield.applications = tokens.isEmpty ? nil : tokens
    }

    func removeShields() {
        store.shield.applications = nil
    }

    func scheduleDailyMonitoring() {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        do {
            try center.startMonitoring(.daily, during: schedule)
        } catch {
            print("Failed to start monitoring: \(error)")
        }
    }

    var hasSelectedApps: Bool {
        !selection.applicationTokens.isEmpty
    }
}
```

### Step 2: Build to verify compilation

```bash
xcodebuild build \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

> **Note:** ScreenTimeManager cannot be unit tested in the simulator because FamilyControls requires a real device with the entitlement. Manual testing on device is required.

### Step 3: Commit

```bash
git add PushupCounter/Services/ScreenTimeManager.swift
git commit -m "feat: add ScreenTimeManager for FamilyControls auth and app shielding"
```

---

## Task 6: Camera + Pose Detection

**Files:**
- Create: `PushupCounter/Services/CameraManager.swift`
- Create: `PushupCounter/Views/Session/CameraPreviewView.swift`

### Step 1: Implement CameraManager

**PushupCounter/Services/CameraManager.swift:**
```swift
import AVFoundation
import Vision
import Observation

@Observable
final class CameraManager: NSObject {
    let session = AVCaptureSession()
    private(set) var cameraPermissionGranted = false
    private(set) var bodyDetected = false

    private let pushupDetector: PushupDetector
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.pushupcounter.video", qos: .userInitiated)

    init(pushupDetector: PushupDetector) {
        self.pushupDetector = pushupDetector
        super.init()
    }

    func requestPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            cameraPermissionGranted = granted
        }
    }

    func setupSession() {
        guard cameraPermissionGranted else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        session.commitConfiguration()
    }

    func startSession() {
        guard !session.isRunning else { return }
        processingQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stopSession() {
        guard session.isRunning else { return }
        processingQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }
}

// MARK: - Video Frame Processing

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard let observation = request.results?.first else {
            DispatchQueue.main.async { [weak self] in
                self?.pushupDetector.processAngle(nil)
                self?.bodyDetected = false
            }
            return
        }

        let angle = extractElbowAngle(from: observation)

        DispatchQueue.main.async { [weak self] in
            self?.pushupDetector.processAngle(angle)
            self?.bodyDetected = angle != nil
        }
    }

    private func extractElbowAngle(from observation: VNHumanBodyPoseObservation) -> Double? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }

        let rightAngle = computeArmAngle(
            shoulder: points[.rightShoulder],
            elbow: points[.rightElbow],
            wrist: points[.rightWrist]
        )

        let leftAngle = computeArmAngle(
            shoulder: points[.leftShoulder],
            elbow: points[.leftElbow],
            wrist: points[.leftWrist]
        )

        switch (rightAngle, leftAngle) {
        case let (r?, l?):
            return (r + l) / 2.0
        case let (r?, nil):
            return r
        case let (nil, l?):
            return l
        case (nil, nil):
            return nil
        }
    }

    private func computeArmAngle(
        shoulder: VNRecognizedPoint?,
        elbow: VNRecognizedPoint?,
        wrist: VNRecognizedPoint?
    ) -> Double? {
        guard let shoulder, shoulder.confidence > 0.6,
              let elbow, elbow.confidence > 0.6,
              let wrist, wrist.confidence > 0.6 else {
            return nil
        }
        return AngleCalculator.angle(
            a: CGPoint(x: shoulder.location.x, y: shoulder.location.y),
            b: CGPoint(x: elbow.location.x, y: elbow.location.y),
            c: CGPoint(x: wrist.location.x, y: wrist.location.y)
        )
    }
}
```

### Step 2: Implement CameraPreviewView (UIViewRepresentable)

**PushupCounter/Views/Session/CameraPreviewView.swift:**
```swift
import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer = previewLayer
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

final class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}
```

### Step 3: Build to verify compilation

```bash
xcodebuild build \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

> **Note:** Camera + Vision requires a physical device to test. Verification is build-only at this stage.

### Step 4: Commit

```bash
git add PushupCounter/Services/CameraManager.swift PushupCounter/Views/Session/CameraPreviewView.swift
git commit -m "feat: add CameraManager with Vision pose detection and camera preview"
```

---

## Task 7: App Entry Point + Navigation

**Files:**
- Modify: `PushupCounter/PushupCounterApp.swift`
- Create: `PushupCounter/ContentView.swift`

### Step 1: Implement ContentView with tab bar and onboarding gate

**PushupCounter/ContentView.swift:**
```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [UserSettings]

    @State private var screenTimeManager = ScreenTimeManager()
    @State private var pushupDetector = PushupDetector()

    private var settings: UserSettings {
        if let existing = settingsList.first {
            return existing
        }
        let new = UserSettings()
        modelContext.insert(new)
        return new
    }

    var body: some View {
        if !settings.hasCompletedOnboarding {
            OnboardingView(settings: settings, screenTimeManager: screenTimeManager)
                .environment(screenTimeManager)
                .environment(pushupDetector)
        } else {
            TabView {
                TodayView(settings: settings)
                    .tabItem {
                        Label("Today", systemImage: "figure.strengthtraining.traditional")
                    }
                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "calendar")
                    }
                SettingsView(settings: settings)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
            .environment(screenTimeManager)
            .environment(pushupDetector)
            .onAppear {
                screenTimeManager.loadSelection()
            }
        }
    }
}
```

### Step 2: Update PushupCounterApp.swift

**PushupCounter/PushupCounterApp.swift:**
```swift
import SwiftUI
import SwiftData

@main
struct PushupCounterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [UserSettings.self, DailyRecord.self, PushupSession.self])
    }
}
```

### Step 3: Create placeholder views so the project compiles

These are minimal placeholder views. Each will be fully implemented in subsequent tasks.

**PushupCounter/Views/Onboarding/OnboardingView.swift:**
```swift
import SwiftUI

struct OnboardingView: View {
    let settings: UserSettings
    let screenTimeManager: ScreenTimeManager

    var body: some View {
        Text("Onboarding — TODO")
    }
}
```

**PushupCounter/Views/Today/TodayView.swift:**
```swift
import SwiftUI

struct TodayView: View {
    let settings: UserSettings

    var body: some View {
        Text("Today — TODO")
    }
}
```

**PushupCounter/Views/History/HistoryView.swift:**
```swift
import SwiftUI

struct HistoryView: View {
    var body: some View {
        Text("History — TODO")
    }
}
```

**PushupCounter/Views/Settings/SettingsView.swift:**
```swift
import SwiftUI

struct SettingsView: View {
    let settings: UserSettings

    var body: some View {
        Text("Settings — TODO")
    }
}
```

### Step 4: Build and run tests

```bash
xcodebuild test \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

### Step 5: Commit

```bash
git add PushupCounter/
git commit -m "feat: add app entry point, ContentView with tab navigation and onboarding gate"
```

---

## Task 8: Onboarding Flow

**Files:**
- Modify: `PushupCounter/Views/Onboarding/OnboardingView.swift`
- Create: `PushupCounter/Views/Onboarding/WelcomeStepView.swift`
- Create: `PushupCounter/Views/Onboarding/GoalStepView.swift`
- Create: `PushupCounter/Views/Onboarding/PermissionsStepView.swift`

### Step 1: Implement WelcomeStepView

**PushupCounter/Views/Onboarding/WelcomeStepView.swift:**
```swift
import SwiftUI

struct WelcomeStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("PushupCounter")
                .font(.largeTitle.bold())

            Text("Do your daily pushups to unlock your social media apps. Stay fit, stay focused.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}
```

### Step 2: Implement GoalStepView

**PushupCounter/Views/Onboarding/GoalStepView.swift:**
```swift
import SwiftUI

struct GoalStepView: View {
    @Bindable var settings: UserSettings
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Set Your Daily Goal")
                .font(.largeTitle.bold())

            Text("How many pushups per day?")
                .font(.body)
                .foregroundStyle(.secondary)

            Picker("Daily Goal", selection: $settings.dailyGoal) {
                ForEach([5, 10, 15, 20, 25, 30, 40, 50, 75, 100], id: \.self) { count in
                    Text("\(count) pushups").tag(count)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)

            Text("\(settings.dailyGoal) pushups")
                .font(.title.bold())
                .foregroundStyle(.blue)

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}
```

### Step 3: Implement PermissionsStepView

**PushupCounter/Views/Onboarding/PermissionsStepView.swift:**
```swift
import SwiftUI
import FamilyControls

struct PermissionsStepView: View {
    @Environment(ScreenTimeManager.self) private var screenTimeManager
    let onComplete: () -> Void
    @State private var isPickerPresented = false

    var body: some View {
        @Bindable var manager = screenTimeManager

        VStack(spacing: 24) {
            Spacer()

            Text("Choose Apps to Lock")
                .font(.largeTitle.bold())

            Text("Select the apps you want blocked until you complete your daily pushups.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if !screenTimeManager.isAuthorized {
                Button("Grant Screen Time Access") {
                    Task {
                        await screenTimeManager.requestAuthorization()
                    }
                }
                .font(.headline)
                .padding()
                .background(.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Button("Select Apps to Block") {
                    isPickerPresented = true
                }
                .font(.headline)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .familyActivityPicker(
                    isPresented: $isPickerPresented,
                    selection: $manager.selection
                )

                if screenTimeManager.hasSelectedApps {
                    Text("Apps selected!")
                        .foregroundStyle(.green)
                        .font(.headline)
                }
            }

            Spacer()

            Button(action: {
                screenTimeManager.saveSelection()
                onComplete()
            }) {
                Text("Finish Setup")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(screenTimeManager.hasSelectedApps ? .blue : .gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!screenTimeManager.hasSelectedApps)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}
```

### Step 4: Update OnboardingView to wire up the 3 steps

**PushupCounter/Views/Onboarding/OnboardingView.swift:**
```swift
import SwiftUI

struct OnboardingView: View {
    @Bindable var settings: UserSettings
    let screenTimeManager: ScreenTimeManager
    @State private var currentStep = 0

    var body: some View {
        TabView(selection: $currentStep) {
            WelcomeStepView {
                withAnimation { currentStep = 1 }
            }
            .tag(0)

            GoalStepView(settings: settings) {
                withAnimation { currentStep = 2 }
            }
            .tag(1)

            PermissionsStepView {
                settings.hasCompletedOnboarding = true
            }
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .interactiveDismissDisabled()
    }
}
```

### Step 5: Build to verify

```bash
xcodebuild build \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

### Step 6: Commit

```bash
git add PushupCounter/Views/Onboarding/
git commit -m "feat: add 3-step onboarding flow (welcome, goal, permissions)"
```

---

## Task 9: Today Dashboard

**Files:**
- Modify: `PushupCounter/Views/Today/TodayView.swift`
- Create: `PushupCounter/Views/Today/ProgressRingView.swift`

### Step 1: Implement ProgressRingView

**PushupCounter/Views/Today/ProgressRingView.swift:**
```swift
import SwiftUI

struct ProgressRingView: View {
    let progress: Double  // 0.0 to 1.0
    let current: Int
    let goal: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 20)

            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    progress >= 1.0 ? Color.green : Color.blue,
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)

            VStack(spacing: 4) {
                Text("\(current)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("of \(goal)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

### Step 2: Implement TodayView

**PushupCounter/Views/Today/TodayView.swift:**
```swift
import SwiftUI
import SwiftData

struct TodayView: View {
    @Bindable var settings: UserSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(ScreenTimeManager.self) private var screenTimeManager
    @Query private var allRecords: [DailyRecord]
    @State private var showingSession = false

    private var todayRecord: DailyRecord {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        if let existing = allRecords.first(where: { calendar.isDate($0.date, inSameDayAs: startOfDay) }) {
            return existing
        }
        let record = DailyRecord(date: startOfDay)
        modelContext.insert(record)
        return record
    }

    private var goalMet: Bool {
        todayRecord.totalPushups >= settings.dailyGoal
    }

    private var currentStreak: Int {
        let calendar = Calendar.current
        let sorted = allRecords
            .filter { $0.goalMet }
            .sorted { $0.date > $1.date }

        var streak = 0
        var expectedDate = calendar.startOfDay(for: Date())

        // If today's goal is met, count today
        if goalMet {
            streak = 1
            expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate)!
        }

        for record in sorted {
            let recordDate = calendar.startOfDay(for: record.date)
            if calendar.isDate(recordDate, inSameDayAs: expectedDate) {
                streak += 1
                expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate)!
            } else if recordDate < expectedDate {
                break
            }
        }
        return streak
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                ProgressRingView(
                    progress: settings.dailyGoal > 0
                        ? Double(todayRecord.totalPushups) / Double(settings.dailyGoal)
                        : 0,
                    current: todayRecord.totalPushups,
                    goal: settings.dailyGoal
                )
                .frame(width: 220, height: 220)

                HStack(spacing: 8) {
                    Image(systemName: goalMet ? "lock.open.fill" : "lock.fill")
                    Text(goalMet ? "Unlocked" : "Locked")
                        .font(.title2.bold())
                }
                .foregroundStyle(goalMet ? .green : .red)

                if currentStreak > 0 {
                    Label("\(currentStreak) day streak", systemImage: "flame.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button {
                    showingSession = true
                } label: {
                    Label("Start Pushups", systemImage: "play.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(goalMet ? .green : .blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("Today")
            .fullScreenCover(isPresented: $showingSession) {
                PushupSessionView(settings: settings, dailyRecord: todayRecord)
            }
        }
    }
}
```

### Step 3: Create placeholder PushupSessionView

**PushupCounter/Views/Session/PushupSessionView.swift:**
```swift
import SwiftUI

struct PushupSessionView: View {
    let settings: UserSettings
    let dailyRecord: DailyRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Text("Session — TODO")
        Button("Done") { dismiss() }
    }
}
```

### Step 4: Build to verify

```bash
xcodebuild build \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

### Step 5: Commit

```bash
git add PushupCounter/Views/Today/ PushupCounter/Views/Session/PushupSessionView.swift
git commit -m "feat: add Today dashboard with progress ring and streak display"
```

---

## Task 10: Pushup Session Screen

**Files:**
- Modify: `PushupCounter/Views/Session/PushupSessionView.swift`

### Step 1: Implement full PushupSessionView

**PushupCounter/Views/Session/PushupSessionView.swift:**
```swift
import SwiftUI
import AVFoundation
import SwiftData

struct PushupSessionView: View {
    @Bindable var settings: UserSettings
    @Bindable var dailyRecord: DailyRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ScreenTimeManager.self) private var screenTimeManager
    @Environment(PushupDetector.self) private var pushupDetector

    @State private var cameraManager: CameraManager?
    @State private var sessionStartTime = Date()
    @State private var sessionCount = 0
    @State private var showCelebration = false

    private var totalToday: Int {
        dailyRecord.totalPushups + pushupDetector.count
    }

    private var goalReached: Bool {
        totalToday >= settings.dailyGoal
    }

    var body: some View {
        ZStack {
            // Camera preview
            if let cameraManager {
                CameraPreviewView(session: cameraManager.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // Overlay UI
            VStack {
                // Top: pushup count
                Text("\(pushupDetector.count)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(.top, 60)

                // Phase indicator
                HStack {
                    Circle()
                        .fill(pushupDetector.bodyDetected ? .green : .red)
                        .frame(width: 12, height: 12)
                    Text(pushupDetector.bodyDetected
                         ? (pushupDetector.phase == .down ? "DOWN" : pushupDetector.phase == .up ? "UP" : "READY")
                         : "No body detected")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                Spacer()

                // Progress toward daily goal
                VStack(spacing: 8) {
                    ProgressView(value: Double(totalToday), total: Double(settings.dailyGoal))
                        .tint(goalReached ? .green : .blue)
                        .scaleEffect(y: 2)
                        .padding(.horizontal, 40)

                    Text("\(totalToday) / \(settings.dailyGoal) today")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }

                // Done button
                Button {
                    endSession()
                } label: {
                    Text("Done")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }

            // Celebration overlay
            if showCelebration {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.green)
                    Text("Goal Reached!")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("Your apps are now unlocked")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.7))
                .onTapGesture {
                    endSession()
                }
            }
        }
        .onAppear {
            sessionStartTime = Date()
            pushupDetector.reset()
            let manager = CameraManager(pushupDetector: pushupDetector)
            cameraManager = manager
            Task {
                await manager.requestPermission()
                manager.setupSession()
                manager.startSession()
            }
        }
        .onDisappear {
            cameraManager?.stopSession()
        }
        .onChange(of: goalReached) { _, reached in
            if reached && !showCelebration {
                showCelebration = true
                if settings.soundEnabled {
                    AudioServicesPlaySystemSound(1025) // completion sound
                }
            }
        }
        .onChange(of: pushupDetector.count) { oldCount, newCount in
            if newCount > oldCount && settings.soundEnabled && !goalReached {
                AudioServicesPlaySystemSound(1057) // tock sound for each rep
            }
        }
        .statusBarHidden()
    }

    private func endSession() {
        cameraManager?.stopSession()
        let count = pushupDetector.count
        guard count > 0 else {
            dismiss()
            return
        }

        let session = PushupSession(startTime: sessionStartTime, endTime: Date(), count: count)
        session.dailyRecord = dailyRecord
        dailyRecord.sessions.append(session)
        modelContext.insert(session)

        if totalToday >= settings.dailyGoal {
            dailyRecord.goalMet = true
            screenTimeManager.removeShields()
        }

        try? modelContext.save()
        dismiss()
    }
}
```

### Step 2: Build to verify

```bash
xcodebuild build \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

### Step 3: Commit

```bash
git add PushupCounter/Views/Session/PushupSessionView.swift
git commit -m "feat: add full pushup session screen with camera, counting, and celebration"
```

---

## Task 11: History View

**Files:**
- Modify: `PushupCounter/Views/History/HistoryView.swift`
- Create: `PushupCounter/Views/History/DayDetailView.swift`

### Step 1: Implement HistoryView

**PushupCounter/Views/History/HistoryView.swift:**
```swift
import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \DailyRecord.date, order: .reverse) private var records: [DailyRecord]
    @State private var selectedRecord: DailyRecord?

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "calendar.badge.clock",
                        description: Text("Complete your first pushup session to start tracking progress.")
                    )
                } else {
                    List(records) { record in
                        Button {
                            selectedRecord = record
                        } label: {
                            HStack {
                                Circle()
                                    .fill(record.goalMet ? .green : .red)
                                    .frame(width: 12, height: 12)
                                VStack(alignment: .leading) {
                                    Text(record.date, style: .date)
                                        .font(.headline)
                                    Text("\(record.totalPushups) pushups in \(record.sessions.count) session(s)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if record.goalMet {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("History")
            .sheet(item: $selectedRecord) { record in
                DayDetailView(record: record)
            }
        }
    }
}
```

### Step 2: Implement DayDetailView

**PushupCounter/Views/History/DayDetailView.swift:**
```swift
import SwiftUI

struct DayDetailView: View {
    let record: DailyRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    LabeledContent("Date", value: record.date, format: .dateTime.month().day().year())
                    LabeledContent("Total Pushups", value: "\(record.totalPushups)")
                    LabeledContent("Goal Met", value: record.goalMet ? "Yes" : "No")
                    LabeledContent("Sessions", value: "\(record.sessions.count)")
                }

                Section("Sessions") {
                    ForEach(record.sessions.sorted(by: { $0.startTime < $1.startTime })) { session in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(session.startTime, style: .time)
                                    .font(.headline)
                                Text("\(session.count) pushups")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            let duration = session.endTime.timeIntervalSince(session.startTime)
                            Text(Duration.seconds(duration).formatted(.units(allowed: [.minutes, .seconds])))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Day Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

### Step 3: Build to verify

```bash
xcodebuild build \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

### Step 4: Commit

```bash
git add PushupCounter/Views/History/
git commit -m "feat: add history view with day detail and session breakdown"
```

---

## Task 12: Settings View

**Files:**
- Modify: `PushupCounter/Views/Settings/SettingsView.swift`

### Step 1: Implement SettingsView

**PushupCounter/Views/Settings/SettingsView.swift:**
```swift
import SwiftUI
import FamilyControls
import SwiftData

struct SettingsView: View {
    @Bindable var settings: UserSettings
    @Environment(ScreenTimeManager.self) private var screenTimeManager
    @Environment(\.modelContext) private var modelContext
    @State private var isPickerPresented = false
    @State private var showResetConfirmation = false

    var body: some View {
        @Bindable var manager = screenTimeManager

        NavigationStack {
            Form {
                Section("Daily Goal") {
                    Stepper("\(settings.dailyGoal) pushups", value: $settings.dailyGoal, in: 1...200)
                }

                Section("Blocked Apps") {
                    Button("Change Blocked Apps") {
                        isPickerPresented = true
                    }
                    .familyActivityPicker(
                        isPresented: $isPickerPresented,
                        selection: $manager.selection
                    )
                    .onChange(of: screenTimeManager.selection) {
                        screenTimeManager.saveSelection()
                    }
                }

                Section("Sound") {
                    Toggle("Rep Completion Sound", isOn: $settings.soundEnabled)
                }

                Section("Stats") {
                    let records = fetchAllRecords()
                    LabeledContent("Total Pushups (All Time)", value: "\(records.reduce(0) { $0 + $1.totalPushups })")
                    LabeledContent("Days Completed", value: "\(records.filter(\.goalMet).count)")
                    LabeledContent("Total Sessions", value: "\(records.reduce(0) { $0 + $1.sessions.count })")
                }

                Section {
                    Button("Reset All Data", role: .destructive) {
                        showResetConfirmation = true
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Reset all data?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
                Button("Reset Everything", role: .destructive) {
                    resetAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all pushup history, reset your goal, and remove app blocking. This cannot be undone.")
            }
        }
    }

    private func fetchAllRecords() -> [DailyRecord] {
        let descriptor = FetchDescriptor<DailyRecord>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func resetAllData() {
        let records = fetchAllRecords()
        for record in records {
            modelContext.delete(record)
        }
        settings.dailyGoal = 30
        settings.soundEnabled = true
        settings.hasCompletedOnboarding = false
        settings.selectedAppsData = nil
        screenTimeManager.removeShields()
        try? modelContext.save()
    }
}
```

### Step 2: Build to verify

```bash
xcodebuild build \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

### Step 3: Commit

```bash
git add PushupCounter/Views/Settings/SettingsView.swift
git commit -m "feat: add settings view with goal, apps, sound, stats, and reset"
```

---

## Task 13: App Extensions (Shield + DeviceActivity)

**Files:**
- Modify: `ShieldConfigurationExtension/ShieldConfigurationExtension.swift`
- Modify: `DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift`

### Step 1: Implement ShieldConfigurationExtension

**ShieldConfigurationExtension/ShieldConfigurationExtension.swift:**
```swift
import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: .white,
            icon: UIImage(systemName: "figure.strengthtraining.traditional"),
            title: ShieldConfiguration.Label(
                text: "Do Your Pushups First!",
                color: .black
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Complete your daily pushups to unlock this app.",
                color: .darkGray
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "OK",
                color: .white
            ),
            primaryButtonBackgroundColor: .systemBlue,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Close App",
                color: .systemBlue
            )
        )
    }
}
```

### Step 2: Implement DeviceActivityMonitorExtension

**DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift:**
```swift
import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let store = ManagedSettingsStore()
    private let sharedDefaults = UserDefaults(suiteName: "group.com.pushupcounter.shared")

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        // Re-apply shields at the start of each day (midnight)
        guard let data = sharedDefaults?.data(forKey: "selectedApps"),
              let selection = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return
        }

        let tokens = selection.applicationTokens
        guard !tokens.isEmpty else { return }
        store.shield.applications = tokens
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
    }
}
```

### Step 3: Build to verify

```bash
xcodebuild build \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

### Step 4: Run all tests

```bash
xcodebuild test \
  -project PushupCounter.xcodeproj \
  -scheme PushupCounter \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

### Step 5: Commit

```bash
git add ShieldConfigurationExtension/ DeviceActivityMonitorExtension/
git commit -m "feat: add shield configuration and device activity monitor extensions"
```

---

## Testing Strategy

### Unit Tests (automated, run in CI/simulator)
- `AngleCalculatorTests` — all angle computation edge cases
- `PushupDetectorTests` — state machine transitions, debounce, counting, reset
- `DailyRecordTests` — model relationships, computed properties

### Manual Device Tests (require physical iOS device)
| Test | Steps | Expected |
|------|-------|----------|
| Camera permission | Launch app → go to session | System prompt for camera access |
| Body detection | Point camera at yourself | "UP/DOWN" indicator appears |
| Pushup counting | Do 3 pushups facing camera | Count goes from 0 to 3 |
| Screen Time auth | Onboarding step 3 | System prompt for Screen Time |
| App picker | Select Instagram | Instagram appears in selection |
| App blocking | Finish onboarding without doing pushups | Instagram shows shield |
| App unblocking | Do pushups to meet goal | Instagram shield disappears |
| Midnight reset | Wait for midnight (or adjust device time) | Shields re-applied |
| Multiple sessions | Do 10 pushups, end, do 10 more | Total shows 20 |
| Audio feedback | Ensure sound toggle on, do pushup | Hear "tock" on each rep |

### Performance Expectations
- Camera frame processing: ~30fps with no visible lag
- Vision body pose detection: <33ms per frame on A14+ chip
- Memory usage: <100MB during active session
- Extension memory: <5MB (Apple's limit for extensions)

---

## File Tree Summary

```
PushupCounter/
├── project.yml
├── PushupCounter/
│   ├── PushupCounterApp.swift
│   ├── ContentView.swift
│   ├── PushupCounter.entitlements
│   ├── Models/
│   │   ├── UserSettings.swift
│   │   ├── DailyRecord.swift
│   │   └── PushupSession.swift
│   ├── Services/
│   │   ├── PushupDetector.swift
│   │   ├── ScreenTimeManager.swift
│   │   └── CameraManager.swift
│   ├── Utilities/
│   │   └── AngleCalculator.swift
│   └── Views/
│       ├── Onboarding/
│       │   ├── OnboardingView.swift
│       │   ├── WelcomeStepView.swift
│       │   ├── GoalStepView.swift
│       │   └── PermissionsStepView.swift
│       ├── Today/
│       │   ├── TodayView.swift
│       │   └── ProgressRingView.swift
│       ├── Session/
│       │   ├── PushupSessionView.swift
│       │   └── CameraPreviewView.swift
│       ├── History/
│       │   ├── HistoryView.swift
│       │   └── DayDetailView.swift
│       └── Settings/
│           └── SettingsView.swift
├── ShieldConfigurationExtension/
│   ├── ShieldConfigurationExtension.swift
│   └── ShieldConfigurationExtension.entitlements
├── DeviceActivityMonitorExtension/
│   ├── DeviceActivityMonitorExtension.swift
│   └── DeviceActivityMonitorExtension.entitlements
├── PushupCounterTests/
│   ├── PushupCounterTests.swift
│   ├── AngleCalculatorTests.swift
│   ├── PushupDetectorTests.swift
│   └── DailyRecordTests.swift
└── docs/
    └── plans/
        ├── 2026-03-02-pushup-counter-design.md
        └── 2026-03-02-pushup-counter-implementation.md
```
