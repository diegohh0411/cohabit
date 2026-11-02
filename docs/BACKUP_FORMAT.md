# Portable backup version 1

JSON is unencrypted and retains original user text. The envelope has format
"cohabit-backup", integer version 1, exportedAt (ISO timestamp), dayBoundaryMinutes
(0 through the application's maximum), and events (the complete canonical
event log, including archived habits and superseded history).

Each event contains id, deviceId, hlc (12 lowercase hexadecimal wall-clock
milliseconds, hyphen, four lowercase hexadecimal counter digits),
schemaVersion (1), type, and payload. Payloads use the domain event fields:
HabitCreated: habitId, name, polarity, schedule, createdDay, createdAt;
HabitEdited: habitId, optional name, schedule, effectiveFrom;
HabitArchived: habitId, archivedAt;
DayStateSet: habitId, habitDay, state, loggedAt, optional source.
Legacy omitted source means manual; omitted effectiveFrom retains legacy
schedule semantics. Unknown fields are retained in event payloads; unknown
envelope fields are ignored. Unsupported versions and event types are rejected.

Restore merges IDs and preserves recipient identity. Identical events skip;
conflicting IDs reject the entire transaction. References may target incoming
or existing creates regardless of input order. Projections are rebuilt using
existing conflict rules. Boundary restoration is opt-in. Preview is advisory:
commit validates again. Future clock drift rejects the backup.

CSV contains explicit resolved logs only, including archived habits and explicit
unknown/skipped states. It includes habitId, name, polarity, archivedAt, date,
state, source, timestamp. Missing days are not synthesized. Cells are quoted,
quotes doubled, records separated by CRLF, and formula-leading text prefixed
with an apostrophe. CSV is not a full backup.

Timestamps require YYYY-MM-DDTHH:mm:ss with optional fractional seconds and Z or ±HH:mm timezone. Calendar dates and time/offset ranges are validated without normalization. Unknown top-level event fields are rejected; payload extras remain lossless.
