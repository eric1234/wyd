Purpose: App stops active tracking on suspend/resume or lock and excludes away time

Scenario: User suspends/resumes laptop
1. Run app
2. Input/select task
3. Wait 2 minutes to accumulate time
4. Suspend machine
5. Wait 3 minutes
6. Resume machine
7. Confirm quick entry is already waiting or appears immediately after resume
8. Press Enter and confirm tracking resumes the previous task
9. Secondary click on tray icon
10. Select "Report"
11. Confirm only 2 minutes of time on the initial task

Scenario: User locks screen and returns
1. Run app
2. Input/select task
3. Wait 2 minutes to accumulate time
4. Lock screen
5. Wait 3 minutes
6. Unlock screen
7. Confirm quick entry is already waiting or appears immediately after unlock
8. Press Enter and confirm tracking resumes the previous task
9. Secondary click on tray icon
10. Select "Report"
11. Confirm only 2 minutes of time on the initial task

Scenario: System suspends without active task
1. Run app
2. Close quick entry window without specifing a task
3. Suspend machine
4. Resume machine
5. Confirm quick entry is not displaying
6. Confirm time is not being tracked.

Scenario: System locks without active task
1. Run app
2. Close quick entry window without specifing a task
3. Lock machine
4. Unlock machine
5. Confirm quick entry is not displaying
6. Confirm time is not being tracked.
