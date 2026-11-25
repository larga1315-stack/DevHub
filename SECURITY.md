# Security Policy

DevHub runs commands on your Mac and launches an AI coding agent against your source code, so security reports are taken seriously.

## Reporting a vulnerability

Please **do not open a public issue**. Use GitHub's private reporting instead:
**Security → Report a vulnerability** on this repository.

Include what you found, how to reproduce it, and the impact. You'll get a response within 7 days.

## Design guarantees (and where to look in the code)

| Guarantee | Where |
|---|---|
| Claude Code gets file tools only (`Read, Edit, Write, Grep, Glob`); `Bash`, `WebFetch`, `WebSearch` are denied | `FixSession.claudeArguments` |
| Log and build output is passed as untrusted data inside tags, never as instructions | `FixSession.systemGuard`, `crashPrompt` |
| Secrets are redacted before anything is sent to Claude or written to history | `Redactor`, `CrashRecord.init(report:)` |
| Untrusted text never passes through a shell (argument arrays only) | `Shell.run` |
| Only files inside the project folder are included in prompts (no path traversal) | `CrashDetector.resolve` |
| Every fix starts from a git snapshot and needs explicit approval; rejecting restores it | `Git.snapshot`, `Git.restore` |
| Process termination: own user only, never PID ≤ 100 or DevHub itself, always confirmed | `ProcessControl.terminate` |

Each guarantee has unit tests in `Tests/DevHubCoreTests`.

## Known limitations

- Secret redaction is pattern-based (best effort), not a guarantee.
- Release builds from `scripts/build-app.sh` are ad-hoc signed and not notarized.
