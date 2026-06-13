# Security Policy

## Supported Versions

`wyd` is a local-first desktop tray application for Linux and macOS. Security
fixes are made for the default branch and the latest published release, when a
release exists.

| Version | Supported |
| --- | --- |
| Default branch | Yes |
| Latest release | Yes |
| Older releases | No |
| Windows builds | No |

Windows runner files may exist in the repository from the Flutter template, but
Windows is not currently a supported runtime target for this project.

## Reporting a Vulnerability

Please report suspected vulnerabilities through GitHub private vulnerability
reporting for this repository. Use the **Security** tab and choose **Report a
vulnerability**.

Do not open a public issue, pull request, discussion, or social media post with
details of an unpatched vulnerability. If private vulnerability reporting is not
available, open a public issue that asks for a secure contact method without
including technical details.

Include as much of the following as practical:

- Affected `wyd` version, release, or commit SHA.
- Operating system and desktop environment, such as macOS, GNOME, KDE, or Xfce.
- Clear reproduction steps and the observed behavior.
- Expected security impact, including whether local task history, settings,
  startup configuration, or app control flow is affected.
- A proof of concept, if it is safe to share privately.
- Relevant logs or screenshots with personal task names, paths, and other
  sensitive local data removed.

Please do not attach a real `wyd` SQLite database or activity log unless it has
been minimized and sanitized. Task names and timelines can reveal sensitive
personal or work information.

## Scope

Security-relevant reports for this project may include, but are not limited to:

- Unauthorized access to, modification of, or disclosure of local activity data.
- Unsafe file permissions or storage behavior for the local SQLite database or
  settings.
- Vulnerabilities in tray, window, startup, idle-detection, single-instance, or
  multi-window behavior that allow unintended control of the app.
- Dependency or native desktop integration issues that materially affect `wyd`.
- Build, packaging, or release-process issues that could compromise users.

`wyd` does not intentionally provide a network service, cloud sync, account
system, or remote API. Reports that depend on those features are generally out
of scope unless such functionality is added later.

## Coordinated Disclosure

After a private report is received, maintainers will aim to:

- Acknowledge the report within 7 days.
- Provide an initial assessment within 14 days.
- Keep the reporter informed while a fix is developed and released.
- Coordinate public disclosure after a fix is available, when disclosure is
  appropriate.

Fix timelines depend on severity, exploitability, affected platforms, and the
availability of a safe patch. Credit will be given to reporters on request,
unless anonymity is preferred.

## Research Guidelines

Good-faith security research is welcome when it follows these guidelines:

- Test only your own systems and data.
- Avoid destructive actions, persistence, privacy violations, and data
  exfiltration.
- Stop testing and report promptly if you encounter sensitive information or a
  plausible vulnerability.
- Give maintainers a reasonable opportunity to fix the issue before public
  disclosure.

This project does not currently operate a bug bounty program. Reports are still
appreciated and will be handled through the coordinated disclosure process above.
