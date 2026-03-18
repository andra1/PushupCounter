# Daily Pushup Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shareable daily pushup summary card with an animated form quality ring, backed by per-rep elbow angle tracking extracted from ARKit skeleton data.

**Architecture:** Extend the existing ARKit body tracking pipeline to extract elbow angles alongside hip height. Persist per-rep min/max angles on `PushupSession`. Build a `DailyCardView` with animated form quality ring as the hero element. Add `CardExporter` to render the card to video/image for sharing via system share sheet.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, ARKit, AVFoundation (for video export), XCTest

**Spec:** `docs/superpowers/specs/2026-03-18-daily-pushup-card-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `PushupCounter/Models/RepAngle.swift` | `RepAngle` Codable struct (minAngle, maxAngle) |
| `PushupCounter/Views/Card/FormQualityRingView.swift` | Animated circular progress ring for form score |
| `PushupCounter/Views/Card/DailyCardView.swift` | Full daily card layout (ring + stats + set chips) |
| `PushupCounter/Views/Card/CompactCardView.swift` | Compact card variant for history list rows |
| `PushupCounter/Services/CardExporter.swift` | Render card to PNG image and MP4 video |
| `PushupCounterTests/RepAngleTests.swift` | Tests for RepAngle, formScore computations |
| `PushupCounterTests/PushupDetectorAngleTrackingTests.swift` | Tests for per-rep angle tracking in PushupDetector |

### Modified Files
| File | Changes |
|------|---------|
| `PushupCounter/Models/PushupSession.swift` | Add `repAnglesData: Data?`, computed `repAngles`, `formScore` |
| `PushupCounter/Models/DailyRecord.swift` | Add computed `formScore` |
| `PushupCounter/Services/PushupDetector.swift` | Change `processHipHeight` → `processFrame(hipHeight:elbowAngle:)`, add angle tracking |
| `PushupCounter/Services/ARSessionManager.swift` | Extract elbow angles from skeleton, pass to detector |
| `PushupCounter/Views/Session/PushupSessionView.swift` | Persist `completedRepAngles` on session save |
| `PushupCounter/Views/Today/TodayView.swift` | Replace plain number with `DailyCardView` |
| `PushupCounter/Views/History/HistoryView.swift` | Use `CompactCardView` for list rows |
| `PushupCounter/Views/History/DayDetailView.swift` | Add full card + share button |
| `PushupCounterTests/PushupDetectorTests.swift` | Update `processHipHeight` calls → `processFrame(hipHeight:elbowAngle:)` |

---

## Task 1: RepAngle struct and PushupSession form score

**Files:**
- Create: `PushupCounter/Models/RepAngle.swift`
- Modify: `PushupCounter/Models/PushupSession.swift`
- Create: `PushupCounterTests/RepAngleTests.swift`

- [ ] **Step 1: Write failing tests for RepAngle and PushupSession.formScore**

Create `PushupCounterTests/RepAngleTests.swift`:

```swift
import XCTest
@testable import PushupCounter

final class RepAngleTests: XCTestCase {

    // MARK: - RepAngle Codable

