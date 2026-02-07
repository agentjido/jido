---
name: hex-release
description: "Guides interactive Hex package release. Bumps version in mix.exs, updates CHANGELOG with commits, creates git tag. Triggers on: release, hex publish, bump version, new release."
---

# Hex Release (Human-in-the-Loop)

Interactive workflow for releasing a Hex package with manual verification at each step.

## When to Use

Use this skill when asked to:
- Release a new version to Hex
- Bump the package version
- Prepare a release
- Create a release tag

## Pre-flight Checks

Before starting, run these checks automatically:

### 1. Git Status
```bash
git status --porcelain
```
If dirty, **STOP** and ask user to commit or stash changes first.

### 2. Run Tests
```bash
mix test
```
If tests fail, **STOP** and show failures. Do not proceed until all tests pass.

### 3. Run Quality Checks
```bash
mix quality
```
This runs: format check, compile with warnings-as-errors, credo, and dialyzer.
If any check fails, **STOP** and show the issues.

### 4. Run Doctor
```bash
mix doctor
```
Review documentation coverage. Warn user of any missing docs but allow proceeding.

### 5. Verify Branch
```bash
git branch --show-current
```
Confirm user is on expected branch (usually `main`).

**SHOW USER**: Summary of all pre-flight results.

**ASK USER**: "All checks passed. Current version is X.Y.Z. What version should this release be?"

## Workflow

### Step 1: Determine Version Bump

Ask the user what type of release:
- **major**: Breaking changes (X.0.0)
- **minor**: New features, backwards compatible (X.Y.0)
- **patch**: Bug fixes only (X.Y.Z)
- **rc**: Release candidate (X.Y.Z-rc.N)
- **specific**: User provides exact version string

### Step 2: Collect Commits for CHANGELOG

Run:
```bash
git log --oneline $(git describe --tags --abbrev=0)..HEAD
```

Categorize commits into:
- **Added**: New features
- **Changed**: Changes in existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security fixes

**SHOW USER**: The proposed CHANGELOG entry formatted as:
```markdown
## [NEW_VERSION] - YYYY-MM-DD

### Added
- ...

### Changed
- ...

### Fixed
- ...
```

**ASK USER**: "Does this CHANGELOG entry look correct? Any edits needed?"

### Step 3: Update mix.exs Version

Edit the `@version` module attribute in mix.exs:
```elixir
@version "NEW_VERSION"
```

**SHOW USER**: The diff of the version change.

**ASK USER**: "Version updated to NEW_VERSION. Proceed?"

### Step 4: Update CHANGELOG.md

Prepend the new version section after the header (after line 6, before the first version entry).

**SHOW USER**: The CHANGELOG diff.

**ASK USER**: "CHANGELOG updated. Proceed?"

### Step 5: Create Release Commit

```bash
git add mix.exs CHANGELOG.md
git commit -m "chore(release): v{NEW_VERSION}"
```

**SHOW USER**: The commit details.

### Step 6: Create Git Tag

```bash
git tag -a v{NEW_VERSION} -m "Release v{NEW_VERSION}"
```

**SHOW USER**: Tag created confirmation.

### Step 7: Final Instructions

**TELL USER**:
```
✅ Release v{NEW_VERSION} prepared!

To publish, run these commands:

  git push origin main
  git push origin v{NEW_VERSION}
  mix hex.publish

After publishing, verify at:
  https://hex.pm/packages/jido
```

## Rollback

If something goes wrong before pushing:
```bash
git reset --soft HEAD~1  # Undo commit
git tag -d v{NEW_VERSION}  # Delete tag
git checkout mix.exs CHANGELOG.md  # Restore files
```

## Notes

- This skill does NOT automatically push or publish
- The automated GitHub Action release is a separate workflow
- Always verify the CHANGELOG before proceeding
- Use conventional commit format for the release commit
