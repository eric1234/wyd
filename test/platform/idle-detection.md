Purpose: User is not interrupted to confirm task

Scenario: User is actively typing

1. Run app
2. Secondary click on tray icon
3. Select "Settings"
4. Set `1` minute for "Reminder interval"
5. Input/select task
6. Type one character per second for 2 minutes
7. Confirm confirmation window never shows
8. Wait 2 minutes
9. Confirm confirmation window shows

Scenario: User is not actively using mouse

1. Continue from previous scenario
5. Input/select task
6. Move mouse every 10 seconds for 2 minutes
7. Confirm confirmation window never shows
8. Wait 2 minutes
9. Confirm confirmation window shows
