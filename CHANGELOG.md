# Changelog

This file tracks current and future project changes.

Historical porting notes and deep engineering logs were moved to HISTORY.md.

## Unreleased

### Documentation
- Renamed the legacy engineering changelog to HISTORY.md.
- Added a clean forward-looking CHANGELOG.md for ongoing maintenance work.
- Updated status docs to reflect current build/runtime risks and remediation priorities.

### Known Priority Work (in progress)
- Bun/OpenBSD syscall correctness review (poll/ppoll dispatch).
- Bun/OpenBSD getFdPath error semantics and cwd-mutation workaround hardening.
- OpenCode source build cleanliness and clean-clone reproducibility alignment.
- Port/orchestration artifact metadata and packaging script cleanup.
