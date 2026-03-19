# Social Leaderboard & Friends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add social features — Firebase auth, streak leaderboard, activity feed with reactions, and phone-contact friend discovery — to the PushupCounter iOS app.

**Architecture:** Firebase Auth (phone number) + Firestore (denormalized) backend. All social logic runs client-side. Local SwiftData remains source of truth for workout data; Firestore is the social layer. Pull-to-refresh data loading, no real-time listeners.

**Tech Stack:** SwiftUI, SwiftData, Firebase Auth, Firebase Firestore, Contacts framework, CryptoKit (SHA256)

**Spec:** `docs/superpowers/specs/2026-03-18-social-leaderboard-design.md`

---

## File Map

### New Files — Models (Codable)
- `PushupCounter/Models/UserProfile.swift` — Firestore `users/` document model
- `PushupCounter/Models/Friendship.swift` — Firestore `friendships/` document model
- `PushupCounter/Models/Activity.swift` — Firestore `activities/` document model

### New Files — Services
- `PushupCounter/Services/FirebaseAuthManager.swift` — Phone auth, sign-in/out, current user state
- `PushupCounter/Services/FirestoreService.swift` — All Firestore CRUD (users, friendships, activities, phoneIndex)
- `PushupCounter/Services/ContactsManager.swift` — Read contacts, normalize E.164, SHA256 hash
- `PushupCounter/Services/SyncManager.swift` — Push session data to Firestore, streak calculation

### New Files — Views
- `PushupCounter/Views/Auth/PhoneAuthView.swift` — Phone number + SMS code entry
- `PushupCounter/Views/Auth/DisplayNameView.swift` — One-time name setup after first sign-in
- `PushupCounter/Views/Auth/SignInPromptView.swift` — Placeholder for unauthenticated social tabs
- `PushupCounter/Views/Leaderboard/LeaderboardView.swift` — Podium + ranked list
- `PushupCounter/Views/Leaderboard/PodiumView.swift` — Top 3 podium component
- `PushupCounter/Views/Leaderboard/LeaderboardRow.swift` — Single rank row
- `PushupCounter/Views/Friends/FriendsView.swift` — Activity feed + friend requests
- `PushupCounter/Views/Friends/ActivityFeedItem.swift` — Single feed item with reactions
- `PushupCounter/Views/Friends/FriendRequestBanner.swift` — Accept/decline UI
- `PushupCounter/Views/Friends/FindFriendsView.swift` — Contact matching results
- `PushupCounter/Views/Friends/ReactionBar.swift` — Emoji reaction row component

### Modified Files
- `project.yml` — Add Firebase SPM packages
- `PushupCounter/PushupCounterApp.swift` — Firebase initialization, inject AuthManager
- `PushupCounter/ContentView.swift` — Add Leaderboard + Friends tabs
- `PushupCounter/Views/Session/PushupSessionView.swift` — Call SyncManager after saving session

### New Test Files
- `PushupCounterTests/SyncManagerTests.swift` — Streak calculation logic
- `PushupCounterTests/ContactsManagerTests.swift` — Phone normalization + hashing
- `PushupCounterTests/LeaderboardSortTests.swift` — Ranking sort logic

### Firebase Config (manual)
- `PushupCounter/GoogleService-Info.plist` — Downloaded from Firebase console (not code-generated)

---

## Task 1: Add Firebase SDK dependency

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add Firebase packages to project.yml**

Add the `packages` block at the top level and Firebase dependencies under the PushupCounter target. Insert after line 9 (after `settings:` block, before `targets:`):

```yaml
packages:
  Firebase:
    url: https://github.com/firebase/firebase-ios-sdk
    minorVersion: "11.0.0"
```

Under `PushupCounter` target `dependencies` (after the existing `sdk` entries at line 35):

```yaml
      - package: Firebase
        product: FirebaseAuth
      - package: Firebase
        product: FirebaseFirestore
```

Also add `NSContactsUsageDescription` to Info.plist properties (after the `NSCameraUsageDescription` entry):

```yaml
        NSContactsUsageDescription: "PushupCounter uses your contacts to find friends who also use the app."
```

- [ ] **Step 2: Regenerate Xcode project**

Run: `cd /Users/kaushikandra/PushupCounter && xcodegen generate`
Expected: Project generated successfully.

- [ ] **Step 3: Verify build resolves packages**

Run: `xcodebuild -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -resolvePackageDependencies`
Expected: Firebase packages resolve successfully.

- [ ] **Step 4: Add placeholder GoogleService-Info.plist**

Create `PushupCounter/GoogleService-Info.plist` with placeholder structure. This file must be replaced with the real one from Firebase console before the app will work, but having the placeholder ensures the project compiles:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>API_KEY</key>
    <string>PLACEHOLDER</string>
    <key>GCM_SENDER_ID</key>
    <string>PLACEHOLDER</string>
    <key>PLIST_VERSION</key>
    <string>1</string>
    <key>BUNDLE_ID</key>
    <string>com.pushupcounter.app</string>
    <key>PROJECT_ID</key>
    <string>PLACEHOLDER</string>
    <key>STORAGE_BUCKET</key>
    <string>PLACEHOLDER</string>
    <key>GOOGLE_APP_ID</key>
    <string>PLACEHOLDER</string>
</dict>
</plist>
```

- [ ] **Step 5: Commit**

```bash
git add project.yml PushupCounter/GoogleService-Info.plist
git commit -m "feat: add Firebase SDK dependency and contacts permission"
```

---

## Task 2: Create Codable models (UserProfile, Friendship, Activity)

**Files:**
- Create: `PushupCounter/Models/UserProfile.swift`
- Create: `PushupCounter/Models/Friendship.swift`
- Create: `PushupCounter/Models/Activity.swift`

- [ ] **Step 1: Create UserProfile model**

```swift
// PushupCounter/Models/UserProfile.swift
import Foundation
import FirebaseFirestore

struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String?
    var displayName: String
    var phoneHash: String
    var avatarURL: String?
    var currentStreak: Int
    var longestStreak: Int
    var lastActiveDate: Date
    var totalPushups: Int
    var todayPushups: Int
    var todayDate: String  // YYYY-MM-DD in device local timezone
    var createdAt: Date

    static let streakMilestones: Set<Int> = [7, 14, 21, 30, 60, 90, 120, 180, 365]
}
```

- [ ] **Step 2: Create Friendship model**

```swift
// PushupCounter/Models/Friendship.swift
import Foundation
import FirebaseFirestore

struct Friendship: Codable, Identifiable {
    @DocumentID var id: String?
    var userIds: [String]
    var status: String  // "pending" or "accepted"
    var requesterId: String
    var createdAt: Date

    var isPending: Bool { status == "pending" }
    var isAccepted: Bool { status == "accepted" }

