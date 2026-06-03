Purpose: Tray icon works correctly

Scenario: Launching app indicates time not being tracked
1. Run app
2. Tray icon displays as red icon
3. Hovering over icon indicates "No current task". Skip if on Linux
4. Nag window displays asking for new task

Scenario: Task Started

1. Resume from last scenario
2. Input task and submit
3. Confirm tray icon is now mask
4. Hovering over icon indicates task name. Skip if on Linux.
5. Nag window does not display
