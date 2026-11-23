# Message Board Vault (CSC 4360 — Homework 02)

A real-time Flutter message board backed by Firebase Authentication and Cloud Firestore, enforcing database-layer ownership rules, idempotent writes, schema versioning/migration, and cursor-based pagination.

## Setup & Running
1. Install Flutter SDK and Firebase/FlutterFire CLIs (`dart pub global activate flutterfire_cli`).
2. Configure Firebase targets: `flutterfire configure --project=mad-hmwk2 --platforms=android,web`.
3. Install dependencies: `flutter pub get`.
4. Run locally: `flutter run -d chrome` (or build Android release APK via `flutter build apk --release`).

## Architecture & Data Model
- **`lib/services/auth_service.dart` (`AuthService`)**: Centralizes `register`, `signIn`, `signOut`, `currentUser`, and `authStateChanges()`. Registration writes the required 5-field user record to `users/{uid}` (`uid`, `firstName`, `lastName`, `role`, `registrationDateTime` via `FieldValue.serverTimestamp()`).
- **`lib/services/board_service.dart` (`BoardService`)**: Centralizes all Firestore `messages/{msgId}` CRUD operations (`createMessage`, live `messagesStream` via `snapshots()`, `updateMessage`, `deleteMessage`).
- **Separation of Concerns**:
  - `users/{uid}`: Private per-user profile written once at registration by the owning client.
  - `messages/{msgId}`: Public board posts readable by any signed-in user; `create` requires `request.resource.data.authorUid == request.auth.uid`; `update`/`delete` require `resource.data.authorUid == request.auth.uid`.

## Implemented Extra Spices (Undergraduate Track — 3 of 6 + Main Spice)
- **Main Spice (Release Readiness Gate)**: Verified end-to-end smoke test against the compiled `app-release.apk` build.
- **Spice #4 (Idempotent Alchemist)**: Uses deterministic draft document IDs paired with `FirebaseFirestore.runTransaction` so concurrent duplicate submissions produce exactly one message record.
- **Spice #5 (Schema Shape-shifter)**: Tags new posts with `schemaVersion: 2` and `category`, while supporting backward-compatible reads and lossless batch migration (`migrateV1ToV2`) of legacy `v1` documents using `body`.
- **Spice #6 (Batch Librarian)**: Caps live board reads with `orderBy('createdAt', descending: true).limit(25)` + `startAfterDocument` cursor queries, and executes atomic `WriteBatch` operations for seeding and bulk deletion.