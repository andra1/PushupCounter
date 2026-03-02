# PushupCounter iOS App — Design Document

**Date:** 2026-03-02
**Status:** Approved

## Overview

An iOS app that uses the device camera and Apple's Vision framework to count pushups in real-time. Users set a daily pushup goal, and until they meet it, their selected social media apps are blocked at the OS level via Apple's Screen Time API (FamilyControls / ManagedSettings).

**Target audience:** General consumers (including beginners)
**Platform:** iOS 16+ (required for Screen Time API)
**Tech stack:** Swift + SwiftUI

## Architecture

### Xcode Targets

1. **PushupCounter** (main app) — All UI, camera capture, Vision pose detection, pushup counting, goal tracking, and ManagedSettingsStore management
2. **ShieldConfigurationExtension** — Customizes the blocked-app screen with a motivational message and deep-link to the main app
3. **DeviceActivityMonitorExtension** — Monitors the daily schedule and re-applies shields at midnight

### Key Frameworks

| Framework | Purpose |
|-----------|---------|
| `AVFoundation` | Camera capture session for live video feed |
| `Vision` | `VNDetectHumanBodyPoseRequest` for real-time body pose detection |
| `FamilyControls` | Authorization + `FamilyActivityPicker` for app selection |
| `ManagedSettings` | `ManagedSettingsStore` to apply/remove app shields |
| `DeviceActivity` | Schedule-based monitoring (daily reset at midnight) |
| `SwiftData` | Local persistence for goals, history, settings |

### Data Flow

```
Camera → AVCaptureSession → Vision Pose Detection → Pushup Counter Logic → Goal Check → ManagedSettingsStore (unshield apps)
```

## Pushup Detection Engine

### Body Pose Tracking

- Camera captures frames at ~30fps via `AVCaptureSession`
- Each frame is processed by `VNDetectHumanBodyPoseRequest`, returning 19 body joint positions
- Key joints tracked: shoulder, elbow, and wrist on both arms
- Only accept joint detections with confidence > 0.6

### Pushup State Machine

```
                    elbow angle < 90°
    ┌─────────┐  ──────────────────►  ┌──────────┐
    │   UP    │                       │   DOWN   │
    │ (arms   │  ◄──────────────────  │ (arms    │
    │extended)│   elbow angle > 160°  │  bent)   │
    └─────────┘   COUNT += 1          └──────────┘
```

- **UP state:** Arms extended (elbow angle > 160°)
- **DOWN state:** Arms bent (elbow angle < 90°)
- **A rep counts** on DOWN → UP transition (completing the push back up)
- **Debounce:** State must be held for 3+ consecutive frames before transitioning

### Real-time Feedback

- Large pushup count overlay on camera preview
- Visual UP/DOWN state indicator
- Optional audio "ding" on each completed rep (toggleable)
- Progress bar showing count vs. daily goal

### Edge Cases

- Person out of frame → pause counting, show "Get back in frame"
- Low confidence → ignore frame
- Too fast movement → debounce prevents double-counting
- Supports portrait and landscape (recommend landscape for best detection)
- Multiple people → use highest-confidence body pose

## Screen Time / App Blocking

### Authorization Flow

1. Request `FamilyControls` authorization via `AuthorizationCenter.shared.requestAuthorization(for: .individual)`
2. System shows "Allow Screen Time access" prompt
3. Present `FamilyActivityPicker` for user to select apps to block

### Daily Blocking Lifecycle

```
Midnight (00:00)
    │
    ▼
Apps BLOCKED (ManagedSettingsStore shield applied)
    │
    ▼
User completes pushup session → reaches daily goal
    │
    ▼
Apps UNBLOCKED (ManagedSettingsStore shield removed)
    │
    ▼
Midnight → cycle repeats
```

### Implementation

- **Blocking:** `store.shield.applications = selectedApps`
- **Unblocking:** `store.shield.applications = nil`
- **Daily reset:** `DeviceActivityMonitor` extension's `intervalDidStart()` re-applies shields at midnight
- **Custom shield screen:** Shows "Do your pushups first!" with button to open PushupCounter app
- Shield state persists across app kills and reboots (OS-managed)

### Constraints

- Requires iOS 16+
- `FamilyControls` entitlement must be requested from Apple (restricted entitlement)
- Cannot block itself
- Selected apps stored as opaque `ApplicationToken` objects

## Data Model (SwiftData)

```swift
@Model
class UserSettings {
    var dailyGoal: Int              // e.g., 30
    var selectedApps: Data          // Encoded FamilyActivitySelection
    var soundEnabled: Bool
    var hasCompletedOnboarding: Bool
}

@Model
class DailyRecord {
    var date: Date                  // Calendar date (midnight-aligned)
    var totalPushups: Int           // Cumulative count for the day
    var goalMet: Bool
    var sessions: [PushupSession]
}

@Model
class PushupSession {
    var startTime: Date
    var endTime: Date
    var count: Int
    var dailyRecord: DailyRecord?
}
```

- Multiple sessions per day allowed
- Goal checked after each session: `if totalPushups >= dailyGoal → unblock`
- History kept indefinitely for stats/streak view

### Derived Stats

- Current streak (consecutive days goal met)
- Total pushups all-time
- Average pushups per day
- Best streak

## UI Screens & Navigation

### Navigation Structure

Tab bar with 3 tabs: **Today** | **History** | **Settings**

### Screen Flow

```
Onboarding (3 steps) → Today Dashboard → Pushup Session
                              │
                       ┌──────┼──────┐
                       ▼      ▼      ▼
                    History  Stats  Settings
```

### Screens

**1. Onboarding (shown once):**
- Step 1: Welcome screen explaining the concept
- Step 2: Set daily pushup goal (number picker)
- Step 3: Grant Screen Time permission + select apps to block

**2. Today Dashboard (main screen):**
- Circular progress ring: pushups done / goal
- Lock status: "Locked" or "Unlocked" with clear visual
- Big "Start Pushups" button
- Current streak display

**3. Pushup Session:**
- Full-screen camera preview
- Large pushup count overlay (top center)
- Progress bar toward daily goal
- "Done" button to end early
- Celebration animation when goal reached

**4. History:**
- Calendar view: green (goal met) / red (missed) / gray (no data)
- Tap day for session details

**5. Settings:**
- Change daily goal
- Edit blocked apps (re-show FamilyActivityPicker)
- Toggle sound effects
- Reset all data

## Error Handling & Edge Cases

| Scenario | Handling |
|----------|----------|
| Screen Time permission denied | Explanation screen with re-request button. Counting works but blocking disabled. |
| Camera permission denied | Explanation + Settings deep-link. Cannot start session. |
| No body detected | Overlay "Position yourself in view". Pause counting. |
| App killed mid-session | Partial session saved. User starts new session to continue. |
| Date/time manipulation | Validate against last known date. DeviceActivity schedule is tamper-resistant. |
| App deleted and reinstalled | Must re-authorize. History lost. Shields cleared. |
| Multiple people in frame | Use highest-confidence body pose. |
| App backgrounded during session | Camera stops. Show "Session paused" on return. |

## Non-Requirements (Explicit Exclusions)

- No backend / server
- No user accounts or authentication
- No cloud sync
- No video saving or recording
- No social features / leaderboards
- No Apple Watch support
- No widgets (can be added later)

## Privacy

- All processing on-device
- No data leaves the device
- No video is saved
- Camera frames are processed in memory and discarded
- Only pushup counts and dates are persisted
