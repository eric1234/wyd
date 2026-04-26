# Tray-Based Time Tracker

## Status

Draft v1 product and implementation specification.

## Product Summary

This project is a desktop time tracker built with Dart and Flutter. It lives in the operating system tray or menu bar instead of as a normal always-open application window.

The main idea is confirmation-based tracking instead of manual timer management. The user starts a task once, then the app periodically asks them to confirm or correct the current task. This reduces missed stop and start actions while still keeping the tracked timeline accurate.

## Goals

- Build a native desktop GUI app in Flutter.
- Start from Linux support first, while keeping the architecture portable to macOS and Windows.
- Make the common path keyboard-first and extremely fast.
- Keep all data local and offline in v1.
- Track work as an append-only activity log and derive time segments from that log.
- Prevent focus stealing when the platform can reliably detect that the user is actively typing.

## Permanent Scope Boundaries

These are intentionally out of scope for the life of the product, not merely deferred from v1.

- Mobile or web support.
- Cloud sync, collaboration, or backend services.
- Billing, invoicing, screenshots, or surveillance features.
- Complex project, client, tag, or hierarchy management.
- Historical editing of prior entries.
- Analytics-heavy dashboards.
- Detailed drill-down reporting beyond a simple daily summary list.

## Platform Scope

- v1 launch target: Linux desktop.
- Initial development target: Linux on Wayland/Cinnamon.
- Planned follow-up platforms: macOS, then Windows.
- The codebase should isolate platform-specific tray, startup, power, and typing-detection behavior behind adapters so the domain logic remains portable.
- The application may use Flutter's standard Material-based desktop UI for v1 because the interface is intentionally minimal.
- Support for other Linux desktop environments, including X11, is best-effort in v1 and should come through Dart or Flutter packages that abstract platform differences where practical.
- Packaging and installer work are out of scope for the current specification. A directly launched desktop binary is sufficient for v1 development and initial use.

## Capability Tiers

- Core required behavior for v1 includes tray availability, single-instance enforcement, the quick-entry popup, local SQLite persistence, task start and stop rules, nag scheduling, timeout auto-stop, the report window, and the settings window.
- Optional or best-effort capabilities for v1 include distinct primary and secondary tray click handling, tray-relative popup positioning, recent-typing deferral, lock and sleep detection, and start-at-login integration.
- If an optional capability is unavailable, the app should disable or hide the related setting or affordance and use the documented fallback instead of brittle emulation.
- If tray support itself is unavailable at startup, the app should display an error and exit because the tray is fundamental to the product.

## Core Concepts

- `Activity log`: The source-of-truth history of user-visible task boundary events.
- `Active task`: Derived from the latest activity log event. If the latest relevant event is `start_task` or `switch_task`, a task is active. If the latest relevant event is `stop_task`, there is no active task.
- `Confirmation`: The user re-submits the same current task to affirm it is still ongoing. Confirmations do not create new activity log rows.
- `Nag prompt`: The quick-entry popup shown on a schedule while a task is active.
- `Expired prompt`: A nag prompt that timed out without response. At that point the active task has already been stopped, but the prompt remains open so the user can resume or switch tasks.
- `Normalized task text`: Task text after pasted newlines are removed, leading and trailing ASCII whitespace is stripped, internal runs of spaces and tabs are collapsed, and case-insensitive comparison is applied for equality and grouping.

## Primary User Experience

1. The app launches into the tray and does not open a normal main window.
2. When the platform supports direct tray click actions, primary click on the tray icon opens a small quick-entry popup. Otherwise the popup remains reachable through the tray menu.
3. The popup contains a single-line text field and a `Submit` button.
4. The text field is focused automatically when the popup opens.
5. If there is an active task, the field is pre-populated with that task and the text is selected so typing replaces it immediately.
6. If there is no active task, the field is empty.
7. Pressing `Enter` submits the form.
8. Clicking `Submit` also submits the form.
9. After a successful submit, the popup closes and the app remains running in the tray.
10. While a task is active, the app periodically shows or reuses the same popup to ask the user to confirm or change the task.
11. If the popup appears and the user simply presses `Enter`, the current task continues.
12. If the user changes the text and submits, the previous task ends and the new task starts immediately.
13. If the popup appears and the user does not respond in time, the current task stops automatically.
14. After auto-stop, the popup remains visible so the user can resume the same task or enter a new one when they return.

