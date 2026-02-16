---
name: hex-release
description: "Guides interactive Hex package release for AgentJido repos. Supports automated (GitHub Actions workflow_dispatch) and manual release flows. Uses git_ops for version bumping and changelog generation. Triggers on: release, hex publish, bump version, new release, publish package."
---

# Hex Release (Human-in-the-Loop)

Interactive workflow for releasing a Hex package with manual verification at each step.
Supports two release paths: **automated** (via GitHub Actions) and **manual** (local).

## When to Use

Use this skill when asked to:
- Release a new version to Hex
- Bump the package version
- Prepare a release
- Create a release tag
- Trigger a release workflow

## Pre-flight Checks

Before starting, run these checks automatically:

### 1. Identify the Package

Read `mix.exs` to determine:
- Package name (from `project()` → `:name` or `:app`)
- Current version (from `@version` or `project()` → `:version`)
- Whether it has `git_ops` as a dependency (required for automated release)

### 2. Check for Git Dependencies

```bash
grep -E 'github:|git:|path:' mix.exs
```

Categorize any git/path deps found:
- **dev/test only** (`only: [:dev, :test]`): Will not block Hex publish — note but continue
- **runtime deps**: **STOP** — these block `mix hex.publish`. Tell the user which deps need to be published to Hex first or switched to Hex versions

### 3. Git Status

```bash
git status --porcelain
```
If dirty, **STOP** and ask user to commit or stash changes first.

### 4. Verify Branch

```bash
git branch --show-current
```
Confirm user is on `main`. Warn if on a different branch.

### 5. Check for Releasable Commits

```bash
git log --oneline $(git describe --tags --abbrev=0 2>/dev/null || echo "")..HEAD
```
If no commits since last tag, **STOP** — nothing to release.

Review commits and confirm they follow conventional commit format (`feat:`, `fix:`, `chore:`, etc.).
Non-conventional commits won't be picked up by `git_ops` for the CHANGELOG.

### 6. Run Tests

```bash
mix test
```
If tests fail, **STOP** and show failures.

### 7. Run Quality Checks

```bash
mix quality
```
This typically runs: format check, compile with warnings-as-errors, credo, and dialyzer.
If the alias doesn't exist, run `mix format --check-formatted && mix compile --warnings-as-errors` as a minimum.
If any check fails, **STOP** and show the issues.

### 8. Hex Publish Dry Run

```bash
mix hex.publish --dry-run
```
Verify the package metadata and file list look correct. If this fails, **STOP**.

**SHOW USER**: Summary of all pre-flight results and current version.

**ASK USER**: "All checks passed. Which release path: **automated** (GitHub Actions) or **manual** (local)?"

---

## Path A: Automated Release (GitHub Actions)

The AgentJido repos have a reusable release workflow triggered via `workflow_dispatch`.

### Step 1: Confirm Workflow Exists

Check that `.github/workflows/release.yml` exists and calls:
```yaml
uses: agentjido/github-actions/.github/workflows/elixir-release.yml@main
```

### Step 2: Explain Dispatch Options

**TELL USER**:
```
The release workflow supports these options:

  • dry_run: true     — Full dry run (no git push, no tag, no Hex publish)
  • hex_dry_run: true — Runs git_ops release + push, but skips actual Hex publish
  • skip_tests: true  — Skip test step (use if CI already passed)

Recommended first run: dry_run: true
```

### Step 3: Trigger the Workflow

**Option 1 — GitHub CLI** (if `gh` is available):
```bash
# Dry run first
gh workflow run release.yml -f dry_run=true

# Watch the run
gh run list --workflow=release.yml --limit=1
gh run watch
```

**Option 2 — GitHub UI**:
```
1. Go to: https://github.com/agentjido/{REPO}/actions/workflows/release.yml
2. Click "Run workflow"
3. Set dry_run = true for first attempt
4. Click "Run workflow"
```

**ASK USER**: "Run a dry run first? (recommended)"

### Step 4: Verify Dry Run Results