    func otherUserId(currentUserId: String) -> String? {
        userIds.first { $0 != currentUserId }
    }
}
```

- [ ] **Step 3: Create Activity model**

```swift
// PushupCounter/Models/Activity.swift
import Foundation
import FirebaseFirestore

struct Activity: Codable, Identifiable {
    @DocumentID var id: String?
    var userId: String
    var userName: String
    var type: String  // "session" or "streak_milestone"
    var count: Int
    var timestamp: Date
    var reactions: [String: [String]]  // emoji -> [userId]

    var isSession: Bool { type == "session" }
    var isStreakMilestone: Bool { type == "streak_milestone" }

    static let reactionEmojis = ["🔥", "👏", "💪", "💯"]
}
```

- [ ] **Step 4: Commit**

```bash
git add PushupCounter/Models/UserProfile.swift PushupCounter/Models/Friendship.swift PushupCounter/Models/Activity.swift
git commit -m "feat: add Codable models for Firestore (UserProfile, Friendship, Activity)"
```

---

## Task 3: Implement FirebaseAuthManager

**Files:**
- Create: `PushupCounter/Services/FirebaseAuthManager.swift`
- Modify: `PushupCounter/PushupCounterApp.swift`

- [ ] **Step 1: Create FirebaseAuthManager**

```swift
// PushupCounter/Services/FirebaseAuthManager.swift
import Foundation
import Observation
import FirebaseAuth

@MainActor
@Observable
final class FirebaseAuthManager {
    private(set) var currentUser: User?
    private(set) var isSignedIn: Bool = false
    private(set) var verificationId: String?
    private(set) var isLoading: Bool = false
    private(set) var error: String?

    init() {
        self.currentUser = Auth.auth().currentUser
        self.isSignedIn = currentUser != nil
    }