## Tray and Window Behavior

- The app must be single-instance.
- Launching a second instance should focus or reveal the existing app state instead of starting another tracker process.
- The quick-entry popup should be small, non-resizable, and always on top while visible.
- The popup should open near the tray location when practical. If platform APIs do not allow this reliably, centering it on the current screen is acceptable.
- The popup should not stack. If it is already open, opening it again should focus and reuse the existing window.
- When supported, primary click on the tray icon opens the quick-entry popup and secondary click opens the context menu.
- If the platform does not support distinct primary and secondary tray clicks, the primary tray interaction opens the context menu instead.
- The tray menu in v1 contains `Update Task`, `Stop Task`, `Report`, `Settings`, and `Exit`.
- `Update Task` opens or focuses the quick-entry popup.
- `Stop Task` is disabled when there is no active task.
- `Report` opens the report window.
- `Settings` opens the settings window.
- `Exit` stops any active task and then exits the app.

## Task Lifecycle Rules

- Only one task may be active at a time.
- Task identity is user-entered free text.
- Equality and grouping use normalized task text.
- The original task text entered by the user is preserved on activity log events.
- Empty or whitespace-only submissions are invalid.

### Task Text Handling

- Task text is stored as Unicode text.
- The app does not impose a separate application-level maximum length. The practical limit is whatever SQLite can store.
- Pasted newline characters are removed before validation, normalization, and storage.
- Leading and trailing ASCII whitespace is stripped.
- Leading and trailing punctuation is preserved.
- Equality and grouping normalize by removing pasted newlines, trimming leading and trailing ASCII whitespace, collapsing internal runs of spaces and tabs, and comparing case-insensitively.
- Other Unicode characters, including odd characters such as zero-width characters and non-breaking spaces, are preserved as entered.
- When the UI needs a display label for a normalized task, it should prefer the most recent stored raw task text already known for that normalized task.

### Start Task

- If no task is active and the user submits non-empty task text, append a `start_task` activity log event at the submit timestamp.
- This starts tracking immediately.

### Continue Current Task

- If a task is active and the submitted task text normalizes to the same current task, do not append a new activity log row.
- Instead, treat the action as a confirmation.
- A confirmation resets the reminder schedule based on the submit timestamp.
- After confirmation, the active task display text should use the most recent stored raw task text known for that normalized task.

### Switch Task

- If a task is active and the submitted task text normalizes to a different task, append a `switch_task` activity log event at the submit timestamp.
- This implicitly ends the previously active task and starts the new task at the same timestamp.

### Explicit Stop

- If a task is active and the user clicks `Stop Task`, append a `stop_task` activity log event at click time.
- If the quick-entry popup is visible, dismiss it after the stop succeeds.
- After a stop event, there is no active task and no further nag prompts should be scheduled until the user starts a task again.

### Exit

- If a task is active and the user chooses `Exit`, append a `stop_task` event with source `exit` at exit time, then terminate the application.
- If the quick-entry popup is visible but the task already expired because of `nag_timeout`, exit immediately without appending an additional stop event.
- If no task is active, exit immediately.

### Lock and Sleep

- If the current platform adapter can detect system lock or sleep while a task is active, append a `stop_task` event immediately.
- Resume from lock or wake does not automatically restart tracking.
- If lock or sleep detection is unavailable, the app should leave this behavior disabled rather than emulate it unreliably.

## Nag and Confirmation Behavior

- The reminder interval `X` defaults to `15` minutes.
- Reminders are only scheduled while a task is active.
- When no task is active, the app remains silent until the user manually starts a task again.
- The next nag is measured from the most recent successful confirmation or task submission.
- If the popup is already open when a nag becomes due, the app reuses the existing popup instead of opening another one.

### Recent-Typing Deferral

