# CONTRIBUTE.md

## Scope

This guide explains how to contribute to the OpenBSD porting effort across the three repositories:

1. `openbsd-opencode-port` (orchestration/docs/scripts)
2. `bun-openbsd` (Bun OpenBSD fork/snapshot)
3. `opencode-openbsd` (OpenCode OpenBSD fork/snapshot)

Use this as the public contribution workflow reference. Detailed local planning notes and private operator logistics should stay out of the published repo.

## Contribution Model

### Which repo should a change go into?

- `openbsd-opencode-port`
  - docs, runbooks, scripts, test automation, release process notes
- `bun-openbsd`
  - Bun runtime/toolchain/OpenBSD compatibility fixes
- `opencode-openbsd`
  - OpenCode/OpenTUI/OpenBSD integration fixes and OpenBSD-specific behavior changes

If a change spans repos, split it into reviewable commits and cross-reference the related commits in commit messages or release notes.

## Branch Strategy

### `openbsd-opencode-port`

- `main` is the active branch.
- Keep operational docs current and concise.
- Avoid committing local-only planning files, secrets, or machine-specific dumps.

### `opencode-openbsd`

- `main` = active development / integration branch
- `stable/openbsd-0.1` = tested stable branch for consumers
- tags = immutable tested snapshots (for example `openbsd-stable-YYYYMMDD`)

Promotion flow:
1. Develop and test on `main`
2. Run baseline + visible TUI validation
3. Promote tested fixes to `stable/openbsd-0.1`
4. Tag the stable commit

### `bun-openbsd`

- `main` is the active porting branch unless a release/stable branch is introduced later.
- Keep OpenBSD-specific changes reviewable and separated from upstream sync commits when possible.

## Before You Commit

1. Read `RELEASE.md` to understand current status, risks, and release criteria.
2. Follow `OPENCODE-PORT-BUILD-GUIDE.md` for build expectations.
3. Run baseline validation:
   - `./scripts/test/run-openbsd-baseline.sh <your-openbsd-host>`
4. Run visible TUI checks when the change may affect interaction/rendering/input:
   - `./scripts/test/run-visible-tui-tests.sh <your-openbsd-host>`
5. Update docs when behavior, commands, or expectations change.

## Commit Guidance

- Keep commits focused and reviewable.
- Use descriptive commit messages that explain what changed and why.
- Prefer separate commits for:
  - code changes
  - test/script changes
  - documentation updates
- If a workaround is temporary, say so in the commit message and docs.

## Publishing to GitHub and SourceHut

Each repo is mirrored to both GitHub and SourceHut.

Recommended practice:
1. Push the same commit graph to both remotes.
2. Push branches first, then tags.
3. Verify the README and branch/tag visibility on both hosts.

Typical remote names used in this project:
- `github`
- `sourcehut`

Example push sequence (`opencode-openbsd`):

```sh
git push github main
git push github stable/openbsd-0.1
git push github openbsd-stable-YYYYMMDD

git push sourcehut main
git push sourcehut stable/openbsd-0.1
git push sourcehut openbsd-stable-YYYYMMDD
```

## Documentation Policy

Keep the published repo focused on a small set of operational docs.

Prefer:
- build guide
- release status/readiness summary
- contribution workflow
- changelog/engineering history (when historical context matters)

Avoid publishing:
- private planning scratch notes
- machine-specific credentials or host details beyond sanitized placeholders
- redundant planning files whose content has been consolidated elsewhere

## Release/Promotion Expectations

Before calling a state stable:
1. Baseline automation passes
2. Interactive TUI validation passes in source and compiled modes
3. Known issues are either fixed or explicitly documented with mitigations
4. Rebuild instructions and verification steps remain accurate

## OpenBSD Ports Note

This repo does not make the project installable via `pkg_add` by itself.
Official `pkg_add` availability requires acceptance into the OpenBSD ports tree and successful bulk builds.
