# Cohabit Product and Technical Spec

Status: draft v1.2, 2026-11-01

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
- `schedule`: days of the week on which the habit applies. Each schedule applies only from the habit day it took effect, so editing it never changes how past days are derived (see Schedule history)
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

### Schedule history

- `HabitCreated` sets the first schedule. A `HabitEdited` event that changes the schedule carries `effectiveFrom`, the habit day on which it took effect (the day of the edit, by the configured boundary).
- The schedule in force on a day is the latest schedule, in event order (HLC, then `deviceId`, then event id), that had taken effect by that day. Days before any change use the creation schedule.
- Unlogged days are derived from the schedule in force on that day: `unknown` if it was scheduled, `skipped` if it was not. The review prompt and the graphs follow the same rule.
- Edits written before `effectiveFrom` existed take the UTC date of their HLC, which is the same on every device.
- Projections store the history as JSON (`habits.scheduleHistory`) and are rebuilt from the log, so a rebuild is deterministic. A database without the column is refolded when it is opened.

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

- Rendered with `CustomPainter` in one pass per graph, with no widget per cell: 10px square cells, a 2px gap, 0 radius, 7 rows (Monday to Sunday) and a column per week
- Per habit: done or confirmed clean is blue3, slipped is orange, not done is the off fill, `skipped` is a diagonal hatch and `unknown` is a 1px muted outline. Days before the habit existed and future days are blank
- Overview: the share of logged habits completed that day (negative habits count clean days; skipped and unlogged habits leave the share, and a day with scheduled habits but nothing logged shows as unknown) on off, blue1, blue2, blue3 and blue4. Steps: 0, under a third, under two thirds, under all, all
- Colour is never the only cue. Each state has a distinct shape, every graph has a legend, hovering (macOS) or pressing arrow keys shows the day's state, and every cell is a labelled button for screen readers
- Tapping or clicking a cell, or pressing Enter on the keyboard cursor, opens that day for backfill
- On phones, anchored to today and scrolling back through time; the range always fills the width and covers at least a year
- Two graphs can be stacked, with days aligned and one shared scroll, to compare correlated habits

### Design system: precise instrument

- One custom design system on both platforms, with no stock Material or Cupertino look (Material is used only as plumbing for routing, text input and focus)
- 0px corners, 1px hairlines, no shadows, gradients or illustrations
- Neutral interface, with colour reserved for data
- Light and dark, following the OS setting
- Quiet interface, blunt findings, for example `Sleep -> Gym  2.3x  n=84  CI 1.6-3.2`

Palette:

| Token | Dark | Light |
|---|---|---|
| background | #0B0E13 | #F7F8FA |
| surface | #12161D | #FFFFFF |
| hairline | #2A313C | #D5DAE2 |
| text | #E8ECF2 | #10151C |
| muted | #8C96A5 | #5D6776 |
| off | #1B212B | #E9ECF1 |
| blue1 | #16365C | #C5DFF8 |
| blue2 | #1F5A96 | #7DB6EC |
| blue3 | #3487D6 | #2C78C7 |
| blue4 | #7CC0FF | #0F4C8F |
| orange | #F0883E | #C3560C |