- Before a due nag is shown, the app checks whether there has been recent keyboard activity.
- If keyboard activity was detected within the last `5` seconds, the popup is not shown yet.
- The app waits for the typing deferral window to pass, then checks again.
- If recent typing is still detected, the popup is delayed again.
- This repeats until the user is no longer actively typing.
- The goal is to avoid stealing focus while the user is mid-sentence or mid-command.
- The typing deferral window should be configurable in settings, default `5` seconds.
- If the current environment does not allow reliable recent-typing detection, the setting should be disabled and nags should be shown normally.
- There is no maximum cumulative typing deferral in v1.
- The unanswered timeout countdown begins when the popup is actually shown after any typing deferral, not when the original nag due time first arrives.
- The typing detector may keep only the timestamp of the most recent detected keystroke, in memory only.
- No key contents, scan codes, window titles, or application names are stored.

### Unanswered Timeout

- The response timeout `Z` defaults to `1` minute.
- If the popup is shown while a task is active, the response timeout countdown applies from when that popup instance first became visible.
- A scheduled nag that becomes due while the popup is already open reuses the existing popup and does not restart the timeout countdown.
- If the user does not respond within `Z` minutes after the popup is shown, append a `stop_task` event with source `nag_timeout`.
- The `occurred_at` timestamp of that stop event is the popup shown time, not popup shown time plus the timeout duration.
- This means unconfirmed time after the popup first became visible is not counted.
- After timeout, there is no active task.
- The popup remains open after timeout so the user can immediately resume the same task or enter a different one.
- The popup does not need a separate expired-state message or styling in v1.
- If the user submits after timeout, that submission creates a fresh `start_task` event because no task is active anymore.

## Popup Interaction Details

- The popup has a single-line task field and a `Submit` button.
- The field should support standard text editing shortcuts for the platform.
- When the popup is pre-populated, its full text should be selected on open.
- The popup should support keyboard-only use for the full common path.
- If the popup is already open when a nag becomes due, the nag is a no-op. The existing popup remains unchanged, including any partially typed input.
- Closing the popup without submitting does not count as confirmation.
- If a nag popup is closed before timeout, the unanswered timeout still continues against that pending prompt.
- Reopening the popup before the timeout expires should restore the same pending prompt state.
- Clicking `Stop Task` while the popup is visible dismisses the popup after the stop succeeds.
- Clicking `Exit` while the popup is visible behaves the same as `Exit` from the tray menu. If the task is still active it is stopped on exit. If the prompt already expired the app exits without writing a duplicate stop event.
- Opening or using the `Report` or `Settings` window is independent of the popup and does not pause, dismiss, or otherwise alter its pending state.

## Autocomplete

- The input field offers autocomplete suggestions from tasks entered within the last `Y` days.
- `Y` defaults to `3` days.
- Suggestions are built from `start_task` and `switch_task` activity log events.
- Suggestions are deduplicated by normalized task text.
- Each suggestion displays the most recent raw task text seen for that normalized task.
- Matching is case-insensitive.
- Prefix matches should rank above substring matches.
- Within the same match class, more recently used tasks rank first.
- Show up to `5` suggestions in v1. This limit should be kept as an implementation constant so it is easy to change later.
- The first visible suggestion is auto-highlighted.
- Arrow keys move through suggestions.
- Pressing `Enter` with a suggestion highlighted accepts it and submits in one action.
- If no suggestion is highlighted, pressing `Enter` submits the raw field text.
- The feature is intended both to reduce typing and to normalize recurring task names.

## Report Window

- The report is a separate window from the quick-entry popup.
- The default selected date is today.
- The report shows the total tracked time for the selected day.
- The report shows one row per normalized task with the total time spent on that task for the selected day.
- Multiple derived segments for the same normalized task are aggregated into a single row.
- Rows are sorted by total duration descending.
- Each row displays the most recent raw task text seen for that normalized task on the selected day.
- If rows tie on total duration, the secondary ordering does not matter.
- The report provides previous-day and next-day navigation.
- Navigating to a future date beyond today is not allowed.
- If a task segment crosses midnight, the report must split it correctly so each day only gets its own portion.
- Day boundaries and displayed dates use the user's current local timezone at query time.
- The report is a static snapshot while the window remains open. It does not live-update automatically.
- The report is read-only in v1.
- No charts are required in v1.