After the dry run completes:
```bash
gh run view --log-failed  # Check for errors
```

Review the workflow summary for:
- Version that would be released
- Hex publish dry-run output
- Any skipped steps

**ASK USER**: "Dry run succeeded. Ready to run the real release?"

### Step 5: Trigger Real Release

```bash
gh workflow run release.yml
# Or with skip_tests if CI already passed:
gh workflow run release.yml -f skip_tests=true
```

### Step 6: Verify

```bash
gh run watch  # Wait for completion
```

**TELL USER**:
```
✅ Release triggered!

The workflow will:
  1. Run git_ops.release to bump version + update CHANGELOG
  2. Push the release commit and tag
  3. Publish to Hex.pm
  4. Create a GitHub Release

Monitor at: https://github.com/agentjido/{REPO}/actions
After publish, verify at: https://hex.pm/packages/{PACKAGE}
```

---

## Path B: Manual Release (Local)

Use when the automated workflow isn't available, or for repos that can't publish to Hex (e.g., git deps blocking publish).

### Step 1: Determine Version Bump

`git_ops` handles this automatically from conventional commits, but ask the user for confirmation.

Run the release in dry-run mode to preview:
```bash
mix git_ops.release --dry-run
```

This shows what version would be bumped to based on commit types:
- `feat:` commits → minor bump
- `fix:` commits → patch bump
- `BREAKING CHANGE:` → major bump

**SHOW USER**: The proposed version bump and commits that will be included.

**ASK USER**: "git_ops wants to release vX.Y.Z. Proceed, or override with a specific version?"

### Step 2: Run the Release

```bash
# Let git_ops decide the version:
mix git_ops.release --yes

# Or force a specific version:
mix git_ops.release --yes --new-version X.Y.Z
```

This will:
- Bump the version in `mix.exs`
- Update `CHANGELOG.md` from conventional commits
- Create a release commit
- Create a git tag

**SHOW USER**: The release commit diff and tag.

### Step 3: Review Before Pushing

```bash
git log --oneline -3
git diff HEAD~1
git tag -l | tail -5
```

**ASK USER**: "Release commit and tag created locally. Ready to push?"

### Step 4: Push

```bash
git push origin main
git push origin --tags
```

### Step 5: Publish to Hex

```bash
# Final dry-run check
mix hex.publish --dry-run

# Publish
mix hex.publish --yes
```

### Step 6: Create GitHub Release

```bash
VERSION="v$(grep -m1 '@version "' mix.exs | sed 's/.*"\(.*\)".*/\1/')"
gh release create "$VERSION" \
  --title "Release $VERSION" \
  --notes "See [CHANGELOG.md](CHANGELOG.md) for details."
```

**TELL USER**:
```
✅ Release complete!

  Published: https://hex.pm/packages/{PACKAGE}
  GitHub:    https://github.com/agentjido/{REPO}/releases/tag/{VERSION}
```

---

## Rollback

### Before pushing:
```bash
git reset --soft HEAD~1          # Undo release commit
git tag -d v{VERSION}            # Delete local tag
git checkout mix.exs CHANGELOG.md  # Restore files
```

### After pushing but before Hex publish:
```bash
git push origin :refs/tags/v{VERSION}  # Delete remote tag
git revert HEAD                         # Revert release commit
git push origin main
```

### After Hex publish:
Hex packages **cannot be unpublished** after 1 hour. You can retire a version:
```bash
mix hex.retire {PACKAGE} {VERSION} invalid --message "Released in error"
```

---

## Notes

- All AgentJido repos use **conventional commits** — non-conventional commits are ignored by `git_ops`
- The `quality` mix alias varies per repo — check `mix.exs` aliases section
- `git_ops` is a dev-only dependency — release commands run in `MIX_ENV=dev`
- The automated workflow uses `GITHUB_TOKEN` for git push and `HEX_API_KEY` (org secret) for Hex publish
- Repos with runtime git dependencies (e.g., `jido_runic`) cannot publish to Hex — use manual path for git tag/release only, skip Hex publish step
