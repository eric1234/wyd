## Summary

<!-- Describe what changed and why. Keep the PR focused on one behavior or concern. -->

## Scope

<!-- Note affected areas such as tray/menu behavior, prompts, reports, settings, persistence, startup, idle detection, tests, docs, or platform adapters. -->

## Testing

<!-- List commands and manual checks run. Explain any checks that were not run. -->

- [ ] `dart format .`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] Relevant integration test script: `./tool/run_integration_tests.sh linux` or `./tool/run_integration_tests.sh macos`
- [ ] Manual desktop smoke test, if tray, startup, idle detection, or window behavior changed

## Platform Impact

<!-- Describe Linux and macOS impact. Include distro/desktop-environment details for Linux-specific changes. -->

- [ ] Linux behavior considered
- [ ] macOS behavior considered
- [ ] Windows is not treated as a supported runtime target

## Screenshots or Recordings

<!-- Add screenshots, recordings, or a short behavior description for UI changes. Remove this section if not applicable. -->

## Documentation

<!-- Note README/CONTRIBUTING/user-facing doc updates, or explain why none are needed. -->

## Privacy and Local Data

- [ ] This PR does not include generated build output, local databases, secrets, or unsanitized logs.
- [ ] Any included logs or screenshots remove private task names, local paths, and personal data.

## Checklist

- [ ] The change preserves `wyd` as a small, local-first tray/menu-bar utility.
- [ ] Relevant tests were added or updated, or the reason they are not needed is explained.
- [ ] Platform-specific behavior goes through existing adapter boundaries where practical.
- [ ] Activity-log and persistence changes preserve append-only task-history semantics.