    func testRepAngle_encodeDecode_roundTrips() throws {
        let angles = [
            RepAngle(minAngle: 85.0, maxAngle: 165.0),
            RepAngle(minAngle: 95.0, maxAngle: 150.0)
        ]
        let data = try JSONEncoder().encode(angles)
        let decoded = try JSONDecoder().decode([RepAngle].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].minAngle, 85.0)
        XCTAssertEqual(decoded[0].maxAngle, 165.0)
        XCTAssertEqual(decoded[1].minAngle, 95.0)
        XCTAssertEqual(decoded[1].maxAngle, 150.0)
    }

    // MARK: - RepAngle.hasFullRangeOfMotion

    func testHasFullROM_deepAndExtended_returnsTrue() {
        let rep = RepAngle(minAngle: 85.0, maxAngle: 165.0)
        XCTAssertTrue(rep.hasFullRangeOfMotion)
    }

    func testHasFullROM_notDeepEnough_returnsFalse() {
        let rep = RepAngle(minAngle: 95.0, maxAngle: 165.0)
        XCTAssertFalse(rep.hasFullRangeOfMotion)
    }

    func testHasFullROM_notExtendedEnough_returnsFalse() {
        let rep = RepAngle(minAngle: 85.0, maxAngle: 150.0)
        XCTAssertFalse(rep.hasFullRangeOfMotion)
    }

    func testHasFullROM_exactThresholds_returnsFalse() {
        // Exactly 90 and 160 should NOT count (need strictly < 90 and > 160)
        let rep = RepAngle(minAngle: 90.0, maxAngle: 160.0)
        XCTAssertFalse(rep.hasFullRangeOfMotion)
    }

    // MARK: - PushupSession.formScore

    func testFormScore_allGoodReps_returns100() {
        let session = PushupSession(startTime: Date(), endTime: Date(), count: 3)
        let angles = [
            RepAngle(minAngle: 80.0, maxAngle: 170.0),
            RepAngle(minAngle: 85.0, maxAngle: 165.0),
            RepAngle(minAngle: 88.0, maxAngle: 162.0)
        ]
        session.repAnglesData = try? JSONEncoder().encode(angles)
        XCTAssertEqual(session.formScore, 100.0)
    }

    func testFormScore_mixedReps_returnsCorrectPercentage() {
        let session = PushupSession(startTime: Date(), endTime: Date(), count: 4)
        let angles = [
            RepAngle(minAngle: 80.0, maxAngle: 170.0),  // good
            RepAngle(minAngle: 95.0, maxAngle: 165.0),  // bad (not deep)
            RepAngle(minAngle: 85.0, maxAngle: 150.0),  // bad (not extended)
            RepAngle(minAngle: 88.0, maxAngle: 162.0)   // good
        ]
        session.repAnglesData = try? JSONEncoder().encode(angles)
        XCTAssertEqual(session.formScore, 50.0)
    }

    func testFormScore_noAngleData_returnsNil() {
        let session = PushupSession(startTime: Date(), endTime: Date(), count: 5)
        XCTAssertNil(session.formScore)
    }

    func testFormScore_emptyAngles_returnsNil() {
        let session = PushupSession(startTime: Date(), endTime: Date(), count: 0)
        session.repAnglesData = try? JSONEncoder().encode([RepAngle]())
        XCTAssertNil(session.formScore)
    }

    // MARK: - PushupSession.repAngles

    func testRepAngles_nilData_returnsEmpty() {
        let session = PushupSession(startTime: Date(), endTime: Date(), count: 0)
        XCTAssertTrue(session.repAngles.isEmpty)
    }

    func testRepAngles_validData_returnsDecoded() {
        let session = PushupSession(startTime: Date(), endTime: Date(), count: 2)
        let angles = [RepAngle(minAngle: 80.0, maxAngle: 170.0)]
        session.repAnglesData = try? JSONEncoder().encode(angles)
        XCTAssertEqual(session.repAngles.count, 1)
        XCTAssertEqual(session.repAngles[0].minAngle, 80.0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:PushupCounterTests/RepAngleTests 2>&1 | tail -20`
Expected: FAIL — `RepAngle` type doesn't exist yet

- [ ] **Step 3: Create RepAngle struct**

Create `PushupCounter/Models/RepAngle.swift`:

```swift
import Foundation

struct RepAngle: Codable, Equatable {
    let minAngle: Double
    let maxAngle: Double

    var hasFullRangeOfMotion: Bool {
        minAngle < 90.0 && maxAngle > 160.0
    }
}
```

- [ ] **Step 4: Add repAnglesData and computed properties to PushupSession**

In `PushupCounter/Models/PushupSession.swift`, add after `var dailyRecord: DailyRecord?`:

```swift
@Attribute var repAnglesData: Data?

var repAngles: [RepAngle] {
    guard let data = repAnglesData else { return [] }
    return (try? JSONDecoder().decode([RepAngle].self, from: data)) ?? []
}

var formScore: Double? {
    let angles = repAngles
    guard !angles.isEmpty else { return nil }
    let goodReps = angles.filter { $0.hasFullRangeOfMotion }.count
    return Double(goodReps) / Double(angles.count) * 100.0
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:PushupCounterTests/RepAngleTests 2>&1 | tail -20`
Expected: All RepAngleTests PASS

- [ ] **Step 6: Commit**

```bash
git add PushupCounter/Models/RepAngle.swift PushupCounter/Models/PushupSession.swift PushupCounterTests/RepAngleTests.swift
git commit -m "feat: add RepAngle struct and formScore to PushupSession"
```

---

## Task 2: DailyRecord.formScore

**Files:**
- Modify: `PushupCounter/Models/DailyRecord.swift`
- Modify: `PushupCounterTests/DailyRecordTests.swift`

- [ ] **Step 1: Write failing tests for DailyRecord.formScore**

Add to `PushupCounterTests/DailyRecordTests.swift`:

```swift
// MARK: - Form Score

func testFormScore_noSessions_returnsNil() {
    let record = DailyRecord(date: Date())
    context.insert(record)
    XCTAssertNil(record.formScore)
}

func testFormScore_sessionsWithoutAngleData_returnsNil() {
    let record = DailyRecord(date: Date())
    context.insert(record)

    let session = PushupSession(startTime: Date(), endTime: Date(), count: 10)
    session.dailyRecord = record
    record.sessions.append(session)
    context.insert(session)

    XCTAssertNil(record.formScore)
}

func testFormScore_singleSession_returnsSessionScore() {
    let record = DailyRecord(date: Date())
    context.insert(record)

    let session = PushupSession(startTime: Date(), endTime: Date(), count: 2)
    let angles = [
        RepAngle(minAngle: 80.0, maxAngle: 170.0),  // good
        RepAngle(minAngle: 95.0, maxAngle: 170.0)   // bad
    ]
    session.repAnglesData = try? JSONEncoder().encode(angles)
    session.dailyRecord = record
    record.sessions.append(session)
    context.insert(session)

    XCTAssertEqual(record.formScore, 50.0)
}

func testFormScore_multipleSessions_weightsbyRepCount() {
    let record = DailyRecord(date: Date())
    context.insert(record)

    // Session 1: 1 rep, 100% form
    let s1 = PushupSession(startTime: Date(), endTime: Date(), count: 1)
    s1.repAnglesData = try? JSONEncoder().encode([RepAngle(minAngle: 80.0, maxAngle: 170.0)])
    s1.dailyRecord = record
    record.sessions.append(s1)
    context.insert(s1)

    // Session 2: 3 reps, 0% form
    let s2 = PushupSession(startTime: Date(), endTime: Date(), count: 3)
    s2.repAnglesData = try? JSONEncoder().encode([
        RepAngle(minAngle: 95.0, maxAngle: 170.0),
        RepAngle(minAngle: 95.0, maxAngle: 170.0),
        RepAngle(minAngle: 95.0, maxAngle: 170.0)
    ])
    s2.dailyRecord = record
    record.sessions.append(s2)
    context.insert(s2)

    // Weighted: (1 * 100 + 3 * 0) / (1 + 3) = 25.0
    XCTAssertEqual(record.formScore!, 25.0, accuracy: 0.1)
}

func testFormScore_mixOfLegacyAndNewSessions_ignoresLegacy() {
    let record = DailyRecord(date: Date())
    context.insert(record)

    // Legacy session (no angle data)
    let legacy = PushupSession(startTime: Date(), endTime: Date(), count: 20)
    legacy.dailyRecord = record
    record.sessions.append(legacy)
    context.insert(legacy)

    // New session with angle data
    let s1 = PushupSession(startTime: Date(), endTime: Date(), count: 2)
    s1.repAnglesData = try? JSONEncoder().encode([
        RepAngle(minAngle: 80.0, maxAngle: 170.0),
        RepAngle(minAngle: 80.0, maxAngle: 170.0)
    ])
    s1.dailyRecord = record
    record.sessions.append(s1)
    context.insert(s1)

    // Only considers the new session: 100%
    XCTAssertEqual(record.formScore, 100.0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:PushupCounterTests/DailyRecordTests 2>&1 | tail -20`
Expected: FAIL — `formScore` property doesn't exist on DailyRecord

- [ ] **Step 3: Add formScore to DailyRecord**

In `PushupCounter/Models/DailyRecord.swift`, add after `totalPushups`:

```swift
var formScore: Double? {
    let scored = sessions.filter { $0.formScore != nil }
    guard !scored.isEmpty else { return nil }
    let totalReps = scored.reduce(0) { $0 + $1.repAngles.count }
    guard totalReps > 0 else { return nil }
    let weightedSum = scored.reduce(0.0) { $0 + ($1.formScore! * Double($1.repAngles.count)) }
    return weightedSum / Double(totalReps)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:PushupCounterTests/DailyRecordTests 2>&1 | tail -20`
Expected: All DailyRecordTests PASS

- [ ] **Step 5: Commit**

```bash
git add PushupCounter/Models/DailyRecord.swift PushupCounterTests/DailyRecordTests.swift
git commit -m "feat: add formScore computed property to DailyRecord"
```

---

## Task 3: PushupDetector angle tracking

**Files:**
- Modify: `PushupCounter/Services/PushupDetector.swift`
- Create: `PushupCounterTests/PushupDetectorAngleTrackingTests.swift`
- Modify: `PushupCounterTests/PushupDetectorTests.swift`

- [ ] **Step 1: Write failing tests for angle tracking**

Create `PushupCounterTests/PushupDetectorAngleTrackingTests.swift`:

```swift
import XCTest
@testable import PushupCounter

@MainActor
final class PushupDetectorAngleTrackingTests: XCTestCase {

    private var detector: PushupDetector!

    private let baseline: Float = 1.0
    private let upHeight: Float = 1.0
    private let downHeight: Float = 0.8

    override func setUp() {
        detector = PushupDetector()
    }

    // MARK: - Helpers

    private func calibrate() {
        for _ in 0..<10 {
            detector.processFrame(hipHeight: baseline, elbowAngle: 170.0)
        }
    }

    private func feedFrame(hipHeight: Float, elbowAngle: Double?, frames: Int) {
        for _ in 0..<frames {
            detector.processFrame(hipHeight: hipHeight, elbowAngle: elbowAngle)
        }
    }

    // MARK: - Initial State

    func testInitial_completedRepAnglesIsEmpty() {
        XCTAssertTrue(detector.completedRepAngles.isEmpty)
    }

    // MARK: - Tracking During Reps

    func testOneRep_recordsMinAndMaxAngles() {
        calibrate()
        // Go up first
        feedFrame(hipHeight: upHeight, elbowAngle: 170.0, frames: 3)
        // Go down with varying angles
        feedFrame(hipHeight: downHeight, elbowAngle: 100.0, frames: 1)
        feedFrame(hipHeight: downHeight, elbowAngle: 85.0, frames: 1)  // min
        feedFrame(hipHeight: downHeight, elbowAngle: 90.0, frames: 1)
        // Go back up
        feedFrame(hipHeight: upHeight, elbowAngle: 165.0, frames: 3)  // max should be 170 from earlier

        XCTAssertEqual(detector.completedRepAngles.count, 1)
        XCTAssertEqual(detector.completedRepAngles[0].minAngle, 85.0)
        XCTAssertEqual(detector.completedRepAngles[0].maxAngle, 170.0)
    }

    func testTwoReps_recordsBothSeparately() {
        calibrate()
        feedFrame(hipHeight: upHeight, elbowAngle: 170.0, frames: 3)

        // Rep 1
        feedFrame(hipHeight: downHeight, elbowAngle: 80.0, frames: 3)
        feedFrame(hipHeight: upHeight, elbowAngle: 165.0, frames: 3)

        // Rep 2
        feedFrame(hipHeight: downHeight, elbowAngle: 95.0, frames: 3)
        feedFrame(hipHeight: upHeight, elbowAngle: 155.0, frames: 3)

        XCTAssertEqual(detector.completedRepAngles.count, 2)
        XCTAssertEqual(detector.completedRepAngles[0].minAngle, 80.0)
        XCTAssertEqual(detector.completedRepAngles[1].minAngle, 95.0)
    }

    func testNilElbowAngle_doesNotCrash() {
        calibrate()
        feedFrame(hipHeight: upHeight, elbowAngle: nil, frames: 3)
        feedFrame(hipHeight: downHeight, elbowAngle: nil, frames: 3)
        feedFrame(hipHeight: upHeight, elbowAngle: nil, frames: 3)

        // Rep still counted but angles are default (Double.greatestFiniteMagnitude / 0)
        XCTAssertEqual(detector.count, 1)
        XCTAssertEqual(detector.completedRepAngles.count, 1)
    }

    // MARK: - Reset

    func testReset_clearsCompletedRepAngles() {
        calibrate()
        feedFrame(hipHeight: upHeight, elbowAngle: 170.0, frames: 3)
        feedFrame(hipHeight: downHeight, elbowAngle: 80.0, frames: 3)
        feedFrame(hipHeight: upHeight, elbowAngle: 170.0, frames: 3)
        XCTAssertEqual(detector.completedRepAngles.count, 1)

        detector.reset()
        XCTAssertTrue(detector.completedRepAngles.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:PushupCounterTests/PushupDetectorAngleTrackingTests 2>&1 | tail -20`
Expected: FAIL — `processFrame(hipHeight:elbowAngle:)` doesn't exist

- [ ] **Step 3: Update PushupDetector to track angles**

Replace the contents of `PushupCounter/Services/PushupDetector.swift`:

```swift
import Observation

enum PushupPhase: Equatable {
    case calibrating
    case up
    case down
    case unknown
}

@MainActor
@Observable
final class PushupDetector {
    private(set) var count: Int = 0
    private(set) var phase: PushupPhase = .calibrating
    private(set) var bodyDetected: Bool = false
    private(set) var baselineHeight: Float?
    private(set) var completedRepAngles: [RepAngle] = []

    private var calibrationSamples: [Float] = []
    private var pendingPhase: PushupPhase = .unknown
    private var consecutiveFrames: Int = 0

    // Per-rep angle tracking
    private var currentRepMinAngle: Double = .greatestFiniteMagnitude
    private var currentRepMaxAngle: Double = 0.0

    private let debounceThreshold = 3
    private let calibrationFrameCount = 10
    private let downDropThreshold: Float = 0.15
    private let upDropThreshold: Float = 0.05

    func processFrame(hipHeight: Float?, elbowAngle: Double?) {
        guard let hipHeight else {
            bodyDetected = false
            return
        }
        bodyDetected = true

        // Track elbow angle for current rep
        if let angle = elbowAngle {
            currentRepMinAngle = min(currentRepMinAngle, angle)
            currentRepMaxAngle = max(currentRepMaxAngle, angle)
        }

        // Calibration phase: collect samples to establish baseline
        if phase == .calibrating {
            calibrationSamples.append(hipHeight)
            if calibrationSamples.count >= calibrationFrameCount {
                baselineHeight = calibrationSamples.reduce(0, +) / Float(calibrationSamples.count)
                phase = .unknown
            }
            return
        }

        guard let baseline = baselineHeight else { return }

        let drop = baseline - hipHeight

        let detected: PushupPhase
        if drop > downDropThreshold {
            detected = .down
        } else if drop < upDropThreshold {
            detected = .up
        } else {
            return // dead zone
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
                completedRepAngles.append(RepAngle(
                    minAngle: currentRepMinAngle == .greatestFiniteMagnitude ? 0.0 : currentRepMinAngle,
                    maxAngle: currentRepMaxAngle
                ))
                currentRepMinAngle = .greatestFiniteMagnitude
                currentRepMaxAngle = 0.0
            }
        }
    }

    func reset() {
        count = 0
        phase = .calibrating
        bodyDetected = false
        baselineHeight = nil
        calibrationSamples = []
        pendingPhase = .unknown
        consecutiveFrames = 0
        completedRepAngles = []
        currentRepMinAngle = .greatestFiniteMagnitude
        currentRepMaxAngle = 0.0
    }
}
```

- [ ] **Step 4: Update existing PushupDetectorTests to use new API**

In `PushupCounterTests/PushupDetectorTests.swift`, update the two helper methods at the bottom of the file. Every test method calls through these two helpers, so updating them is sufficient to fix all 20+ tests:

```swift
private func calibrate(at height: Float) {
    for _ in 0..<10 {
        detector.processFrame(hipHeight: height, elbowAngle: nil)
    }
}

private func feedHeight(_ height: Float, frames: Int) {
    for _ in 0..<frames {
        detector.processFrame(hipHeight: height, elbowAngle: nil)
    }
}
```

- [ ] **Step 5: Run all PushupDetector tests**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:PushupCounterTests/PushupDetectorTests -only-testing:PushupCounterTests/PushupDetectorAngleTrackingTests 2>&1 | tail -30`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add PushupCounter/Services/PushupDetector.swift PushupCounterTests/PushupDetectorTests.swift PushupCounterTests/PushupDetectorAngleTrackingTests.swift
git commit -m "feat: add per-rep elbow angle tracking to PushupDetector"
```

---

## Task 4: ARSessionManager elbow angle extraction

**Files:**
- Modify: `PushupCounter/Services/ARSessionManager.swift`

Note: ARSessionManager uses ARKit hardware APIs that cannot be unit tested in the simulator. This task is integration-only — verify via build + manual test on device.

- [ ] **Step 1: Update ARSessionManager to extract elbow angles**

Replace the `ARSessionDelegate` extension in `PushupCounter/Services/ARSessionManager.swift`:

```swift
// MARK: - ARSessionDelegate

extension ARSessionManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let bodyAnchor = anchors.compactMap({ $0 as? ARBodyAnchor }).first else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pushupDetector.processFrame(hipHeight: nil, elbowAngle: nil)
                self.bodyDetected = false
            }
            return
        }

        let hipHeight = bodyAnchor.transform.columns.3.y
        let elbowAngle = Self.extractElbowAngle(from: bodyAnchor.skeleton)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pushupDetector.processFrame(hipHeight: hipHeight, elbowAngle: elbowAngle)
            self.bodyDetected = true
        }
    }

    private static func extractElbowAngle(from skeleton: ARSkeleton3D) -> Double? {
        let leftAngle = elbowAngle(
            from: skeleton,
            shoulder: "left_shoulder_1_joint",
            elbow: "left_forearm_joint",
            wrist: "left_hand_joint"
        )
        let rightAngle = elbowAngle(
            from: skeleton,
            shoulder: "right_shoulder_1_joint",
            elbow: "right_forearm_joint",
            wrist: "right_hand_joint"
        )

        switch (leftAngle, rightAngle) {
        case let (l?, r?): return (l + r) / 2.0
        case let (l?, nil): return l
        case let (nil, r?): return r
        case (nil, nil): return nil
        }
    }

    private static func elbowAngle(
        from skeleton: ARSkeleton3D,
        shoulder: String,
        elbow: String,
        wrist: String
    ) -> Double? {
        guard let shoulderIdx = skeleton.definition.index(for: ARSkeleton.JointName(rawValue: shoulder)),
              let elbowIdx = skeleton.definition.index(for: ARSkeleton.JointName(rawValue: elbow)),
              let wristIdx = skeleton.definition.index(for: ARSkeleton.JointName(rawValue: wrist))
        else { return nil }

        let shoulderTransform = skeleton.jointModelTransforms[shoulderIdx]
        let elbowTransform = skeleton.jointModelTransforms[elbowIdx]
        let wristTransform = skeleton.jointModelTransforms[wristIdx]

        // Check for untracked joints (identity matrix)
        let identity = simd_float4x4(1.0)
        if shoulderTransform == identity || elbowTransform == identity || wristTransform == identity {
            return nil
        }

        // Project 3D to 2D (X, Y plane — sagittal)
        let shoulderPt = CGPoint(x: CGFloat(shoulderTransform.columns.3.x), y: CGFloat(shoulderTransform.columns.3.y))
        let elbowPt = CGPoint(x: CGFloat(elbowTransform.columns.3.x), y: CGFloat(elbowTransform.columns.3.y))
        let wristPt = CGPoint(x: CGFloat(wristTransform.columns.3.x), y: CGFloat(wristTransform.columns.3.y))

        return AngleCalculator.angle(a: shoulderPt, b: elbowPt, c: wristPt)
    }
}
```

- [ ] **Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run all existing tests to confirm no regressions**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add PushupCounter/Services/ARSessionManager.swift
git commit -m "feat: extract elbow angles from ARKit skeleton in ARSessionManager"
```

---

## Task 5: Persist rep angles in PushupSessionView

**Files:**
- Modify: `PushupCounter/Views/Session/PushupSessionView.swift`

- [ ] **Step 1: Update endSession() to save rep angles**

In `PushupCounter/Views/Session/PushupSessionView.swift`, replace the `endSession()` method:

```swift
private func endSession() {
    arSessionManager?.pauseSession()
    let count = pushupDetector.count
    guard count > 0 else {
        dismiss()
        return
    }

    let session = PushupSession(startTime: sessionStartTime, endTime: Date(), count: count)
    session.repAnglesData = try? JSONEncoder().encode(pushupDetector.completedRepAngles)
    session.dailyRecord = dailyRecord
    dailyRecord.sessions.append(session)
    modelContext.insert(session)

    try? modelContext.save()
    dismiss()
}
```

- [ ] **Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run all tests**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add PushupCounter/Views/Session/PushupSessionView.swift
git commit -m "feat: persist rep angle data when saving pushup session"
```

---

## Task 6: FormQualityRingView

**Files:**
- Create: `PushupCounter/Views/Card/FormQualityRingView.swift`

- [ ] **Step 1: Create FormQualityRingView**

Create `PushupCounter/Views/Card/FormQualityRingView.swift`:

```swift
import SwiftUI

struct FormQualityRingView: View {
    let score: Double  // 0-100
    let size: CGFloat
    var animated: Bool = true

    @State private var animatedProgress: Double = 0

    private var progress: Double { score / 100.0 }

    private var ringColor: LinearGradient {
        if score >= 70 {
            return LinearGradient(colors: [.green, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if score >= 40 {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: size * 0.057)

            // Progress ring
            Circle()
                .trim(from: 0, to: animated ? animatedProgress : progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: size * 0.057, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Center text
            VStack(spacing: 2) {
                Text("\(Int(animated ? animatedProgress * 100 : score))%")
                    .font(.system(size: size * 0.23, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("FORM")
                    .font(.system(size: size * 0.08))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated else { return }
            withAnimation(.easeOut(duration: 1.2)) {
                animatedProgress = progress
            }
        }
    }
}
```

- [ ] **Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PushupCounter/Views/Card/FormQualityRingView.swift
git commit -m "feat: add FormQualityRingView with animated progress ring"
```

---

## Task 7: DailyCardView

**Files:**
- Create: `PushupCounter/Views/Card/DailyCardView.swift`

- [ ] **Step 1: Create DailyCardView**

Create `PushupCounter/Views/Card/DailyCardView.swift`:

```swift
import SwiftUI

struct DailyCardView: View {
    let record: DailyRecord

    private var totalTime: TimeInterval {
        record.sessions.reduce(0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
    }

    private var formattedTime: String {
        let duration = Duration.seconds(totalTime)
        return duration.formatted(.units(allowed: [.minutes, .seconds]))
    }

    private var sortedSessions: [PushupSession] {
        record.sessions.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Date header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.date.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                    Text(record.date.formatted(.dateTime.month().day().year()))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text("PUSHUP COUNTER")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(0.5)
            }
            .padding(.bottom, 24)

            // Form quality ring
            if let score = record.formScore {
                FormQualityRingView(score: score, size: 140)
                    .padding(.bottom, 28)
            }

            // Stats row
            HStack {
                statColumn(value: "\(record.totalPushups)", label: "PUSHUPS")
                Spacer()
                Divider()
                    .frame(height: 40)
                    .background(Color.white.opacity(0.2))
                Spacer()
                statColumn(value: "\(record.sessions.count)", label: "SETS")
                Spacer()
                Divider()
                    .frame(height: 40)
                    .background(Color.white.opacity(0.2))
                Spacer()
                statColumn(value: formattedTime, label: "TIME")
            }
            .padding(.vertical, 16)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            }

            // Set chips
            if !sortedSessions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(sortedSessions.enumerated()), id: \.element.id) { index, session in
                        setChip(index: index + 1, session: session)
                    }
                }
                .padding(.top, 16)
            }
        }
        .padding(28)
        .background(
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.06, blue: 0.1), Color(red: 0.1, green: 0.1, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
        }
    }

    private func setChip(index: Int, session: PushupSession) -> some View {
        VStack(spacing: 4) {
            Text("\(session.count)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(chipColor(for: session))
            Text("SET \(index)")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func chipColor(for session: PushupSession) -> Color {
        guard let score = session.formScore else { return .white }
        if score >= 70 { return .green }
        if score >= 40 { return .yellow }
        return .red
    }
}
```

- [ ] **Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PushupCounter/Views/Card/DailyCardView.swift
git commit -m "feat: add DailyCardView with form ring, stats, and set chips"
```

---

## Task 8: CompactCardView for history list

**Files:**
- Create: `PushupCounter/Views/Card/CompactCardView.swift`

- [ ] **Step 1: Create CompactCardView**

Create `PushupCounter/Views/Card/CompactCardView.swift`:

```swift
import SwiftUI

struct CompactCardView: View {
    let record: DailyRecord

    var body: some View {
        HStack(spacing: 16) {
            // Mini form ring
            if let score = record.formScore {
                FormQualityRingView(score: score, size: 48, animated: false)
            } else {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text("--")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.date, style: .date)
                    .font(.headline)
                HStack(spacing: 12) {
                    Label("\(record.totalPushups)", systemImage: "figure.strengthtraining.traditional")
                    Label("\(record.sessions.count)", systemImage: "number")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PushupCounter/Views/Card/CompactCardView.swift
git commit -m "feat: add CompactCardView for history list rows"
```

---

## Task 9: CardExporter for image and video export

**Files:**
- Create: `PushupCounter/Services/CardExporter.swift`

- [ ] **Step 1: Create CardExporter**

Create `PushupCounter/Services/CardExporter.swift`:

```swift
import SwiftUI
import AVFoundation

@MainActor
final class CardExporter {

    enum ExportError: Error {
        case renderFailed
        case writerSetupFailed
        case writingFailed
    }

    static func exportImage(for record: DailyRecord) -> UIImage? {
        let cardView = DailyCardView(record: record)
        let renderer = ImageRenderer(content: cardView.frame(width: 360))
        renderer.scale = 3.0
        return renderer.uiImage
    }

    static func exportVideo(for record: DailyRecord) async throws -> URL {
        let size = CGSize(width: 1080, height: 1350) // 4:5 aspect ratio for Instagram
        let fps: Int32 = 30
        let totalFrames = 90 // 3 seconds at 30fps

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("pushup-card-\(UUID().uuidString).mp4")

        // Clean up if file exists
        try? FileManager.default.removeItem(at: outputURL)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw ExportError.writerSetupFailed
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let formScore = record.formScore ?? 0

        for frameIndex in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            // Calculate animation progress for this frame
            let time = Double(frameIndex) / Double(fps)
            let ringProgress: Double
            if time < 1.2 {
                // Ease-out ring fill
                let t = time / 1.2
                ringProgress = 1.0 - pow(1.0 - t, 3)
            } else {
                ringProgress = 1.0
            }
            let currentScore = formScore * ringProgress
            let statsOpacity = time >= 1.2 ? min((time - 1.2) / 0.5, 1.0) : 0.0
            let chipsOffset = time >= 1.7 ? min((time - 1.7) / 0.3, 1.0) : 0.0

            let frameView = AnimatedCardFrame(
                record: record,
                currentScore: currentScore,
                statsOpacity: statsOpacity,
                chipsOffset: chipsOffset
            )
            .frame(width: size.width / 3, height: size.height / 3)

            let renderer = ImageRenderer(content: frameView)
            renderer.scale = 3.0
            guard let cgImage = renderer.cgImage else { continue }

            guard let pixelBuffer = pixelBuffer(from: cgImage, size: size) else { continue }

            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        input.markAsFinished()
        await writer.finishWriting()

        if writer.status == .completed {
            return outputURL
        } else {
            throw ExportError.writingFailed
        }
    }

    private static func pixelBuffer(from cgImage: CGImage, size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width), Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}

// MARK: - Animated Card Frame (for video rendering)

private struct AnimatedCardFrame: View {
    let record: DailyRecord
    let currentScore: Double
    let statsOpacity: Double
    let chipsOffset: Double

    private var totalTime: TimeInterval {
        record.sessions.reduce(0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
    }

    private var formattedTime: String {
        Duration.seconds(totalTime).formatted(.units(allowed: [.minutes, .seconds]))
    }

    private var sortedSessions: [PushupSession] {
        record.sessions.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Date header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.date.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                    Text(record.date.formatted(.dateTime.month().day().year()))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text("PUSHUP COUNTER")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(0.5)
            }
            .padding(.bottom, 24)

            // Form ring (non-animated, driven by currentScore)
            FormQualityRingView(score: currentScore, size: 140, animated: false)
                .padding(.bottom, 28)

            // Stats
            HStack {
                statColumn(value: "\(record.totalPushups)", label: "PUSHUPS")
                Spacer()
                statColumn(value: "\(record.sessions.count)", label: "SETS")
                Spacer()
                statColumn(value: formattedTime, label: "TIME")
            }
            .opacity(statsOpacity)
            .padding(.vertical, 16)

            // Chips
            if !sortedSessions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(sortedSessions.enumerated()), id: \.element.id) { index, session in
                        VStack(spacing: 4) {
                            Text("\(session.count)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.green)
                            Text("SET \(index + 1)")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .offset(y: (1 - chipsOffset) * 20)
                .opacity(chipsOffset)
                .padding(.top, 16)
            }
        }
        .padding(28)
        .background(
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.06, blue: 0.1), Color(red: 0.1, green: 0.1, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
        }
    }
}
```

- [ ] **Step 2: Verify build succeeds**

Run: `xcodebuild build -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PushupCounter/Services/CardExporter.swift
git commit -m "feat: add CardExporter for image and video export"
```

---

## Task 10: Integrate card views into TodayView, HistoryView, DayDetailView

**Files:**
- Modify: `PushupCounter/Views/Today/TodayView.swift`
- Modify: `PushupCounter/Views/History/HistoryView.swift`
- Modify: `PushupCounter/Views/History/DayDetailView.swift`

Note: CardExporter already exists from Task 9, so DayDetailView is written with both image and video export from the start.

- [ ] **Step 1: Update TodayView to show DailyCardView**

Replace the `body` property in `PushupCounter/Views/Today/TodayView.swift` (keep `ensureTodayRecord()` and all state properties unchanged):

```swift
var body: some View {
    NavigationStack {
        if let todayRecord {
            ScrollView {
                VStack(spacing: 24) {
                    if todayRecord.totalPushups > 0 {
                        DailyCardView(record: todayRecord)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                    } else {
                        VStack(spacing: 12) {
                            Text("0")
                                .font(.system(size: 72, weight: .bold, design: .rounded))
                            Text("pushups today")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 60)
                    }

                    Spacer(minLength: 40)

                    Button {
                        showingSession = true
                    } label: {
                        Label("Start Pushups", systemImage: "play.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .fullScreenCover(isPresented: $showingSession) {
                PushupSessionView(dailyRecord: todayRecord)
            }
        } else {
            ProgressView()
        }
    }
    .navigationTitle("Today")
    .onAppear {
        ensureTodayRecord()
    }
    .onChange(of: allRecords) {
        ensureTodayRecord()
    }
}
```

- [ ] **Step 2: Update HistoryView to use CompactCardView**

In `PushupCounter/Views/History/HistoryView.swift`, replace the `Button` label content inside the `List`:

```swift
List(records) { record in
    Button {
        selectedRecord = record
    } label: {
        CompactCardView(record: record)
    }
    .foregroundStyle(.primary)
}
```

- [ ] **Step 3: Replace DayDetailView with card + share (image and video)**

Replace the entire contents of `PushupCounter/Views/History/DayDetailView.swift`:

```swift
import SwiftUI

struct DayDetailView: View {
    let record: DailyRecord
    @Environment(\.dismiss) private var dismiss
    @State private var isExportingVideo = false
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DailyCardView(record: record)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    // Share buttons
                    HStack(spacing: 12) {
                        Button {
                            if let image = CardExporter.exportImage(for: record) {
                                shareItems = [image]
                                showingShareSheet = true
                            }
                        } label: {
                            Label("Image", systemImage: "photo")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            isExportingVideo = true
                            Task {
                                do {
                                    let url = try await CardExporter.exportVideo(for: record)
                                    shareItems = [url]
                                    showingShareSheet = true
                                } catch {
                                    // Video export failed silently — image sharing still works
                                }
                                isExportingVideo = false
                            }
                        } label: {
                            Group {
                                if isExportingVideo {
                                    ProgressView()
                                } else {
                                    Label("Video", systemImage: "video")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isExportingVideo)
                    }
                    .padding(.horizontal, 16)

                    // Session breakdown
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sessions")
                            .font(.headline)
                            .padding(.horizontal, 16)

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
                                if let score = session.formScore {
                                    Text("\(Int(score))% form")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                let duration = session.endTime.timeIntervalSince(session.startTime)
                                Text(Duration.seconds(duration).formatted(.units(allowed: [.minutes, .seconds])))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
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
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: shareItems)
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

- [ ] **Step 4: Verify build succeeds**

Run: `xcodebuild build -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Run all tests**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add PushupCounter/Views/Today/TodayView.swift PushupCounter/Views/History/HistoryView.swift PushupCounter/Views/History/DayDetailView.swift
git commit -m "feat: integrate daily card views with sharing into Today, History, and DayDetail screens"
```

---

## Task 11: Update project.yml and regenerate Xcode project

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add AVFoundation dependency**

Since `project.yml` uses `sources: - PushupCounter` (the whole directory), all new Swift files are picked up automatically. The only change needed is adding the `AVFoundation` framework dependency for video export.

In `project.yml`, add to the PushupCounter target dependencies:

```yaml
    dependencies:
      - sdk: ARKit.framework
      - sdk: RealityKit.framework
      - sdk: AVFoundation.framework
```

- [ ] **Step 2: Regenerate Xcode project**

Run: `xcodegen generate` (from project root)
Expected: "Generated project: PushupCounter.xcodeproj"

- [ ] **Step 3: Verify build succeeds**

Run: `xcodebuild build -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run all tests to confirm everything works end-to-end**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add project.yml PushupCounter.xcodeproj
git commit -m "chore: add AVFoundation dependency and regenerate Xcode project"
```
