# Cohabit Product and Technical Spec

Status: draft v1, 2026-11-01

Cohabit is an open-source, local-first habit tracker for macOS and Android. It finds which habits move together, using analysis that runs on the device.

## Principles

1. **Open to the core.** Licensed AGPL-3.0, with no paywalled features.
2. **Local-first.** The app is fully usable offline, with no account.
3. **Private by construction.** Remote storage and relays only ever see ciphertext.
4. **Honest analysis.** Show effect size, sample size and confidence. Never claim causation.
5. **Fast logging.** Logging a habit takes under two seconds.
6. **No guilt.** A broken streak is data, not failure.

## MVP scope

The MVP is the first four milestones below.

In scope:

- Positive and negative yes/no habits
- Logging, backfill and history editing
- Per-habit commit graph
- Import/export, Android widget, macOS menu bar item
- Phi and lagged correlation insights

Out of scope:

- Numeric habits and mood scores
- iOS, Windows, Linux and web
- Apple Health
- Accounts or any hosted Cohabit service
- Pretrained models and ML runtimes

## Domain model

### Habit

- `id`: UUIDv7
- `name`
- `polarity`: `positive` or `negative`
- `schedule`: days of the week on which the habit applies
- `archivedAt`: optional

### Day states

Each habit has one state per habit day:

| State | Meaning | Used in analysis |
|---|---|---|
| `done` | Positive habit completed, or negative habit slipped | Yes |
| `notDone` | Explicitly not done, or negative habit confirmed clean | Yes |
| `skipped` | Deliberately excused, or not scheduled | No |
| `unknown` | Nothing logged | No |

Rules:

- `unknown` is never treated as `notDone`, and it is displayed differently.
- A positive habit with no log stays `unknown` until the user resolves it, including through the review prompt.
- Negative habits are logged by recording a slip, plus a one-tap clean-day confirmation. Only confirmed days count as clean.

### Time

- Every event stores `habitDay` (local calendar date) and `loggedAt` (UTC instant).
- The day boundary is configurable and defaults to 03:00.
- `habitDay` never changes when the time zone does.

### Events

The append-only event log is the source of truth. SQLite tables holding current state are projections that can be rebuilt from it.

Every event has:

```text
id            UUIDv7
deviceId      stable per installation
hlc           hybrid logical clock timestamp
schemaVersion payload version
type          HabitCreated | HabitEdited | HabitArchived | DayStateSet
payload       versioned, type-specific data
```

`DayStateSet` also records `habitDay`, `loggedAt` and `source` (`manual`, `import` or `healthConnect`).

Rules:

- Events are never changed or deleted. An edit is a new event.
- Any past day can be edited.
- The current state of a habit and day comes from the latest event by HLC, with `deviceId` as the tie-breaker.
- A manual event overrides an automatic one regardless of HLC.
- Applying the same event twice has no effect.

Versioned payloads leave room for numeric values without a migration of existing events.

## Experience

### Logging

- Today view with one-tap logging
- "Yesterday" review prompt for unresolved days
- Backfill from the commit graph or a day view
- Android home-screen widget and notification actions
- macOS menu bar item and keyboard shortcuts

### Commit graph

- Rendered with `CustomPainter`
- Blue for positive, orange for negative (colour-blind-safe), final values to be checked for contrast
- `skipped` and `unknown` visually distinct from `notDone`
- On phones, anchored to today and scrolling back through time
- Two graphs can be stacked to compare correlated habits

### Design system: precise instrument

- One custom design system on both platforms, with no stock Material or Cupertino look
- 0px corners, 1px hairlines, no shadows, gradients or illustrations
- Neutral interface, with colour reserved for data
- One clean sans plus monospaced numerals
- Quiet interface, blunt findings, for example `Sleep -> Gym  2.3x  n=84  CI 1.6-3.2`

Per-platform adaptation covers navigation (sidebar on macOS, bottom bar on Android), hover and keyboard vs. touch, scrolling, back gestures and window chrome.

## Analysis

`cohabit_analysis` is a pure Dart package with no Flutter dependency, and it runs in an isolate. Its results are tested against fixtures generated with scikit-learn and SciPy.

| Stage | Method | Milestone |
|---|---|---|
| 1 | Phi correlation matrix | 4 |
| 2 | Lagged correlation | 4 |
| 3 | Graphical lasso (partial correlation) | 7 |
| 4 | Survival analysis of streaks | 7 |
| 5 | Change-point detection | 7 |

Requirements:

- Exclude `skipped` and `unknown` days pairwise.
- Adjust for day-of-week effects before correlating.
- Control false discoveries with Benjamini-Hochberg.
- Account for autocorrelation in significance estimates.
- Hide insights until a pair has at least 30 overlapping days. Validate this threshold against real data.
- Lead with plain sentences, with the matrix as a drill-down.
- Say "tends to go with", never "causes".

If Dart proves too slow, hot paths may move to Rust through FFI.

## Storage and sync

Local storage uses Drift on SQLite. State management uses Riverpod.

Sync is optional and uses no Cohabit server:

- Each device writes its own encrypted, immutable event batches, so devices never write to the same file.
- Devices download batches from other devices and merge them through the event rules above.
- Crypto uses libsodium: XChaCha20-Poly1305 for encryption and Argon2id for key derivation.
- Setup generates a recovery kit. Without the key, data cannot be recovered.

Storage adapters:

- WebDAV (for example Nextcloud)
- S3-compatible (for example MinIO or R2)
- Plain folder (decentralised through Syncthing)

Rollout:

1. Background sync on launch and on a timer
2. Near-realtime polling while the app is open
3. Optional self-hosted relay (ntfy or a small WebSocket service) that carries only notifications or ciphertext

Storage hosts can still see batch sizes and timing, and the docs must say so.

## Health Connect

Android-only. A rule turns a measurement into a yes/no result, for example `Sleep >= 7h` or `Steps >= 8000`.

- Store only the yes/no result and its source, not raw health data.
- macOS receives these results through sync.
- Manual edits override automatic results.
- Play Store health permissions need a declaration and a privacy policy.

## Distribution

- Android: F-Droid and Google Play. The F-Droid build must avoid proprietary dependencies.
- macOS: notarized DMG and Homebrew cask, which needs a paid Apple Developer account. No Mac App Store.

## Import and export

- Import from Loop Habit Tracker and CSV, so analysis can work on day one.
- Export all data to documented JSON and CSV.

## Milestones

1. Event store with device IDs and HLCs, habit CRUD, fast logging and backfill
2. Design system and commit graph
3. Import/export, Android widget and macOS menu bar item
4. `cohabit_analysis`: phi and lagged correlation
5. Encrypted background sync, then near-realtime
6. Health Connect rules
7. Advanced analysis and the optional relay

## Open questions

- Should a positive habit become `notDone` automatically after the review window?
- What is the final colour palette and typeface?
- Which notifications are worth having, given the no-guilt principle?