    func sendVerificationCode(phoneNumber: String) async {
        isLoading = true
        error = nil
        do {
            let id = try await PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil)
            verificationId = id
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func verifyCode(_ code: String) async -> Bool {
        guard let verificationId else {
            error = "No verification ID. Request a code first."
            return false
        }
        isLoading = true
        error = nil
        do {
            let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationId, verificationCode: code)
            let result = try await Auth.auth().signIn(with: credential)
            currentUser = result.user
            isSignedIn = true
            isLoading = false
            return true
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return false
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            currentUser = nil
            isSignedIn = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteAccount() async {
        do {
            try await currentUser?.delete()
            currentUser = nil
            isSignedIn = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Update PushupCounterApp.swift to initialize Firebase and inject AuthManager**

Replace the full content of `PushupCounterApp.swift`:

```swift
// PushupCounter/PushupCounterApp.swift
import SwiftUI
import SwiftData
import FirebaseCore

@main
struct PushupCounterApp: App {
    @State private var authManager = FirebaseAuthManager()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
        }
        .modelContainer(for: [DailyRecord.self, PushupSession.self])
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add PushupCounter/Services/FirebaseAuthManager.swift PushupCounter/PushupCounterApp.swift
git commit -m "feat: add FirebaseAuthManager with phone auth and Firebase init"
```

---

## Task 4: Implement FirestoreService

**Files:**
- Create: `PushupCounter/Services/FirestoreService.swift`

- [ ] **Step 1: Create FirestoreService with all CRUD operations**

```swift
// PushupCounter/Services/FirestoreService.swift
import Foundation
import FirebaseFirestore

final class FirestoreService {
    private let db = Firestore.firestore()

    // MARK: - Users

    func createUser(_ profile: UserProfile, userId: String) async throws {
        try db.collection("users").document(userId).setData(from: profile)
    }

    func getUser(userId: String) async throws -> UserProfile? {
        let doc = try await db.collection("users").document(userId).getDocument()
        return try? doc.data(as: UserProfile.self)
    }

    func updateUser(userId: String, fields: [String: Any]) async throws {
        try await db.collection("users").document(userId).updateData(fields)
    }

    func deleteUser(userId: String) async throws {
        try await db.collection("users").document(userId).delete()
    }

    func batchGetUsers(userIds: [String]) async throws -> [UserProfile] {
        var results: [UserProfile] = []
        // Firestore `in` queries limited to 30 values
        for batch in userIds.chunked(into: 30) {
            let snapshot = try await db.collection("users")
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments()
            let users = snapshot.documents.compactMap { try? $0.data(as: UserProfile.self) }
            results.append(contentsOf: users)
        }
        return results
    }

    // MARK: - Phone Index

    func createPhoneIndex(phoneHash: String, userId: String) async throws {
        try await db.collection("phoneIndex").document(phoneHash).setData(["userId": userId])
    }

    func deletePhoneIndex(phoneHash: String) async throws {
        try await db.collection("phoneIndex").document(phoneHash).delete()
    }

    func lookupPhoneHashes(_ hashes: [String]) async throws -> [String: String] {
        var results: [String: String] = [:]  // phoneHash -> userId
        for batch in hashes.chunked(into: 30) {
            let snapshot = try await db.collection("phoneIndex")
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments()
            for doc in snapshot.documents {
                if let userId = doc.data()["userId"] as? String {
                    results[doc.documentID] = userId
                }
            }
        }
        return results
    }

    // MARK: - Friendships

    func createFriendship(currentUserId: String, friendUserId: String) async throws {
        let sorted = [currentUserId, friendUserId].sorted()
        let friendship = Friendship(
            userIds: sorted,
            status: "pending",
            requesterId: currentUserId,
            createdAt: Date()
        )
        _ = try db.collection("friendships").addDocument(from: friendship)
    }

    func acceptFriendship(friendshipId: String) async throws {
        try await db.collection("friendships").document(friendshipId).updateData(["status": "accepted"])
    }

    func deleteFriendship(friendshipId: String) async throws {
        try await db.collection("friendships").document(friendshipId).delete()
    }

    func getAcceptedFriendships(userId: String) async throws -> [Friendship] {
        let snapshot = try await db.collection("friendships")
            .whereField("userIds", arrayContains: userId)
            .whereField("status", isEqualTo: "accepted")
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Friendship.self) }
    }

    func getPendingFriendRequests(userId: String) async throws -> [Friendship] {
        let snapshot = try await db.collection("friendships")
            .whereField("userIds", arrayContains: userId)
            .whereField("status", isEqualTo: "pending")
            .getDocuments()
        // Filter to requests where current user is NOT the requester
        return snapshot.documents
            .compactMap { try? $0.data(as: Friendship.self) }
            .filter { $0.requesterId != userId }
    }

    func getAllFriendships(userId: String) async throws -> [Friendship] {
        let snapshot = try await db.collection("friendships")
            .whereField("userIds", arrayContains: userId)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Friendship.self) }
    }

    // MARK: - Activities

    func createActivity(_ activity: Activity) async throws {
        _ = try db.collection("activities").addDocument(from: activity)
    }

    func getActivities(forUserIds userIds: [String], limit: Int = 50) async throws -> [Activity] {
        var results: [Activity] = []
        for batch in userIds.chunked(into: 30) {
            let snapshot = try await db.collection("activities")
                .whereField("userId", in: batch)
                .order(by: "timestamp", descending: true)
                .limit(to: limit)
                .getDocuments()
            let activities = snapshot.documents.compactMap { try? $0.data(as: Activity.self) }
            results.append(contentsOf: activities)
        }
        // Merge and sort across batches
        return results.sorted { $0.timestamp > $1.timestamp }.prefix(limit).map { $0 }
    }

    func toggleReaction(activityId: String, emoji: String, userId: String) async throws {
        let docRef = db.collection("activities").document(activityId)
        let doc = try await docRef.getDocument()
        guard var activity = try? doc.data(as: Activity.self) else { return }

        var reactors = activity.reactions[emoji] ?? []
        if reactors.contains(userId) {
            reactors.removeAll { $0 == userId }
        } else {
            reactors.append(userId)
        }
        activity.reactions[emoji] = reactors

        try await docRef.updateData(["reactions": activity.reactions])
    }

    func deleteActivities(forUserId userId: String) async throws {
        let snapshot = try await db.collection("activities")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add PushupCounter/Services/FirestoreService.swift
git commit -m "feat: add FirestoreService with full Firestore CRUD operations"
```

---

## Task 5: Implement ContactsManager

**Files:**
- Create: `PushupCounter/Services/ContactsManager.swift`
- Create: `PushupCounterTests/ContactsManagerTests.swift`

- [ ] **Step 1: Write failing tests for phone normalization and hashing**

```swift
// PushupCounterTests/ContactsManagerTests.swift
import XCTest
@testable import PushupCounter

final class ContactsManagerTests: XCTestCase {

    // MARK: - Phone Hashing

    func testHashPhone_consistentOutput() {
        let hash1 = ContactsManager.hashPhoneNumber("+14155551234")
        let hash2 = ContactsManager.hashPhoneNumber("+14155551234")
        XCTAssertEqual(hash1, hash2)
    }

    func testHashPhone_differentNumbersDifferentHashes() {
        let hash1 = ContactsManager.hashPhoneNumber("+14155551234")
        let hash2 = ContactsManager.hashPhoneNumber("+14155551235")
        XCTAssertNotEqual(hash1, hash2)
    }

    func testHashPhone_returnsHexString() {
        let hash = ContactsManager.hashPhoneNumber("+14155551234")
        // SHA256 hex is 64 characters
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit })
    }

    // MARK: - Phone Normalization

    func testNormalizePhone_alreadyE164() {
        let result = ContactsManager.normalizePhoneNumber("+14155551234", regionCode: "US")
        XCTAssertEqual(result, "+14155551234")
    }

    func testNormalizePhone_domesticUS() {
        let result = ContactsManager.normalizePhoneNumber("(415) 555-1234", regionCode: "US")
        XCTAssertEqual(result, "+14155551234")
    }

    func testNormalizePhone_withDashes() {
        let result = ContactsManager.normalizePhoneNumber("415-555-1234", regionCode: "US")
        XCTAssertEqual(result, "+14155551234")
    }

    func testNormalizePhone_withSpaces() {
        let result = ContactsManager.normalizePhoneNumber("415 555 1234", regionCode: "US")
        XCTAssertEqual(result, "+14155551234")
    }

    func testNormalizePhone_tooShort_returnsNil() {
        let result = ContactsManager.normalizePhoneNumber("123", regionCode: "US")
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:PushupCounterTests/ContactsManagerTests 2>&1 | tail -20`
Expected: Compilation errors — `ContactsManager` does not exist.

- [ ] **Step 3: Implement ContactsManager**

```swift
// PushupCounter/Services/ContactsManager.swift
import Foundation
import Contacts
import CryptoKit

final class ContactsManager {
    enum AuthorizationStatus {
        case authorized, denied, notDetermined
    }

    static func requestAccess() async -> Bool {
        let store = CNContactStore()
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    static func authorizationStatus() -> AuthorizationStatus {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    static func fetchContactPhoneNumbers() async -> [String] {
        let store = CNContactStore()
        let keys = [CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        var phoneNumbers: [String] = []

        let request = CNContactFetchRequest(keysToFetch: keys)
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                for phone in contact.phoneNumbers {
                    let raw = phone.value.stringValue
                    phoneNumbers.append(raw)
                }
            }
        } catch {
            // Contacts access denied or failed
        }
        return phoneNumbers
    }

    /// Normalize a phone number to E.164 format.
    /// Simple normalization: strip non-digit chars (except leading +), prepend country code if missing.
    static func normalizePhoneNumber(_ number: String, regionCode: String = "US") -> String? {
        let stripped = number.filter { $0.isNumber || $0 == "+" }

        // Already has country code
        if stripped.hasPrefix("+") {
            return stripped.count >= 10 ? stripped : nil
        }

        // US/CA: strip leading 1 if present, expect 10 digits
        let digitsOnly = stripped.filter { $0.isNumber }
        if regionCode == "US" || regionCode == "CA" {
            if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
                return "+\(digitsOnly)"
            } else if digitsOnly.count == 10 {
                return "+1\(digitsOnly)"
            }
        }

        return digitsOnly.count >= 7 ? "+\(digitsOnly)" : nil
    }

    /// SHA256 hash of a phone number string, returned as lowercase hex.
    static func hashPhoneNumber(_ e164Number: String) -> String {
        let data = Data(e164Number.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Full pipeline: fetch contacts, normalize, hash, return set of hashes.
    static func getContactPhoneHashes(regionCode: String = "US") async -> [String] {
        let rawNumbers = await fetchContactPhoneNumbers()
        var hashes: [String] = []
        for number in rawNumbers {
            if let normalized = normalizePhoneNumber(number, regionCode: regionCode) {
                hashes.append(hashPhoneNumber(normalized))
            }
        }
        return hashes
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:PushupCounterTests/ContactsManagerTests 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add PushupCounter/Services/ContactsManager.swift PushupCounterTests/ContactsManagerTests.swift
git commit -m "feat: add ContactsManager with phone normalization and SHA256 hashing"
```

---

## Task 6: Implement SyncManager with streak logic

**Files:**
- Create: `PushupCounter/Services/SyncManager.swift`
- Create: `PushupCounterTests/SyncManagerTests.swift`

- [ ] **Step 1: Write failing tests for streak calculation**

```swift
// PushupCounterTests/SyncManagerTests.swift
import XCTest
@testable import PushupCounter

final class SyncManagerTests: XCTestCase {

    private let calendar = Calendar.current

    // MARK: - Streak Calculation

    func testStreak_firstSession_streakIsOne() {
        let result = SyncManager.calculateStreak(
            sessionDate: Date(),
            lastActiveDate: nil,
            currentStreak: 0
        )
        XCTAssertEqual(result.newStreak, 1)
    }

    func testStreak_sameDay_noChange() {
        let today = calendar.startOfDay(for: Date())
        let result = SyncManager.calculateStreak(
            sessionDate: today,
            lastActiveDate: today,
            currentStreak: 5
        )
        XCTAssertEqual(result.newStreak, 5)
    }

    func testStreak_nextDay_increments() {
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let result = SyncManager.calculateStreak(
            sessionDate: today,
            lastActiveDate: yesterday,
            currentStreak: 5
        )
        XCTAssertEqual(result.newStreak, 6)
    }

    func testStreak_gapDay_resetsToOne() {
        let today = calendar.startOfDay(for: Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let result = SyncManager.calculateStreak(
            sessionDate: today,
            lastActiveDate: twoDaysAgo,
            currentStreak: 10
        )
        XCTAssertEqual(result.newStreak, 1)
    }

    func testStreak_longestStreak_updates() {
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let result = SyncManager.calculateStreak(
            sessionDate: today,
            lastActiveDate: yesterday,
            currentStreak: 29,
            longestStreak: 29
        )
        XCTAssertEqual(result.newStreak, 30)
        XCTAssertEqual(result.newLongestStreak, 30)
    }

    func testStreak_longestStreak_doesNotDecrease() {
        let today = calendar.startOfDay(for: Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let result = SyncManager.calculateStreak(
            sessionDate: today,
            lastActiveDate: twoDaysAgo,
            currentStreak: 10,
            longestStreak: 50
        )
        XCTAssertEqual(result.newStreak, 1)
        XCTAssertEqual(result.newLongestStreak, 50)
    }

    // MARK: - Today Pushups Reset

    func testTodayPushups_sameDay_adds() {
        let todayStr = SyncManager.dateString(for: Date())
        let result = SyncManager.calculateTodayPushups(
            sessionCount: 25,
            existingTodayPushups: 10,
            existingTodayDate: todayStr,
            sessionDate: Date()
        )
        XCTAssertEqual(result.newTodayPushups, 35)
        XCTAssertEqual(result.newTodayDate, todayStr)
    }

    func testTodayPushups_newDay_resets() {
        let result = SyncManager.calculateTodayPushups(
            sessionCount: 25,
            existingTodayPushups: 100,
            existingTodayDate: "2025-01-01",
            sessionDate: Date()
        )
        XCTAssertEqual(result.newTodayPushups, 25)
    }

    // MARK: - Milestone Detection

    func testMilestone_seven_detected() {
        XCTAssertTrue(SyncManager.isStreakMilestone(7))
    }

    func testMilestone_thirty_detected() {
        XCTAssertTrue(SyncManager.isStreakMilestone(30))
    }

    func testMilestone_five_notDetected() {
        XCTAssertFalse(SyncManager.isStreakMilestone(5))
    }

    func testMilestone_365_detected() {
        XCTAssertTrue(SyncManager.isStreakMilestone(365))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:PushupCounterTests/SyncManagerTests 2>&1 | tail -20`
Expected: Compilation errors — `SyncManager` does not exist.

- [ ] **Step 3: Implement SyncManager**

```swift
// PushupCounter/Services/SyncManager.swift
import Foundation

@MainActor
@Observable
final class SyncManager {
    private let firestoreService = FirestoreService()
    private(set) var isSyncing: Bool = false

    struct StreakResult {
        let newStreak: Int
        let newLongestStreak: Int
    }

    struct TodayPushupsResult {
        let newTodayPushups: Int
        let newTodayDate: String
    }

    // MARK: - Pure Calculation Functions (static, testable)

    static func calculateStreak(
        sessionDate: Date,
        lastActiveDate: Date?,
        currentStreak: Int,
        longestStreak: Int = 0
    ) -> StreakResult {
        let calendar = Calendar.current
        let sessionDay = calendar.startOfDay(for: sessionDate)

        guard let lastActive = lastActiveDate else {
            // First ever session
            return StreakResult(newStreak: 1, newLongestStreak: max(longestStreak, 1))
        }

        let lastDay = calendar.startOfDay(for: lastActive)

        if lastDay == sessionDay {
            // Same day — no change
            return StreakResult(newStreak: currentStreak, newLongestStreak: longestStreak)
        }

        let yesterday = calendar.date(byAdding: .day, value: -1, to: sessionDay)!
        if calendar.isDate(lastDay, inSameDayAs: yesterday) {
            // Consecutive day — increment
            let newStreak = currentStreak + 1
            return StreakResult(newStreak: newStreak, newLongestStreak: max(longestStreak, newStreak))
        }

        // Gap — reset
        return StreakResult(newStreak: 1, newLongestStreak: max(longestStreak, 1))
    }

    static func calculateTodayPushups(
        sessionCount: Int,
        existingTodayPushups: Int,
        existingTodayDate: String,
        sessionDate: Date
    ) -> TodayPushupsResult {
        let todayStr = dateString(for: sessionDate)
        if existingTodayDate == todayStr {
            return TodayPushupsResult(
                newTodayPushups: existingTodayPushups + sessionCount,
                newTodayDate: todayStr
            )
        } else {
            return TodayPushupsResult(
                newTodayPushups: sessionCount,
                newTodayDate: todayStr
            )
        }
    }

    static func isStreakMilestone(_ streak: Int) -> Bool {
        UserProfile.streakMilestones.contains(streak)
    }

    static func dateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    // MARK: - Sync Session to Firestore

    func syncSession(count: Int, startTime: Date, userId: String, displayName: String) async {
        guard count > 0 else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            // Fetch current user profile
            guard var profile = try await firestoreService.getUser(userId: userId) else { return }

            // Calculate streak
            let streakResult = Self.calculateStreak(
                sessionDate: startTime,
                lastActiveDate: profile.lastActiveDate,
                currentStreak: profile.currentStreak,
                longestStreak: profile.longestStreak
            )

            // Calculate today pushups
            let todayResult = Self.calculateTodayPushups(
                sessionCount: count,
                existingTodayPushups: profile.todayPushups,
                existingTodayDate: profile.todayDate,
                sessionDate: startTime
            )

            // Update profile
            try await firestoreService.updateUser(userId: userId, fields: [
                "currentStreak": streakResult.newStreak,
                "longestStreak": streakResult.newLongestStreak,
                "lastActiveDate": startTime,
                "totalPushups": profile.totalPushups + count,
                "todayPushups": todayResult.newTodayPushups,
                "todayDate": todayResult.newTodayDate
            ])

            // Create session activity
            let activity = Activity(
                userId: userId,
                userName: displayName,
                type: "session",
                count: count,
                timestamp: startTime,
                reactions: [:]
            )
            try await firestoreService.createActivity(activity)

            // Create milestone activity if applicable
            if Self.isStreakMilestone(streakResult.newStreak) && streakResult.newStreak != profile.currentStreak {
                let milestoneActivity = Activity(
                    userId: userId,
                    userName: displayName,
                    type: "streak_milestone",
                    count: streakResult.newStreak,
                    timestamp: startTime,
                    reactions: [:]
                )
                try await firestoreService.createActivity(milestoneActivity)
            }
        } catch {
            // Sync failure is non-blocking — local data is already saved
            print("SyncManager: Failed to sync session: \(error)")
        }
    }

    // MARK: - Account Deletion

    func deleteAllUserData(userId: String, phoneHash: String) async throws {
        try await firestoreService.deleteActivities(forUserId: userId)
        let friendships = try await firestoreService.getAllFriendships(userId: userId)
        for friendship in friendships {
            if let id = friendship.id {
                try await firestoreService.deleteFriendship(friendshipId: id)
            }
        }
        try await firestoreService.deletePhoneIndex(phoneHash: phoneHash)
        try await firestoreService.deleteUser(userId: userId)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:PushupCounterTests/SyncManagerTests 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add PushupCounter/Services/SyncManager.swift PushupCounterTests/SyncManagerTests.swift
git commit -m "feat: add SyncManager with streak calculation and Firestore sync"
```

---

## Task 7: Implement Auth Views (PhoneAuthView, DisplayNameView, SignInPromptView)

**Files:**
- Create: `PushupCounter/Views/Auth/PhoneAuthView.swift`
- Create: `PushupCounter/Views/Auth/DisplayNameView.swift`
- Create: `PushupCounter/Views/Auth/SignInPromptView.swift`

- [ ] **Step 1: Create SignInPromptView**

This is the placeholder shown on Leaderboard/Friends tabs when not authenticated.

```swift
// PushupCounter/Views/Auth/SignInPromptView.swift
import SwiftUI

struct SignInPromptView: View {
    @State private var showingAuth = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Sign in to connect with friends")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Sign In") {
                showingAuth = true
            }
            .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showingAuth) {
            PhoneAuthView()
        }
    }
}
```

- [ ] **Step 2: Create PhoneAuthView**

```swift
// PushupCounter/Views/Auth/PhoneAuthView.swift
import SwiftUI

struct PhoneAuthView: View {
    @Environment(FirebaseAuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var codeSent = false
    @State private var showDisplayName = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if !codeSent {
                    phoneEntrySection
                } else {
                    codeEntrySection
                }
            }
            .padding()
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showDisplayName) {
                DisplayNameView()
            }
        }
    }

    @ViewBuilder
    private var phoneEntrySection: some View {
        VStack(spacing: 16) {
            Text("Enter your phone number")
                .font(.headline)
            TextField("+1 (555) 555-1234", text: $phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if let error = authManager.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    await authManager.sendVerificationCode(phoneNumber: phoneNumber)
                    if authManager.error == nil {
                        codeSent = true
                    }
                }
            } label: {
                if authManager.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text("Send Code")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(phoneNumber.isEmpty || authManager.isLoading)
        }
    }

    @ViewBuilder
    private var codeEntrySection: some View {
        VStack(spacing: 16) {
            Text("Enter verification code")
                .font(.headline)
            TextField("123456", text: $verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if let error = authManager.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    let success = await authManager.verifyCode(verificationCode)
                    if success {
                        // Check if user profile exists, if not show display name
                        let service = FirestoreService()
                        if let userId = authManager.currentUser?.uid {
                            let profile = try? await service.getUser(userId: userId)
                            if profile == nil {
                                showDisplayName = true
                            } else {
                                dismiss()
                            }
                        }
                    }
                }
            } label: {
                if authManager.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text("Verify")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(verificationCode.isEmpty || authManager.isLoading)
        }
    }
}
```

- [ ] **Step 3: Create DisplayNameView**

```swift
// PushupCounter/Views/Auth/DisplayNameView.swift
import SwiftUI

struct DisplayNameView: View {
    @Environment(FirebaseAuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("What should we call you?")
                    .font(.headline)
                TextField("Display name", text: $displayName)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await createProfile() }
                } label: {
                    if isCreating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
            .padding()
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
    }

    private func createProfile() async {
        guard let user = authManager.currentUser,
              let phoneNumber = user.phoneNumber else {
            error = "No authenticated user."
            return
        }
        isCreating = true
        let phoneHash = ContactsManager.hashPhoneNumber(phoneNumber)
        let profile = UserProfile(
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            phoneHash: phoneHash,
            currentStreak: 0,
            longestStreak: 0,
            lastActiveDate: Date(),
            totalPushups: 0,
            todayPushups: 0,
            todayDate: SyncManager.dateString(for: Date()),
            createdAt: Date()
        )
        let service = FirestoreService()
        do {
            try await service.createUser(profile, userId: user.uid)
            try await service.createPhoneIndex(phoneHash: phoneHash, userId: user.uid)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add PushupCounter/Views/Auth/
git commit -m "feat: add auth views (PhoneAuthView, DisplayNameView, SignInPromptView)"
```

---

## Task 8: Implement LeaderboardView

**Files:**
- Create: `PushupCounter/Views/Leaderboard/LeaderboardView.swift`
- Create: `PushupCounter/Views/Leaderboard/PodiumView.swift`
- Create: `PushupCounter/Views/Leaderboard/LeaderboardRow.swift`
- Create: `PushupCounterTests/LeaderboardSortTests.swift`

- [ ] **Step 1: Write failing tests for leaderboard sorting**

```swift
// PushupCounterTests/LeaderboardSortTests.swift
import XCTest
@testable import PushupCounter

final class LeaderboardSortTests: XCTestCase {

    private func makeProfile(name: String, streak: Int, longest: Int = 0, total: Int = 0) -> UserProfile {
        UserProfile(
            displayName: name,
            phoneHash: "",
            currentStreak: streak,
            longestStreak: longest,
            lastActiveDate: Date(),
            totalPushups: total,
            todayPushups: 0,
            todayDate: "",
            createdAt: Date()
        )
    }

    func testSort_byStreakDescending() {
        let profiles = [
            makeProfile(name: "A", streak: 5),
            makeProfile(name: "B", streak: 10),
            makeProfile(name: "C", streak: 3)
        ]
        let sorted = LeaderboardView.sortProfiles(profiles)
        XCTAssertEqual(sorted.map(\.displayName), ["B", "A", "C"])
    }

    func testSort_tiebreakByLongestStreak() {
        let profiles = [
            makeProfile(name: "A", streak: 10, longest: 20),
            makeProfile(name: "B", streak: 10, longest: 30)
        ]
        let sorted = LeaderboardView.sortProfiles(profiles)
        XCTAssertEqual(sorted.map(\.displayName), ["B", "A"])
    }

    func testSort_tiebreakByTotalPushups() {
        let profiles = [
            makeProfile(name: "A", streak: 10, longest: 20, total: 100),
            makeProfile(name: "B", streak: 10, longest: 20, total: 200)
        ]
        let sorted = LeaderboardView.sortProfiles(profiles)
        XCTAssertEqual(sorted.map(\.displayName), ["B", "A"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:PushupCounterTests/LeaderboardSortTests 2>&1 | tail -20`
Expected: Compilation errors.

- [ ] **Step 3: Create LeaderboardRow**

```swift
// PushupCounter/Views/Leaderboard/LeaderboardRow.swift
import SwiftUI

struct LeaderboardRow: View {
    let rank: Int
    let profile: UserProfile
    let isCurrentUser: Bool

    private var isActiveToday: Bool {
        profile.todayDate == SyncManager.dateString(for: Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.bold())
                .foregroundStyle(isCurrentUser ? .blue : .secondary)
                .frame(width: 28, alignment: .center)

            Circle()
                .fill(isCurrentUser ? Color.blue : Color(.systemGray4))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(String(profile.displayName.prefix(1)).uppercased())
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }

            Text(isCurrentUser ? "You" : profile.displayName)
                .font(.body)
                .fontWeight(isCurrentUser ? .semibold : .regular)
                .foregroundStyle(isCurrentUser ? .blue : .primary)

            Spacer()

            HStack(spacing: 4) {
                if isActiveToday && profile.currentStreak > 0 {
                    Image(systemName: "flame.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("\(profile.currentStreak) days")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, isCurrentUser ? 12 : 0)
        .background(isCurrentUser ? Color.blue.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 4: Create PodiumView**

```swift
// PushupCounter/Views/Leaderboard/PodiumView.swift
import SwiftUI

struct PodiumView: View {
    let topThree: [(rank: Int, profile: UserProfile)]
    let currentUserId: String?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if topThree.count > 1 {
                podiumEntry(topThree[1], height: 60, color: .gray)
            }
            if topThree.count > 0 {
                podiumEntry(topThree[0], height: 80, color: .yellow)
            }
            if topThree.count > 2 {
                podiumEntry(topThree[2], height: 48, color: .orange)
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func podiumEntry(_ entry: (rank: Int, profile: UserProfile), height: CGFloat, color: Color) -> some View {
        let isMe = entry.profile.id == currentUserId
        VStack(spacing: 6) {
            Circle()
                .fill(isMe ? Color.blue : Color(.systemGray4))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(entry.profile.displayName.prefix(1)).uppercased())
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }
                .overlay(alignment: .top) {
                    if entry.rank == 1 {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .offset(y: -12)
                    }
                }

            Text(isMe ? "You" : entry.profile.displayName)
                .font(.caption.bold())
                .lineLimit(1)

            Text("\(entry.profile.currentStreak) days")
                .font(.caption2)
                .foregroundStyle(.secondary)

            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.6))
                .frame(height: height)
                .overlay {
                    Text("\(entry.rank)")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
        }
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 5: Create LeaderboardView with sort function**

```swift
// PushupCounter/Views/Leaderboard/LeaderboardView.swift
import SwiftUI

struct LeaderboardView: View {
    @Environment(FirebaseAuthManager.self) private var authManager

    @State private var profiles: [UserProfile] = []
    @State private var isLoading = false
    @State private var error: String?

    private let firestoreService = FirestoreService()

    static func sortProfiles(_ profiles: [UserProfile]) -> [UserProfile] {
        profiles.sorted { a, b in
            if a.currentStreak != b.currentStreak { return a.currentStreak > b.currentStreak }
            if a.longestStreak != b.longestStreak { return a.longestStreak > b.longestStreak }
            return a.totalPushups > b.totalPushups
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !authManager.isSignedIn {
                    SignInPromptView()
                } else if isLoading && profiles.isEmpty {
                    ProgressView()
                } else if profiles.isEmpty {
                    emptyState
                } else {
                    leaderboardContent
                }
            }
            .navigationTitle("Leaderboard")
            .task { await loadLeaderboard() }
            .refreshable { await loadLeaderboard() }
        }
    }

    @ViewBuilder
    private var leaderboardContent: some View {
        let sorted = Self.sortProfiles(profiles)
        let currentUserId = authManager.currentUser?.uid

        ScrollView {
            VStack(spacing: 0) {
                // Podium for top 3
                let topThree = Array(sorted.prefix(3)).enumerated().map { (rank: $0.offset + 1, profile: $0.element) }
                PodiumView(topThree: topThree, currentUserId: currentUserId)

                // Remaining rows
                LazyVStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, profile in
                        if index >= 3 {
                            LeaderboardRow(
                                rank: index + 1,
                                profile: profile,
                                isCurrentUser: profile.id == currentUserId
                            )
                            .padding(.horizontal)
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .padding(.top, 16)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Friends Yet", systemImage: "trophy")
        } description: {
            Text("Add friends to see the leaderboard")
        } actions: {
            NavigationLink("Find Friends") {
                FindFriendsView()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func loadLeaderboard() async {
        guard let userId = authManager.currentUser?.uid else { return }
        isLoading = true
        do {
            let friendships = try await firestoreService.getAcceptedFriendships(userId: userId)
            var friendIds = friendships.compactMap { $0.otherUserId(currentUserId: userId) }
            friendIds.append(userId)  // Include self
            let users = try await firestoreService.batchGetUsers(userIds: friendIds)
            profiles = users
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:PushupCounterTests/LeaderboardSortTests 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add PushupCounter/Views/Leaderboard/ PushupCounterTests/LeaderboardSortTests.swift
git commit -m "feat: add LeaderboardView with podium, ranked list, and sorting"
```

---

## Task 9: Implement Friends Tab (FriendsView, ActivityFeedItem, FriendRequestBanner, ReactionBar)

**Files:**
- Create: `PushupCounter/Views/Friends/FriendsView.swift`
- Create: `PushupCounter/Views/Friends/ActivityFeedItem.swift`
- Create: `PushupCounter/Views/Friends/FriendRequestBanner.swift`
- Create: `PushupCounter/Views/Friends/ReactionBar.swift`

- [ ] **Step 1: Create ReactionBar**

```swift
// PushupCounter/Views/Friends/ReactionBar.swift
import SwiftUI

struct ReactionBar: View {
    let reactions: [String: [String]]
    let currentUserId: String
    let onToggle: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Activity.reactionEmojis, id: \.self) { emoji in
                let reactors = reactions[emoji] ?? []
                let hasReacted = reactors.contains(currentUserId)
                let count = reactors.count

                Button {
                    onToggle(emoji)
                } label: {
                    HStack(spacing: 4) {
                        Text(emoji)
                            .font(.subheadline)
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2)
                                .foregroundStyle(hasReacted ? .blue : .secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(hasReacted ? Color.blue.opacity(0.12) : Color(.systemGray6))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(hasReacted ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 2: Create ActivityFeedItem**

```swift
// PushupCounter/Views/Friends/ActivityFeedItem.swift
import SwiftUI

struct ActivityFeedItem: View {
    let activity: Activity
    let currentUserId: String
    let onReaction: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(activity.userName.prefix(1)).uppercased())
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 6) {
                activityText
                Text(activity.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ReactionBar(
                    reactions: activity.reactions,
                    currentUserId: currentUserId,
                    onToggle: onReaction
                )
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var activityText: some View {
        if activity.isSession {
            HStack(spacing: 0) {
                Text(activity.userName).bold()
                Text(" did ")
                Text("\(activity.count) pushups").bold()
            }
            .font(.subheadline)
        } else {
            HStack(spacing: 0) {
                Text(activity.userName).bold()
                Text(" hit a ")
                Text("\(activity.count)-day streak!").bold().foregroundStyle(.orange)
            }
            .font(.subheadline)
        }
    }
}
```

- [ ] **Step 3: Create FriendRequestBanner**

```swift
// PushupCounter/Views/Friends/FriendRequestBanner.swift
import SwiftUI

struct FriendRequestBanner: View {
    let friendship: Friendship
    let requesterProfile: UserProfile?
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String((requesterProfile?.displayName ?? "?").prefix(1)).uppercased())
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading) {
                Text("\(requesterProfile?.displayName ?? "Someone") wants to be friends")
                    .font(.subheadline.bold())
                Text("From your contacts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Accept", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Decline", action: onDecline)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        }
    }
}
```

- [ ] **Step 4: Create FriendsView**

```swift
// PushupCounter/Views/Friends/FriendsView.swift
import SwiftUI

struct FriendsView: View {
    @Environment(FirebaseAuthManager.self) private var authManager

    @State private var activities: [Activity] = []
    @State private var pendingRequests: [(friendship: Friendship, profile: UserProfile?)] = []
    @State private var isLoading = false
    @State private var error: String?

    private let firestoreService = FirestoreService()

    var body: some View {
        NavigationStack {
            Group {
                if !authManager.isSignedIn {
                    SignInPromptView()
                } else if isLoading && activities.isEmpty && pendingRequests.isEmpty {
                    ProgressView()
                } else if activities.isEmpty && pendingRequests.isEmpty {
                    emptyState
                } else {
                    feedContent
                }
            }
            .navigationTitle("Friends")
            .toolbar {
                if authManager.isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            FindFriendsView()
                        } label: {
                            Text("Find Friends")
                                .font(.subheadline.bold())
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Sign Out", role: .destructive) {
                                authManager.signOut()
                            }
                            Button("Delete Account", role: .destructive) {
                                Task { await deleteAccount() }
                            }
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .task { await loadFeed() }
            .refreshable { await loadFeed() }
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        let currentUserId = authManager.currentUser?.uid ?? ""
        ScrollView {
            LazyVStack(spacing: 0) {
                // Friend requests
                ForEach(pendingRequests, id: \.friendship.id) { item in
                    FriendRequestBanner(
                        friendship: item.friendship,
                        requesterProfile: item.profile,
                        onAccept: { Task { await acceptRequest(item.friendship) } },
                        onDecline: { Task { await declineRequest(item.friendship) } }
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }

                // Activity feed
                ForEach(activities) { activity in
                    ActivityFeedItem(
                        activity: activity,
                        currentUserId: currentUserId,
                        onReaction: { emoji in
                            Task { await toggleReaction(activityId: activity.id ?? "", emoji: emoji) }
                        }
                    )
                    .padding(.horizontal)
                    Divider().padding(.leading, 66)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("See What Friends Are Up To", systemImage: "hand.wave")
        } description: {
            Text("Find friends from your contacts and cheer each other on")
        } actions: {
            NavigationLink("Find Friends") {
                FindFriendsView()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func loadFeed() async {
        guard let userId = authManager.currentUser?.uid else { return }
        isLoading = true
        do {
            // Load pending requests
            let requests = try await firestoreService.getPendingFriendRequests(userId: userId)
            var requestsWithProfiles: [(friendship: Friendship, profile: UserProfile?)] = []
            for request in requests {
                let profile = try? await firestoreService.getUser(userId: request.requesterId)
                requestsWithProfiles.append((friendship: request, profile: profile))
            }
            pendingRequests = requestsWithProfiles

            // Load activity feed
            let friendships = try await firestoreService.getAcceptedFriendships(userId: userId)
            var friendIds = friendships.compactMap { $0.otherUserId(currentUserId: userId) }
            friendIds.append(userId)
            activities = try await firestoreService.getActivities(forUserIds: friendIds)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func acceptRequest(_ friendship: Friendship) async {
        guard let id = friendship.id else { return }
        try? await firestoreService.acceptFriendship(friendshipId: id)
        await loadFeed()
    }

    private func declineRequest(_ friendship: Friendship) async {
        guard let id = friendship.id else { return }
        try? await firestoreService.deleteFriendship(friendshipId: id)
        await loadFeed()
    }

    private func toggleReaction(activityId: String, emoji: String) async {
        guard let userId = authManager.currentUser?.uid else { return }
        try? await firestoreService.toggleReaction(activityId: activityId, emoji: emoji, userId: userId)
        await loadFeed()
    }

    private func deleteAccount() async {
        guard let userId = authManager.currentUser?.uid,
              let phoneNumber = authManager.currentUser?.phoneNumber else { return }
        let phoneHash = ContactsManager.hashPhoneNumber(phoneNumber)
        let syncManager = SyncManager()
        try? await syncManager.deleteAllUserData(userId: userId, phoneHash: phoneHash)
        await authManager.deleteAccount()
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add PushupCounter/Views/Friends/
git commit -m "feat: add FriendsView with activity feed, reactions, and friend requests"
```

---

## Task 10: Implement FindFriendsView

**Files:**
- Create: `PushupCounter/Views/Friends/FindFriendsView.swift`

- [ ] **Step 1: Create FindFriendsView**

```swift
// PushupCounter/Views/Friends/FindFriendsView.swift
import SwiftUI

struct FindFriendsView: View {
    @Environment(FirebaseAuthManager.self) private var authManager

    @State private var matchedUsers: [UserProfile] = []
    @State private var existingFriendIds: Set<String> = []
    @State private var sentRequests: Set<String> = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var permissionDenied = false

    private let firestoreService = FirestoreService()

    var body: some View {
        Group {
            if permissionDenied {
                ContentUnavailableView {
                    Label("Contacts Access Required", systemImage: "person.crop.circle.badge.xmark")
                } description: {
                    Text("Allow contacts access in Settings to find friends who use PushupCounter.")
                }
            } else if isSearching {
                VStack {
                    ProgressView("Searching contacts...")
                }
            } else if hasSearched && matchedUsers.isEmpty {
                ContentUnavailableView {
                    Label("No Friends Found", systemImage: "person.slash")
                } description: {
                    Text("None of your contacts are on PushupCounter yet. Invite them!")
                }
            } else if hasSearched {
                List(matchedUsers) { user in
                    HStack {
                        Circle()
                            .fill(Color(.systemGray4))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Text(String(user.displayName.prefix(1)).uppercased())
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                            }

                        VStack(alignment: .leading) {
                            Text(user.displayName)
                                .font(.body.bold())
                            Text("\(user.currentStreak) day streak")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let userId = user.id, existingFriendIds.contains(userId) {
                            Text("Friends")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let userId = user.id, sentRequests.contains(userId) {
                            Text("Sent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Add") {
                                Task { await sendRequest(to: user) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .navigationTitle("Find Friends")
        .task { await searchContacts() }
    }

    private func searchContacts() async {
        guard let userId = authManager.currentUser?.uid else { return }

        // Check permission
        let status = ContactsManager.authorizationStatus()
        if status == .denied {
            permissionDenied = true
            return
        }

        if status == .notDetermined {
            let granted = await ContactsManager.requestAccess()
            if !granted {
                permissionDenied = true
                return
            }
        }

        isSearching = true

        // Load existing friendships
        let friendships = (try? await firestoreService.getAllFriendships(userId: userId)) ?? []
        existingFriendIds = Set(
            friendships.filter(\.isAccepted).compactMap { $0.otherUserId(currentUserId: userId) }
        )
        sentRequests = Set(
            friendships.filter(\.isPending).filter { $0.requesterId == userId }.compactMap { $0.otherUserId(currentUserId: userId) }
        )

        // Search contacts
        let hashes = await ContactsManager.getContactPhoneHashes()
        let hashToUser = (try? await firestoreService.lookupPhoneHashes(hashes)) ?? [:]
        let foundUserIds = Array(hashToUser.values).filter { $0 != userId }
        let users = (try? await firestoreService.batchGetUsers(userIds: foundUserIds)) ?? []
        matchedUsers = users

        isSearching = false
        hasSearched = true
    }

    private func sendRequest(to user: UserProfile) async {
        guard let currentUserId = authManager.currentUser?.uid,
              let friendUserId = user.id else { return }
        try? await firestoreService.createFriendship(currentUserId: currentUserId, friendUserId: friendUserId)
        sentRequests.insert(friendUserId)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add PushupCounter/Views/Friends/FindFriendsView.swift
git commit -m "feat: add FindFriendsView with contact discovery and friend requests"
```

---

## Task 11: Wire up navigation and sync integration

**Files:**
- Modify: `PushupCounter/ContentView.swift`
- Modify: `PushupCounter/Views/Session/PushupSessionView.swift`

- [ ] **Step 1: Update ContentView to add Leaderboard and Friends tabs**

Replace the full content of `ContentView.swift`:

```swift
// PushupCounter/ContentView.swift
import SwiftUI

struct ContentView: View {
    @State private var pushupDetector = PushupDetector()

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "figure.strengthtraining.traditional")
                }
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "calendar")
                }
            LeaderboardView()
                .tabItem {
                    Label("Leaderboard", systemImage: "trophy")
                }
            FriendsView()
                .tabItem {
                    Label("Friends", systemImage: "person.2")
                }
        }
        .environment(pushupDetector)
    }
}
```

- [ ] **Step 2: Update PushupSessionView to call SyncManager after saving**

In `PushupSessionView.swift`, first add a new environment property for `FirebaseAuthManager` alongside the existing ones (near line 7). Since `PushupCounterApp` always injects `FirebaseAuthManager` into the environment, this is non-optional:

```swift
    @Environment(FirebaseAuthManager.self) private var authManager
```

Then replace the `endSession()` function (lines 113-127) with this version that adds a fire-and-forget Firestore sync after saving locally:

```swift
    private func endSession() {
        arSessionManager?.pauseSession()
        let count = pushupDetector.count
        guard count > 0 else {
            dismiss()
            return
        }

        let session = PushupSession(startTime: sessionStartTime, endTime: Date(), count: count)
        session.dailyRecord = dailyRecord
        dailyRecord.sessions.append(session)
        modelContext.insert(session)

        try? modelContext.save()

        // Sync to Firestore (non-blocking, fire-and-forget)
        // Capture value types before dismiss tears down the view
        if authManager.isSignedIn, let userId = authManager.currentUser?.uid {
            let startTime = sessionStartTime
            Task.detached {
                let service = FirestoreService()
                let profile = try? await service.getUser(userId: userId)
                let displayName = profile?.displayName ?? "Unknown"
                let syncManager = await SyncManager()
                await syncManager.syncSession(count: count, startTime: startTime, userId: userId, displayName: displayName)
            }
        }

        dismiss()
    }
```

- [ ] **Step 3: Regenerate Xcode project and verify build**

Run: `cd /Users/kaushikandra/PushupCounter && xcodegen generate`
Run: `xcodebuild -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run all tests**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add PushupCounter/ContentView.swift PushupCounter/Views/Session/PushupSessionView.swift
git commit -m "feat: wire up Leaderboard and Friends tabs, integrate SyncManager"
```

---

## Task 12: Add Firestore security rules and indexes config

**Files:**
- Create: `firestore.rules`
- Create: `firestore.indexes.json`

- [ ] **Step 1: Create firestore.rules**

```
// firestore.rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }
    match /friendships/{docId} {
      allow read, delete: if request.auth != null && request.auth.uid in resource.data.userIds;
      allow create: if request.auth != null && request.auth.uid in request.resource.data.userIds;
      allow update: if request.auth != null && request.auth.uid in resource.data.userIds;
    }
    match /activities/{docId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null && request.auth.uid == request.resource.data.userId;
      allow update: if request.auth != null
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['reactions']);
      allow delete: if request.auth != null && request.auth.uid == resource.data.userId;
    }
    match /phoneIndex/{hash} {
      allow get: if request.auth != null;
      allow list: if false;
      allow create: if request.auth != null && request.resource.data.userId == request.auth.uid;
      allow delete: if request.auth != null && resource.data.userId == request.auth.uid;
    }
  }
}
```

- [ ] **Step 2: Create firestore.indexes.json**

```json
{
  "indexes": [
    {
      "collectionGroup": "activities",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "friendships",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userIds", "arrayConfig": "CONTAINS" },
        { "fieldPath": "status", "order": "ASCENDING" }
      ]
    }
  ]
}
```

- [ ] **Step 3: Commit**

```bash
git add firestore.rules firestore.indexes.json
git commit -m "feat: add Firestore security rules and composite indexes config"
```

---

## Task 13: Final build verification and cleanup

- [ ] **Step 1: Regenerate Xcode project**

Run: `cd /Users/kaushikandra/PushupCounter && xcodegen generate`

- [ ] **Step 2: Full build**

Run: `xcodebuild -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run all tests**

Run: `xcodebuild test -scheme PushupCounter -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 4: Add .superpowers to .gitignore if not already present**

Check and add:
```
.superpowers/
```

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: final cleanup and gitignore update"
```
