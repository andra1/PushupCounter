# Social Leaderboard & Friends Feature — Design Spec

## Overview

Add social features to PushupCounter: a streak-based leaderboard among friends, an activity feed with emoji reactions, phone-number-based friend discovery, and Firebase backend for auth and data.

## Goals

- **Accountability:** Seeing friends' activity keeps users consistent
- **Competition:** Streak-based leaderboard drives daily engagement
- **Community:** Activity feed with reactions creates lightweight social encouragement

## Architecture

### Backend: Firebase (Denormalized Firestore)

The app is currently fully local (SwiftUI + SwiftData, no backend). This feature adds:

- **Firebase Auth** — phone number SMS verification for identity
- **Firestore** — denormalized document store for user profiles, friendships, activities
- **No Cloud Functions** — all logic runs client-side; can add later if needed

### Why Denormalized

Each user document contains pre-computed `currentStreak`, `todayPushups`, etc. so the leaderboard loads with a single batch read of friend user documents. No aggregation queries needed.

## Firestore Schema

### `users/{userId}`

| Field | Type | Description |
|-------|------|-------------|
| displayName | String | User-chosen display name |
| phoneHash | String | SHA256 of E.164 phone number |
| avatarURL | String? | Optional profile image URL |
| currentStreak | Int | Consecutive days with at least one session |
| longestStreak | Int | All-time best streak |
| lastActiveDate | Timestamp | Last date a session was completed |
| totalPushups | Int | Lifetime pushup count |
| todayPushups | Int | Today's pushup count |
| todayDate | String | YYYY-MM-DD, for resetting todayPushups |
| createdAt | Timestamp | Account creation date |

### `friendships/{id}`

| Field | Type | Description |
|-------|------|-------------|
| userIds | [String] | Sorted pair of user IDs |
| status | String | "pending" or "accepted" |
| requesterId | String | Who sent the request |
| createdAt | Timestamp | When request was created |

### `activities/{id}`

| Field | Type | Description |
|-------|------|-------------|
| userId | String | Who performed the activity |
| userName | String | Denormalized display name |
| type | String | "session" or "streak_milestone" |
| count | Int | Pushups in session, or streak day count |
| timestamp | Timestamp | When it happened |
| reactions | Map<String, [String]> | Emoji key → array of user IDs who reacted |

### `phoneIndex/{phoneHash}`

| Field | Type | Description |
|-------|------|-------------|
| userId | String | Maps phone hash to user ID |

## Authentication Flow

1. App launch → check Firebase Auth state → if no account, the Leaderboard and Friends tabs show a sign-in prompt (all 4 tabs are always visible)
2. User taps sign-in → phone number entry screen → Firebase Auth sends SMS code → user enters code
3. On first sign-in: create `users/{userId}` document and `phoneIndex/{phoneHash}` entry
4. Prompt user to set a display name (required, one-time)
5. Auth state persists locally — user stays signed in across launches

### Unauthenticated Experience

Users who haven't signed in see all 4 tabs. Today and History work fully offline as before. Leaderboard and Friends tabs show a centered sign-in prompt: "Sign in to connect with friends" with a "Sign In" button. No social data is fetched until authenticated.

### Sign-Out

Available via a sign-out button on the Friends tab (or a future profile/settings screen). Signs out of Firebase Auth, clears cached social data, returns social tabs to the sign-in prompt. Local SwiftData session data is unaffected.

### Account Deletion

A "Delete Account" option (required by App Store guidelines) will be accessible from the same location as sign-out. Deletion is performed client-side as a best-effort batch operation:

1. Query `activities` where `userId == currentUserId`, delete all results
2. Query `friendships` where `userIds` contains `currentUserId`, delete all results
3. Delete `phoneIndex/{phoneHash}` document
4. Delete `users/{userId}` document
5. Delete Firebase Auth account