## Settings Window

- Settings are editable via UI in v1.
- The settings window is reachable from the tray menu.
- v1 settings include:
- Reminder interval in minutes. Default `15`.
- Recent-task autocomplete lookback in days. Default `3`.
- Unanswered timeout in minutes. Default `1`.
- Typing deferral window in seconds. Default `5` when supported. Disable the setting when recent-typing detection is unavailable.
- Start app at login. Default `false`.
- Settings changes are persisted locally.
- On first run, if start-at-login is supported, ask the user for consent before enabling it.
- Suggested v1 validation ranges are: reminder interval `1-240` minutes, autocomplete lookback `1-30` days, unanswered timeout `1-60` minutes, and typing deferral `0-30` seconds. These should be implemented as constants so they are easy to change later.
- The reminder interval must be greater than or equal to the unanswered timeout.
- If reminder-related settings change while a task is active, future cycles should use the latest saved values.
- If a reminder or timeout cycle is already in progress when its setting changes, that in-progress cycle may finish using either the old or new value, whichever is simplest to implement.
- If the user disables start-at-login, the platform integration should be removed immediately or on next safe opportunity.
- If start-at-login is unsupported on the current platform, the setting should be disabled or hidden.

## Data Model

### Activity Log

Use an append-only `activity_log` table as the historical source of truth.

Recommended fields:

| Field | Type | Notes |
| --- | --- | --- |
| `id` | integer | Monotonic primary key used as a stable tie-breaker |
| `occurred_at_utc` | timestamp | Logical event time |
| `event_type` | enum | `start_task`, `switch_task`, `stop_task` |
| `task_text` | text nullable | Present for `start_task` and `switch_task` |
| `task_text_normalized` | text nullable | Present for `start_task` and `switch_task` |
| `source` | enum | `manual_submit`, `manual_stop`, `nag_timeout`, `system_lock`, `system_sleep`, `exit`, `recovery` |
| `created_at_utc` | timestamp | Insert time |

Rules:

- Normal operation should only append rows, never update or delete them.
- `start_task` is emitted only when no task is active.
- `switch_task` is emitted only when a task is active and the normalized submitted text differs.
- `stop_task` is emitted only when a task is active.

### Runtime State

Some runtime state is still required because confirmations do not create activity log rows.

Recommended persisted `app_state` fields:

| Field | Type | Notes |
| --- | --- | --- |
| `last_confirmation_at_utc` | timestamp nullable | Last successful confirmation or task submit |
| `pending_prompt_shown_at_utc` | timestamp nullable | When the current nag popup became visible |
| `pending_prompt_expired` | boolean | Whether the shown prompt has already auto-stopped the task |
| `clean_shutdown` | boolean | Marks whether the previous exit completed normally |

The activity log remains the source of truth for historical task boundaries. `app_state` only stores scheduler and recovery state that cannot be inferred from the log alone.

### Settings

Store settings locally in SQLite or a small persistent settings store.

Recommended fields:

| Field | Type | Default |
| --- | --- | --- |
| `reminder_interval_minutes` | integer | `15` |
| `autocomplete_lookback_days` | integer | `3` |
| `response_timeout_minutes` | integer | `1` |
| `typing_deferral_seconds` | integer | `5` |
| `start_at_login` | boolean | `false` |

### Persistence Guarantees

- All database writes that change task state, prompt state, or settings must happen atomically in a single SQLite transaction.
- State-changing operations should be serialized through a simple in-process queue, mutex, or equivalent single-writer mechanism so UI submits, timer callbacks, tray actions, and startup recovery do not interleave unpredictably.
- If a write fails, cancel the current operation and leave the previously persisted state authoritative.

## Deriving Time Segments From the Activity Log

Reports do not read stored time segments. They derive them from activity log events.

Recommended derivation algorithm:

1. Read `activity_log` ordered by `occurred_at_utc`, then by `id` as a stable tie-breaker.
2. Maintain `current_task` in memory while iterating.
3. On `start_task`, open a new derived segment for that task.
4. On `switch_task`, close the current derived segment at the event time and open a new segment for the new task at the same event time.
5. On `stop_task`, close the current derived segment at the event time.
6. When building a report for the current day and a task is still active, treat `now` as the temporary segment end for display purposes.
7. Split any derived segment at day boundaries using the user's current local timezone at query time before aggregation.
8. Aggregate durations by normalized task text for report rows.

The app should never intentionally emit invalid event sequences. If malformed sequences still occur, report generation should make a reasonable best effort instead of failing outright, but exhaustive repair logic is not required.

## State Model

Recommended conceptual states:

- `Idle`: No active task, no pending nag.
- `Tracking`: Active task exists, no popup currently awaiting response.
- `PromptVisible`: Active task exists, popup is visible and awaiting response.
- `PromptExpired`: Popup remains visible, but the active task has already been auto-stopped due to timeout.

Key transitions:

- `Idle -> Tracking`: User submits a new task.
- `Tracking -> Tracking`: User confirms the same task.
- `Tracking -> Tracking`: User switches to a different task.
- `Tracking -> PromptVisible`: User manually opens the popup while a task is active.
- `Tracking -> PromptVisible`: Nag becomes due and is shown after any typing deferral.
- `PromptVisible -> Tracking`: User confirms or switches task before timeout.
- `PromptVisible -> PromptExpired`: Timeout expires and a `stop_task` event is appended.
- `PromptExpired -> Tracking`: User submits a task, creating a fresh `start_task` event.
- `Tracking -> Idle`: User explicitly stops, exits, or the system locks or sleeps.

## Recovery Rules

- The app should persist enough state to support simple, conservative recovery after crashes or forced termination.
- Perfect reconstruction is not required in v1. Simpler recovery that may lose uncertain time is preferred over complex heuristics.
- On startup, if the previous shutdown was clean, normal initialization is sufficient.
- On startup after an unclean shutdown, inspect the last activity log event and the persisted confirmation state.
- If there is no active task according to the activity log, recover as idle.
- If there is an active task and `pending_prompt_shown_at_utc` is set, append a recovery `stop_task` event at that stored popup shown timestamp, then recover as idle.
- Otherwise, if there is an active task, append a recovery `stop_task` event at `last_confirmation_at_utc`. If `last_confirmation_at_utc` is unavailable, use the last relevant activity log event time.
- If a required recovery write fails during initialization, display the problem and exit.
- Recovery behavior should prefer undercounting or dropping uncertain time over extending tracking based on complex reconstruction.

## Error Handling and Diagnostics

- If tray support or another required startup capability cannot be initialized, display the problem and exit.
- If a runtime operation fails, cancel that operation, leave the previously persisted state unchanged, and display the problem.
- If a stop-during-exit operation fails, cancel the exit and keep the app running.
- Diagnostic logging is disabled by default.
- A single environment variable should enable diagnostic logging to stdout or stderr for local debugging. The exact variable name is an implementation detail.
- v1 does not require persistent log files.

## Technical Direction

- Use Flutter desktop as the application framework.
- Use Flutter's default Material design system for the UI in v1.
- Use SQLite for local persistence.
- Keep domain logic independent from Flutter widgets and platform APIs.
- Organize the code into at least three layers:
- Domain layer for task state rules, scheduling rules, report derivation, and normalization.
- Infrastructure layer for SQLite, tray integration, startup-at-login, power and lock detection, and typing activity detection.
- UI layer for quick entry, report window, and settings window.
- Prefer Dart and Flutter packages that abstract platform differences whenever practical.
- Recommended plugin starting points include `tray_manager`, `window_manager`, and `sqflite_common_ffi`.
- Native platform channels may still be required for startup-at-login, power events, and recent-typing detection.

## Linux Notes and Risks

