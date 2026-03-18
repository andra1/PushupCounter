# Daily Pushup Card — Design Spec

## Overview

A shareable daily summary card that visualizes pushup effort, with an animated form quality ring as the visual centerpiece. The card shows in-app (TodayView, HistoryView) and exports as a short animated video or static image for social sharing.

The form quality ring serves the same role as Strava's route map — a distinctive, glanceable visual that's unique to each day and immediately communicates effort.

## Current Detection Architecture

The app uses **ARKit body tracking** (not Vision framework). `ARSessionManager` runs an `ARBodyTrackingConfiguration`, receives `ARBodyAnchor` updates, and passes `bodyAnchor.transform.columns.3.y` (hip height) to `PushupDetector`. The detector uses hip height drop from a calibrated baseline to determine up/down state (drop > 0.15 = down, drop < 0.05 = up) with 3-frame debounce.

Key: `ARBodyAnchor` also provides a full body skeleton via `bodyAnchor.skeleton`, which includes joint positions for shoulders, elbows, and wrists. We can extract elbow angles from the same anchor data without adding any new tracking system.

## Form Quality Metric

**Definition:** Percentage of reps with full range of motion.

A rep has full range of motion when:
- `minElbowAngle < 90°` (arms bent deep enough at the bottom)
- `maxElbowAngle > 160°` (arms fully extended at the top)

**Elbow angle extraction:** Computed from three ARKit 3D body skeleton joints per arm, accessed via string-based joint names on `bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue:))`:
- Left: `"left_shoulder_1_joint"` (shoulder), `"left_forearm_joint"` (elbow), `"left_hand_joint"` (wrist)
- Right: `"right_shoulder_1_joint"` (shoulder), `"right_forearm_joint"` (elbow), `"right_hand_joint"` (wrist)

Note: These are string identifiers from `ARSkeletonDefinition.defaultBody3D`, not the limited `ARSkeleton.JointName` static properties which don't include forearm.

Joint positions are 3D (`simd_float4x4` model transforms). Since pushups happen in a roughly 2D plane (sagittal), project to 2D by taking the X and Y components of each joint's translation column (`columns.3.x`, `columns.3.y`), then pass as `CGPoint` to the existing `AngleCalculator.angle(a:b:c:)`.

**Detecting untracked joints:** `modelTransform(for:)` returns the identity matrix for untracked joints. Check by comparing `transform.columns.3` to `(0, 0, 0, 1)`.

**Arm averaging:** `ARSessionManager` computes both left and right elbow angles. If both are tracked, pass the average. If only one arm's joints are tracked, use that one. If neither is available, pass `nil` for `elbowAngle`.

**Score calculation:**
- Per-session: `(reps with full ROM / total reps) * 100`
- Per-day: weighted average across sessions, weighted by rep count

## Data Model Changes

### PushupSession (modified)

Add one new persisted field:

```swift
@Attribute var repAnglesData: Data? // JSON-encoded [RepAngle], nil for sessions recorded before this feature
```

Add a helper struct and computed properties:

```swift
struct RepAngle: Codable {
    let minAngle: Double
    let maxAngle: Double
}

var repAngles: [RepAngle]  // decoded from repAnglesData, empty if nil
var formScore: Double?      // nil if repAnglesData is nil (legacy session), otherwise % of reps with full ROM
```

**Storage cost:** ~64 bytes per rep (two Doubles). A 50-rep session adds ~3KB.

**Migration:** The field is optional (`Data?`). Existing sessions will have `nil`, and `formScore` returns `nil` for them. No SwiftData migration needed.

### DailyRecord (modified)

Add one computed property:

```swift
var formScore: Double?  // weighted average of session form scores (only sessions that have angle data), nil if no sessions have data
```

No new persisted fields on DailyRecord.

### ARSessionManager (modified)

Extract elbow angle from skeleton joints alongside hip height:

- In `session(_:didUpdate:)`, after extracting `hipHeight` from `bodyAnchor.transform.columns.3.y`:
  1. Get the skeleton's model transforms for left and right arm joints using `bodyAnchor.skeleton.modelTransform(for:)`
  2. Project 3D positions to 2D (`CGPoint` from `columns.3.x` and `columns.3.y`)
  3. Compute elbow angle for each arm via `AngleCalculator.angle(a: shoulder, b: elbow, c: wrist)`
  4. Average the two angles (or use single arm if only one is tracked — `modelTransform(for:)` returns the identity matrix for untracked joints, so check for this)
  5. Pass both `hipHeight` and `elbowAngle: Double?` to `PushupDetector.processFrame(hipHeight:elbowAngle:)`

### PushupDetector (modified)

Accept elbow angle alongside hip height. Track per-rep angle extremes:

- Change `processHipHeight(_ height: Float?)` → `processFrame(hipHeight: Float?, elbowAngle: Double?)`. Only callsite is `ARSessionManager.session(_:didUpdate:)` — update there simultaneously.
- New properties: `currentRepMinAngle: Double`, `currentRepMaxAngle: Double`, `completedRepAngles: [RepAngle]`
- On each frame with a valid elbow angle: track running min/max for the current rep
- On rep completion (DOWN → UP transition): append `RepAngle(minAngle, maxAngle)` to `completedRepAngles`, reset tracking min/max
- Expose `completedRepAngles` for the session view to read on save
- `reset()` also clears angle tracking state

### PushupSessionView (modified)

When the user taps "Done":
- Read `completedRepAngles` from the detector
- Encode to JSON `Data` via `JSONEncoder` and set on `PushupSession.repAnglesData`. If encoding fails (shouldn't happen with simple Codable structs), save the session without angle data (`repAnglesData = nil`) — the pushup count is always more important than form tracking.
- Save as part of the existing SwiftData save flow

## Card Design

### Layout (dark theme)

```
┌──────────────────────────────────┐
│  Wednesday                       │
│  March 18, 2026    PUSHUP COUNTER│
│                                  │
│          ┌─────────┐             │
│          │  ╭───╮  │             │
│          │  │80%│  │             │
│          │  ╰───╯  │             │
│          │  FORM   │             │
│          └─────────┘             │
│    Form Quality Ring (animated)  │
│                                  │
│ ─────────────────────────────── │
│    47          3         4:32    │
│  PUSHUPS     SETS        TIME   │
│ ─────────────────────────────── │
│                                  │
│   [SET 1: 20] [SET 2: 15] [SET 3: 12] │
└──────────────────────────────────┘
```

### Visual Details

- **Background:** dark gradient (`#0f0f1a` → `#1a1a2e`)
- **Form quality ring:** circular progress indicator, the hero element
  - Green/cyan gradient for good form (≥70%)
  - Amber for moderate form (40-70%)
  - Red for poor form (<40%)
  - Percentage displayed in center, large bold text
- **Stats row:** three columns — total pushups, number of sets, total active time
- **Set chips:** small rounded rectangles at the bottom, one per session, showing count. Chip color reflects that session's form score (green/amber/red).

## Animation (for export)

~3 second animation sequence:

1. **Ring fills** from 0% to actual score (~1.2s), percentage number counts up in sync
2. **Stats fade in** with subtle stagger (~0.5s)
3. **Set chips slide in** from bottom (~0.3s)
4. **Hold** final state (~1s)

## Export & Sharing

### Formats
- **Animated video (MP4):** rendered via Core Animation snapshotting. ~3 seconds.
- **Static image (PNG):** snapshot of the final state

### Sharing mechanism
- Share button on the full card triggers `UIActivityViewController`
- Works with iMessage, Instagram Stories, Snapchat, etc.

### Implementation: CardExporter service
- Takes a `DailyRecord` and renders the `DailyCardView` offscreen
- For video: captures the animation frame-by-frame using `UIGraphicsImageRenderer` and encodes with `AVAssetWriter`
- For image: single snapshot render

## Where It Lives in the App

### TodayView (modified)
- The card replaces the current plain number display
- Full card is the main content when sessions exist for today
- "Start Pushups" button remains below the card

### HistoryView (modified)
- Each day shows a compact card variant: smaller ring + key stats inline
- Tapping opens the full card in `DayDetailView`

### DayDetailView (modified)
- Shows the full card at the top
- Share button triggers export
- Session breakdown list remains below

## New Files

| File | Purpose |
|------|---------|
| `Views/Card/DailyCardView.swift` | The card SwiftUI view with ring animation |
| `Views/Card/FormQualityRingView.swift` | The animated circular progress ring |
| `Views/Card/CompactCardView.swift` | Smaller card variant for history list |
| `Services/CardExporter.swift` | Renders card to video/image for sharing |

## Files Modified

| File | Changes |
|------|---------|
| `Models/PushupSession.swift` | Add `repAnglesData`, `RepAngle` struct, `formScore` computed property |
| `Models/DailyRecord.swift` | Add `formScore` computed property |
| `Services/ARSessionManager.swift` | Extract elbow angle from skeleton joints, pass to detector |
| `Services/PushupDetector.swift` | Accept elbow angle, track per-rep min/max, expose `completedRepAngles` |
| `Views/Today/TodayView.swift` | Replace plain number with `DailyCardView` |
| `Views/History/HistoryView.swift` | Use `CompactCardView` for each day |
| `Views/History/DayDetailView.swift` | Add full card + share button |
| `Views/Session/PushupSessionView.swift` | Read `completedRepAngles` from detector and persist on save |

## Out of Scope

- Historical form quality trends / graphs
- Per-rep detailed breakdown view
- Customizable card themes or colors
- Sharing to specific platforms (just using system share sheet)
