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

1. App launch → check Firebase Auth state → if no account, show phone sign-in screen
2. Firebase Auth sends SMS verification code → user enters code
3. On first sign-in: create `users/{userId}` document and `phoneIndex/{phoneHash}` entry
4. Prompt user to set a display name (required, one-time)
5. Auth state persists locally — user stays signed in across launches

## Friend Discovery Flow

1. User taps "Find Friends" → app requests Contacts permission
2. App reads phone contacts, normalizes to E.164 format, hashes each with SHA256
3. Batch query `phoneIndex` for matching hashes (Firestore `in` queries, batches of 30)
4. Display matched users with display names and current streaks
5. User taps "Add" → creates `friendships` document with `status: "pending"`
6. Recipient sees request in Friends tab → accepts or declines
7. On accept, `status` flips to `"accepted"`, both users appear on each other's leaderboards/feeds

### Privacy

- Phone numbers stored as SHA256 hashes only — never raw
- Contacts permission is optional — app works without social features
- Only mutually accepted friends see each other's data

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
2. Batch fetch friend user documents from `users/` collection
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
1. Query `activities` where `userId` in friend list, ordered by `timestamp` desc, limit 50
2. Query `friendships` for pending requests where current user is recipient
3. Pull-to-refresh to reload

**Empty state:** "Find friends from your contacts and cheer each other on" with Find Friends button

## Streak Calculation

Performed client-side when saving a session:

```
if lastActiveDate == yesterday:
    currentStreak += 1
elif lastActiveDate == today:
    no change (already counted today)
else:
    currentStreak = 1  // streak broken, restart

lastActiveDate = today
longestStreak = max(longestStreak, currentStreak)
```

## Activity Creation

When a pushup session is saved to SwiftData:
1. Update `users/{userId}`: increment `todayPushups`, recalculate streak, update `lastActiveDate`
2. Create `activities` document with type "session" and the pushup count
3. If streak hits a milestone (7, 14, 21, 30, 60, 90, etc.), also create a "streak_milestone" activity

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

Added to `project.yml` as a Swift Package Manager dependency.

## Testing Strategy

- Unit tests for `SyncManager` streak calculation logic (mock Firestore)
- Unit tests for phone number normalization and hashing in `ContactsManager`
- Unit tests for leaderboard sorting logic
- Integration tests for Firestore read/write can use Firebase emulator locally