Light blue3 and orange are slightly darker than first proposed (#2F7FD1, #C4560C), and dark mode puts background-colour text on blue3 and orange fills, because white text failed WCAG AA on those fills (3.76:1 and 2.53:1 in dark, 4.14:1 and 4.48:1 in light). Everything that carries text or a control meets AA (4.5:1 for text, 3:1 for shapes); the tests check this. The hairline and off fill are deliberately quiet (about 1.1 to 1.5:1) and rely on shape, legend and text detail instead. The unknown outline uses muted so unresolved days stand out.

Typefaces, bundled as assets with their OFL 1.1 licences and never downloaded at runtime:

- Inter for names and sentences
- JetBrains Mono, with tabular figures, for numbers, metadata lines and small section labels (uppercase, 11px, 0.08em tracking, muted)

Components: segmented log control (30px high with a pointer, at least 44px on touch; selected Done or Clean uses blue3, selected Slipped uses orange), habit row, primary, secondary and ghost buttons, input (hairline border, blue3 on focus), review banner and insight card (left 2px blue3 rule, a sentence, a mono stats line; used on the Insights screen).

Per-platform adaptation covers navigation (sidebar on macOS, bottom tabs on Android phones, sidebar on wide or landscape Android windows), hover and keyboard vs. touch, scrolling, back gestures and window chrome. The sections are Today, History, Insights, Habits and Settings, in that order: Insights sits beside History because both read the log back, and it keeps the five bottom tabs equal in width (labels shrink to fit at large text sizes). On macOS, command-1 to command-5 switch sections, command-N adds a habit and Escape goes back.

## Analysis

`cohabit_analysis` (`packages/cohabit_analysis`) is a pure Dart package with no Flutter dependency, and the app runs it in an isolate (`Isolate.run`), so analysis never blocks the UI. It is recomputed, after a 300 ms debounce, whenever habits or logs change; the previous result stays on screen, marked "Updating", until the new one arrives. Its results are tested against fixtures generated with scikit-learn and SciPy (see Fixtures below). No ML runtime is used.

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
- Hide insights until a pair has at least 30 overlapping days. Validate this threshold against real data (see Thresholds).
- Lead with plain sentences, with the matrix as a drill-down.
- Say "tends to go with", never "causes".

If Dart proves too slow, hot paths may move to Rust through FFI.

### Methodology

Stages 1 and 2 are one procedure applied to aligned series, at lag 0 (stage 1) and at each lag (stage 2).

**Inputs.** For each active habit, one value per habit day from the earliest creation or logged day to today. The app takes each day from the resolved state, or, when nothing is logged, from the schedule in force on that day (`unknown` if scheduled, `skipped` if not). `done` is 1 and `notDone` is 0. `skipped` and `unknown` are missing. Missing is never 0.

**Negative habits.** Analysed with the spec's own encoding: `done` (a slip) is 1 and `notDone` (a confirmed clean day) is 0. A day with no confirmation is `unknown`, so it is missing, not clean. Phi is sign-symmetric, so polarity only changes the wording (a slip is "slipping on X"), never the statistics. Archived habits are not analysed.

**Pairs and lags.** Same-day pairs are unordered; the first habit in list order is the "from" habit, which only decides which habit the ratio below is stated for (phi, p, n_eff are symmetric). A lagged result `A -> B at lag k` compares A on day d with B on day d + k, so `from` is always the earlier day and `to` the later one. It is reported for every ordered pair of different habits at lags 1, 2 and 3. A habit is not lag-compared with itself. The window of a pair is the days d on which A(d) and B(d + k) are both observed (pairwise exclusion); `n` is their count.

**Effect size.** phi is the correlation of the two series after removing day-of-week effects: each value has the mean of its own weekday (over the pair's days) subtracted, which is the residual of regressing on weekday indicators, and phi is the Pearson correlation of the residuals (the partial correlation given the weekday). With binary series this is the usual phi (Matthews) coefficient, adjusted for the weekday. For a lagged pair the weekday of d fixes that of d + k, so one set of weekday strata serves both series. The unadjusted phi is also reported (`rawPhi`) for reference. Positive means done goes with done.

**Ratio.** To answer "how much more likely", the Mantel-Haenszel risk ratio is stratified by weekday: how many times as likely `to` is done on days `from` is done, compared with days it is not. Its confidence interval uses the Greenland-Robins variance of the log ratio, multiplied by the design effect below. It is undefined (shown as absent) when a stratified numerator or denominator is zero.

**Autocorrelation.** Habit series come in streaks, so neighbouring days are not independent and a plain test would find patterns that are not there. Following Bartlett (1935), the variance of a correlation between two autocorrelated series is inflated by the design effect `1 + 2 * sum over k = 1..K of rho_x(k) * rho_y(k)`, where rho are the autocorrelations of the two weekday-adjusted series at lag k days, estimated on the days where both are observed, from the pairs of such days that are k days apart. K is min(14, n / 4), and a lag with fewer than 10 such day pairs is ignored. A design effect below 1 is taken as 1, so the correction never claims more data than there is. The effective sample size is `n_eff = n / design effect`.

**Significance and confidence.** The test statistic is `t = phi * sqrt(df / (1 - phi^2))` with `df = n_eff - 2 - q`, where q is the number of weekday indicators beyond the first (6 when all seven weekdays occur). The p-value is two-sided from Student's t with that (fractional) df. The 95% confidence interval of phi is the Fisher z interval with standard error `1 / sqrt(n_eff - 3 - q)`. If `df < 1` there is no evidence: p is 1 and the interval is -1 to 1.

**False discovery control.** Every pair that was tested (every same-day pair and every lagged ordered pair, in one family) goes into one Benjamini-Hochberg correction at 5%. Adjusted values (q) equal `scipy.stats.false_discovery_control(method='bh')`. BH assumes independent or positively dependent tests, which is not guaranteed here (pairs share habits); the correction should be read as approximate.

**An insight** is a tested pair with `q <= 0.05` and `|phi| >= 0.10`. The second condition keeps a very certain but negligible association out of the list.

**Constant and degenerate series.** A pair is `tooFewDays` below 30 shared days (no statistics at all, not even phi). Otherwise it is `constant` when either series has no variation left after the weekday adjustment (including a habit that is always done, never done, or done on exactly the same weekdays every week): phi is undefined, nothing is tested and it is not in the correction family. It is `sparse` when the pooled 2x2 table would have an expected count below 5 in some cell (a rare habit): phi is reported, but the test is not trusted, so there is no p-value and it is not in the family. `rawPhi` is absent when a series is constant before any adjustment.

### Thresholds

| Threshold | Value | Basis |
|---|---|---|
| Overlapping days for a pair | 30 | Spec. Not yet validated against real data: no real logs existed. Simulation (below) gives what 30 days can and cannot detect |
| False discovery rate | 5% | Strict, because insights are read as findings |
| Smallest effect shown | abs(phi) >= 0.10 | Hides negligible associations that long histories make "significant" |
| Lags | 1, 2, 3 days | Habit effects mostly show the next day; each lag adds tests |
| Expected cell count to test | 5 | The usual rule for 2x2 tables |
| Autocorrelation | up to 14 days, at least 10 day pairs per lag | Two weeks covers the weekly rhythm without chasing noise |
| Insights listed | 20, then "more in All pairs" | |

Simulation on the package's generator (`packages/cohabit_analysis/test/analysis_test.dart` repeats parts of it):

- Two unrelated habits with long streaks (60 days, stay probability 0.85): 26% pass an uncorrected test at 5%, against 1.6% with the autocorrelation correction. With plain coin flips, the corrected test passes 4.2% (nominal 5%).
- A strong real link (done 90% of the days the other is, 10% otherwise) is found 66% of the time at 30 days, 99% at 45. A moderate one (80% against 20%) is found 50% at 30, 96% at 45 and 99% at 60. A weak one (70% against 30%) is found 24% at 30 days, 66% at 45, 86% at 60 and 97% at 90.
- So 30 days is where Cohabit starts to look, not where it can promise to find things. This needs checking against real logs before 30 is treated as settled.

### Presentation

Insights lead with a plain sentence, then a mono stats line: `Sleep -> Gym  +1d  2.3x  n=84  CI 1.6-3.2  phi +0.41` (same-day pairs read `Sleep & Gym` with no delay). The ratio is the Mantel-Haenszel risk ratio of `to` given `from`; n is the shared days; CI is its 95% interval; phi is the adjusted correlation. Sentences use "tends to go with" (`Sleep tends to go with Gym the next day.`; with "less" when phi is negative; a slip on a negative habit reads "slipping on X"). They never say "causes". Findings are ordered by q, then |phi|.

Empty states are honest and say what is missing: fewer than two habits; fewer than 30 shared days for every pair (with the largest count so far; unlogged days are not counted as missed); or enough data but nothing strong enough ("a normal result"). Every screen states how many days and comparisons the numbers come from.

The matrix (All pairs) shows the same-day phi of every pair with the 95% interval, effective n and adjusted p for the selected pair, at all lags and in both directions. An outlined cell is a finding; the sign and the number carry the meaning, not colour.

### Known limits

- A lagged association is not conditioned on the outcome habit's own previous day, so an echo of a same-day link through a persistent habit can also appear at lag 1. The autocorrelation correction keeps such results honest about uncertainty, not about redundancy.
- Associations are over all history with one effect per pair; habits that change over time are not modelled (change-point detection is stage 5).
- Weekday adjustment assumes the same weekday effect throughout.

### Fixtures

`packages/cohabit_analysis/tool/generate_fixtures.py` generates `test/fixtures/*.json` with scikit-learn (`matthews_corrcoef`, `LinearRegression` and `OneHotEncoder` for the weekday adjustment), SciPy (`pearsonr`, `t`, `norm`, `special.betainc`, `false_discovery_control`) and NumPy, with fixed seeds. The fixtures are committed and the Dart tests compare against them to 1e-9, so CI needs no Python. `python tool/generate_fixtures.py --check` confirms the committed files still match what the script produces. The Mantel-Haenszel ratio has no library implementation in this set, so the script implements it from the published formulas.

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
- Which notifications are worth having, given the no-guilt principle?