If the deletion is interrupted (e.g., user kills app mid-way), orphaned friendship or activity documents may remain. This is an accepted tradeoff — orphaned documents are harmless (they reference a non-existent user and will not appear in any friend's feed since the friendship is also being deleted). A future Cloud Function can perform periodic cleanup if needed.

The security rules allow users to delete their own activities (`allow delete: if userId == auth.uid`) and friendships they're part of (`allow update/delete: if auth.uid in userIds`).

Local SwiftData data is preserved (it's the user's own workout data).

## Friend Discovery Flow

1. User taps "Find Friends" → app requests Contacts permission
2. App reads phone contacts, normalizes to E.164 format, hashes each with SHA256
3. Batch query `phoneIndex` for matching hashes (Firestore `in` queries, batches of 30)
4. Display matched users with display names and current streaks
5. User taps "Add" → creates `friendships` document with `status: "pending"`
6. Recipient sees request in Friends tab → accepts or declines
7. On accept, `status` flips to `"accepted"`, both users appear on each other's leaderboards/feeds

### Privacy & Security

- Phone numbers stored as SHA256 hashes only — never raw
- Contacts permission is optional — app works without social features
- Only mutually accepted friends see each other's data
- **Firestore security rules** restrict `phoneIndex` reads to authenticated users only, preventing unauthenticated enumeration. Firebase App Check should be enabled to further limit access to legitimate app instances. The `phoneIndex` collection is query-only (no listing) — clients can only read documents by exact hash key, not scan the collection.

## Firestore Security Rules

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users: read own doc freely; friends can read profile fields
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }
    // Friendships: both users can read/delete; only involved users can write
    match /friendships/{docId} {
      allow read, delete: if request.auth != null && request.auth.uid in resource.data.userIds;
      allow create: if request.auth != null && request.auth.uid in request.resource.data.userIds;
      allow update: if request.auth != null && request.auth.uid in resource.data.userIds;
    }
    // Activities: authenticated users can read; only author creates; updates restricted to reactions
    match /activities/{docId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null && request.auth.uid == request.resource.data.userId;
      allow update: if request.auth != null
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['reactions']);
      allow delete: if request.auth != null && request.auth.uid == resource.data.userId;
    }
    // Phone index: authenticated users can read by exact doc ID; only owner can write/delete
    match /phoneIndex/{hash} {
      allow get: if request.auth != null;
      allow list: if false; // no collection scanning
      allow create: if request.auth != null && request.resource.data.userId == request.auth.uid;
      allow delete: if request.auth != null && resource.data.userId == request.auth.uid;
    }
  }
}
```

### Required Composite Indexes

The `activities` query (`userId in [...]`, `orderBy timestamp desc`) requires a Firestore composite index on `activities`: `userId` (ascending) + `timestamp` (descending). Create this in the Firebase console or via `firestore.indexes.json`.

## Navigation Changes

Current: 2 tabs (Today, History)
New: 4 tabs (Today, History, Leaderboard, Friends)

## Leaderboard Tab

**Layout:**
- Top 3 users displayed in a podium layout (gold/silver/bronze)
- Remaining users in a ranked list below
- Current user's row highlighted with accent color and always visible
- Each row: rank, avatar/initial, display name, streak count, flame icon if active today

**Ranking:**
- Primary sort: `currentStreak` descending
- Tiebreaker 1: `longestStreak` descending
- Tiebreaker 2: `totalPushups` descending

**Data fetching:**
1. On tab load, fetch current user's accepted friendship IDs
2. Batch fetch friend user documents from `users/` collection (batched in groups of 30 for Firestore `in` query limit, same as activity feed)
3. Sort client-side by streak
4. Pull-to-refresh to reload

**Empty state:** "Add friends to see the leaderboard" with Find Friends button

## Friends Tab

**Layout:**
- Top: Friend request banner (visible only when pending requests exist) with accept/decline
- Main: Activity feed sorted by timestamp descending
- Each item: avatar/initial, name, activity description, relative timestamp, reaction bar
- "Find Friends" button in navigation bar

**Activity types:**
- Session completion: "Sam did 30 pushups"
- Streak milestone: "Alex hit a 28-day streak!"

**Reactions:**
- 4 emoji reactions per activity item: 🔥 👏 💪 💯
- Tap to toggle your reaction; shows count when others have reacted
- Stored as a map in the activity document: `{ "🔥": ["userId1", "userId2"], "👏": ["userId3"] }`

**Data fetching:**
1. Query `activities` where `userId` in friend list, ordered by `timestamp` desc, limit 50. Firestore `in` queries support max 30 values — if the user has more than 30 friends, batch into groups of 30, query each batch, merge results client-side, and sort by timestamp. Same batching applies to leaderboard user document fetches.
2. Query `friendships` for pending requests where current user is recipient
3. Pull-to-refresh to reload

**Empty state:** "Find friends from your contacts and cheer each other on" with Find Friends button

## Streak Calculation

Performed client-side when saving a session. All date comparisons use the **device's local calendar day** (via `Calendar.current`). The authoritative date is the local session start time from SwiftData, not the Firestore server timestamp.

```
let sessionDay = Calendar.current.startOfDay(for: session.startTime)
let lastDay = Calendar.current.startOfDay(for: lastActiveDate)