- Linux desktop support varies across X11, Wayland, GNOME, KDE, and StatusNotifier/AppIndicator implementations.
- Tray behavior and popup positioning may need platform-specific handling.
- The initial Linux environment is Wayland on Cinnamon. Support for other Linux environments is best-effort in v1.
- Global recent-typing detection is likely the hardest Linux-specific integration, especially on Wayland, and should be treated as the lowest-priority optional capability in v1.
- The implementation should isolate typing detection behind an interface so Linux-specific strategies can evolve without changing the rest of the app.
- If recent-typing detection is not feasible in a specific Linux environment, the accepted fallback is to disable the deferral behavior, disable the related setting, and allow the popup to be more interruptive.

## Acceptance Criteria

- Launching the app on a supported tray environment shows a tray icon and no normal main window.
- The app is single-instance. Launching a second instance focuses or reveals the existing app state instead of starting another tracker process.
- If direct tray click actions are supported, primary click opens the popup and secondary click opens the tray menu.
- If direct tray click opening is unavailable but tray support exists, the primary tray interaction opens the tray menu and `Update Task` opens the popup.
- If tray support is unavailable at startup, the app displays an error and exits.
- Opening the popup gives keyboard focus to the task field immediately.
- Submitting a new task appends `start_task` and begins tracking immediately.
- Pressing `Enter` on the unchanged current task records a confirmation, does not append a new activity log row, and reschedules the next nag.
- Submitting a different task while tracking appends `switch_task` and changes the active task immediately.
- Clicking `Stop Task` appends `stop_task`, dismisses the popup if it is open, and leaves no active task.
- If a nag becomes due while the popup is already open, the existing popup is reused and any partially typed input remains intact.
- If recent-typing detection is supported, a due nag is deferred until typing has been idle for the configured deferral window. If unsupported, the setting is disabled and nags are shown normally.
- If the popup is shown and ignored for the configured timeout, a `stop_task` event is appended with the popup shown timestamp as its logical stop time.
- After timeout, the popup remains available so the user can resume by submitting again.
- Clicking `Exit` while a task is active appends `stop_task` with source `exit`. If the visible popup has already expired the task, the app exits without appending a duplicate stop event.
- Where the current platform supports lock and sleep detection, locking or sleeping while a task is active appends `stop_task` immediately and resume does not restart tracking.
- Autocomplete shows up to `5` deduplicated recent-task suggestions, auto-highlights the first suggestion, and lets `Enter` accept the highlighted suggestion or submit raw text when none is highlighted.
- The report correctly shows daily totals, uses the user's current local timezone at query time, remains static while open, and correctly splits segments that cross midnight.
- The settings window allows changing all supported v1 settings, persists those changes locally, enforces the defined ranges, and does not allow the reminder interval to be shorter than the response timeout.
- If start-at-login is supported, first run asks for consent before enabling it. If unsupported, the setting is disabled or hidden.
- On startup after an unclean shutdown, the app performs simple conservative recovery by appending a recovery stop when needed instead of continuing uncertain tracking.
- Unrecoverable initialization failures display the problem and exit. Runtime failures cancel the current operation without partially applying it.
- Diagnostic logging can be enabled with an environment variable and writes to stdout or stderr.

## Implementation Phases

1. Bootstrap the Flutter desktop app, tray lifecycle, hidden startup behavior, and single-instance enforcement.
2. Implement SQLite persistence, normalization, the activity log repository, and the report derivation logic.
3. Implement the quick-entry popup, submit behavior, autocomplete, and tray menu actions.
4. Implement nag scheduling, timeout behavior, and runtime state persistence.
5. Implement recent-typing deferral as the lowest-priority optional v1 capability when platform support exists.
6. Implement report and settings windows.
7. Implement simple recovery, lock and sleep handling, and start-at-login where supported.
8. Harden Linux-specific integrations and prepare portability seams for macOS and Windows.

## Product Positioning

- This application is intentionally small and bounded in scope.
- Future versions may refine behavior and polish implementation details, but the product should remain simple rather than grow into a broad time-tracking platform.
- The report should remain a straightforward day view showing how time was spent, without turning into a complex analytics surface.

## Final Notes

- This specification intentionally avoids speculative extensibility features such as generic metadata fields unless there is a concrete present-day need.
- Flutter's default Material widgets are an acceptable UI basis for the product because the interface is minimal and utility-focused.