if lastDay == yesterday(of: sessionDay):
    currentStreak += 1
elif lastDay == sessionDay:
    no change (already counted today)
else:
    currentStreak = 1  // streak broken, restart

lastActiveDate = sessionDay
longestStreak = max(longestStreak, currentStreak)
```

The `todayPushups` field resets when `todayDate` (YYYY-MM-DD in device local timezone) doesn't match the current local date. The reset check happens when saving a session (inside `SyncManager`), not on app launch or tab load.

### Streak Integrity

Streaks are computed and written client-side with no server-side validation. This means a technically savvy user could write arbitrary streak values to their own Firestore document. **This is an accepted tradeoff** — the app has no Cloud Functions, and among-friends leaderboards have low incentive for cheating. If integrity becomes a concern, a Cloud Function can be added later to validate streak writes against the user's activity history.

## Activity Creation

When a pushup session is saved to SwiftData:
1. Update `users/{userId}`: increment `todayPushups`, recalculate streak, update `lastActiveDate`
2. Create `activities` document with type "session" and the pushup count
3. If streak hits a milestone (7, 14, 21, 30, 60, 90, 120, 180, 365 days), also create a "streak_milestone" activity

## Data Sync

- **Pull-to-refresh** on both Leaderboard and Friends tabs
- Data loads when tab appears and on manual refresh
- No real-time Firestore listeners (keeps costs low)
- Local SwiftData remains the source of truth for the user's own session data; Firestore is the social layer

## New Swift Files & Services

### Services
- `FirebaseAuthManager` — phone auth sign-in/sign-out, current user state
- `FirestoreService` — CRUD for users, friendships, activities, phone index
- `ContactsManager` — reads phone contacts, normalizes numbers, hashes for lookup
- `SyncManager` — coordinates pushing local session data to Firestore after each session

### Models (Codable, not SwiftData)
- `UserProfile` — maps to `users/` document
- `Friendship` — maps to `friendships/` document
- `Activity` — maps to `activities/` document

### Views
- `LeaderboardView` — podium + ranked list
- `FriendsView` — activity feed + friend requests
- `FriendRequestBanner` — accept/decline UI
- `ActivityFeedItem` — single feed item with reactions
- `FindFriendsView` — contact matching results with add buttons
- `PhoneAuthView` — phone number entry + SMS code verification
- `DisplayNameView` — one-time name setup

## Dependencies

New dependency: **Firebase iOS SDK** (firebase-ios-sdk Swift Package)
- FirebaseAuth
- FirebaseFirestore

Added to `project.yml` via XcodeGen SPM syntax:

```yaml
packages:
  Firebase:
    url: https://github.com/firebase/firebase-ios-sdk
    minorVersion: "11.0.0"

# Under PushupCounter target dependencies:
dependencies:
  - package: Firebase
    product: FirebaseAuth
  - package: Firebase
    product: FirebaseFirestore
```

Also requires a `GoogleService-Info.plist` file from the Firebase console, added to the PushupCounter target sources.

## Testing Strategy

- Unit tests for `SyncManager` streak calculation logic (mock Firestore)
- Unit tests for phone number normalization and hashing in `ContactsManager`
- Unit tests for leaderboard sorting logic
- Integration tests for Firestore read/write can use Firebase emulator locally
