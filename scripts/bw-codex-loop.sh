#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/bw-codex-loop.sh prime
  scripts/bw-codex-loop.sh ready
  scripts/bw-codex-loop.sh seed-fable [review-dir]
  scripts/bw-codex-loop.sh start <issue-id> [slug]
  scripts/bw-codex-loop.sh prompt <issue-id>
  scripts/bw-codex-loop.sh run [--parent <epic-id>] [--limit N] [--dry-run] [--continue-on-error] [--no-watch]
  scripts/bw-codex-loop.sh quality
  scripts/bw-codex-loop.sh pr <issue-id> <pr-url>
  scripts/bw-codex-loop.sh finish <issue-id> <pr-url>
  scripts/bw-codex-loop.sh skip <issue-id> <reason>

Environment:
  BASE_REF        Base ref for new worktrees. Default: origin/main
  WORKTREE_ROOT  Parent directory for worktrees. Default: parent of repo root
  EPIC_ID        Default parent epic for run.
  EPIC_TITLE     seed-fable epic title. Default: Architecture review remediation
  CODEX_EXEC_MODE Codex exec privilege mode. Default: bypass.
                  Values: bypass, sandbox.

Flow:
  1. seed-fable imports markdown findings into Beadwork once.
  2. ready shows unblocked work.
  3. start creates a worktree branch and marks the issue in progress.
  4. prompt prints the Codex worker prompt for that issue.
  5. run loops over open/in-progress child bugs, one branch and PR per issue.
  6. finish closes the Beadwork issue only after the PR is green.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

script_path() {
  local source_dir
  source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s/%s\n' "$source_dir" "$(basename "${BASH_SOURCE[0]}")"
}

repo_root() {
  git rev-parse --show-toplevel
}

slugify() {
  tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g' |
    cut -c 1-48
}

issue_title() {
  local id="$1"
  bw show "$id" --json |
    sed -nE 's/^  "title": "(.*)",$/\1/p' |
    sed 's/\\"/"/g'
}

issue_status() {
  local id="$1"
  bw show "$id" --json |
    sed -nE 's/^  "status": "([^"]+)".*/\1/p' |
    head -1
}

repo_name() {
  basename "$(repo_root)"
}

worktree_root() {
  local root
  root="$(repo_root)"
  printf '%s\n' "${WORKTREE_ROOT:-$(dirname "$root")}"
}

issue_slug() {
  local id="$1"
  local explicit_slug="${2:-}"

  if [[ -n "$explicit_slug" ]]; then
    printf '%s' "$explicit_slug" | slugify
  else
    issue_title "$id" | slugify
  fi
}

issue_branch() {
  local id="$1"
  local explicit_slug="${2:-}"
  local slug

  slug="$(issue_slug "$id" "$explicit_slug")"
  [[ -n "$slug" ]] || slug="work"
  printf '%s/%s\n' "$id" "$slug"
}

issue_worktree() {
  local id="$1"
  printf '%s/%s-%s\n' "$(worktree_root)" "$(repo_name)" "$id"
}

priority_for_severity() {
  case "$1" in
    High*) echo 1 ;;
    Medium*) echo 2 ;;
    Low*) echo 3 ;;
    *) echo 2 ;;
  esac
}

epic_id_by_title() {
  local title="$1"
  bw list --all --type epic --grep "$title" --json |
    sed -nE 's/^    "id": "([^"]+)".*/\1/p' |
    head -1
}

comment() {
  local id="$1"
  local body="$2"
  bw comment "$id" "$body" >/dev/null
}

print_prompt() {
  local id="$1"
  local title runner
  title="$(issue_title "$id")"
  runner="$(script_path)"

  cat <<PROMPT
Work Beadwork ticket $id only: $title

Rules:
- Run \`bw prime\` and \`bw show $id\` first.
- Verify the issue exists in the codebase, preferably with a focused failing ExUnit test.
- If it cannot be validated, do not fix it. Comment the evidence and use:
  \`${runner} skip $id not-reproducible\`
- If the minimal fix expands into unrelated architecture, stop. Comment the scope issue and use:
  \`${runner} skip $id scope-expanded\`
- Otherwise make the smallest idiomatic Elixir/OTP fix.
- Prefer pure agent tests first, then AgentServer/runtime integration tests.
- Avoid \`Process.sleep/1\`; use \`JidoTest.Eventually\` helpers for async assertions.
- Run the targeted test, then \`mix test\`, then \`mix q\` or \`mix quality\`.
- Commit with a Conventional Commit that references $id.
- Push the branch and open a non-draft PR.
- Do not close $id until GitHub checks are green.
PROMPT
}

seed_fable() {
  local review_dir="${1:-fable/review}"
  local epic_title="${EPIC_TITLE:-Architecture review remediation}"
  local epic_description
  local epic_id

  [[ -d "$review_dir" ]] || die "review directory not found: $review_dir"

  epic_id="$(epic_id_by_title "$epic_title")"
  if [[ -z "$epic_id" ]]; then
    epic_description="Imported architecture-review findings from ${review_dir}. Each child issue should be validated with a failing test before implementation. Close skipped findings with an evidence-backed reason."
    epic_id="$(bw create "$epic_title" --type epic --priority 1 --description "$epic_description" --silent)"
    bw label "$epic_id" +architecture-review +fable >/dev/null
    echo "created epic $epic_id"
  else
    echo "using existing epic $epic_id"
  fi

  local file number title severity priority location body description child_id existing_id
  for file in "$review_dir"/[0-9][0-9]-*.md; do
    [[ -f "$file" ]] || continue

    number="$(basename "$file" | sed -E 's/^([0-9][0-9])-.*$/\1/')"
    [[ "$number" == "00" ]] && continue

    title="$(sed -nE '1s/^# [0-9][0-9] (—|-|:) //p' "$file")"
    [[ -n "$title" ]] || title="$(sed -nE '1s/^# //p' "$file")"
    severity="$(sed -nE 's/^\*\*Severity:\*\* *//p' "$file" | head -1)"
    location="$(sed -nE 's/^\*\*Location:\*\* *//p' "$file" | head -1)"
    priority="$(priority_for_severity "$severity")"

    existing_id="$(
      bw list --all --parent "$epic_id" --grep "F${number}:" --json |
        sed -nE 's/^    "id": "([^"]+)".*/\1/p' |
        head -1
    )"

    if [[ -n "$existing_id" ]]; then
      echo "skipping existing F${number} as $existing_id"
      continue
    fi

    body="$(cat "$file")"
    description="$(cat <<DESC
Source: ${file}
Finding: F${number}
Severity: ${severity}
Location: ${location}

Validation:
- Add or identify a failing test proving the issue.
- If not reproducible, comment evidence and close as skipped:not-reproducible.

Fix rules:
- Smallest idiomatic Elixir/OTP fix.
- Do not expand into unrelated architecture.
- If scope expands, comment evidence and close as skipped:scope-expanded.

Done:
- Targeted test fails before fix and passes after.
- mix test passes.
- mix q or mix quality passes.
- PR opened and GitHub checks are green.

---

${body}
DESC
)"

    child_id="$(
      bw create "F${number}: ${title}" \
        --type bug \
        --priority "$priority" \
        --parent "$epic_id" \
        --description "$description" \
        --silent
    )"
    bw label "$child_id" +architecture-review +fable +"severity-p${priority}" >/dev/null
    echo "created $child_id F${number}"
  done

  bw sync
}

start_issue() {
  local id="$1"
  local explicit_slug="${2:-}"
  local base_ref branch worktree

  base_ref="${BASE_REF:-origin/main}"
  branch="$(issue_branch "$id" "$explicit_slug")"
  worktree="$(issue_worktree "$id")"

  prepare_issue_worktree "$id" "$branch" "$worktree" "$base_ref" 0

  echo "Worktree: $worktree"
  echo "Branch:   $branch"
  echo
  print_prompt "$id"
}

run_quality() {
  if mix help quality >/dev/null 2>&1; then
    mix quality
  else
    mix q
  fi
}

record_pr() {
  local id="$1"
  local pr_url="$2"
  comment "$id" "PR opened: ${pr_url}"
  bw sync
}

finish_issue() {
  local id="$1"
  local pr_url="$2"
  comment "$id" "Completed after green checks: ${pr_url}"
  bw close "$id" --reason completed
  bw sync
}

skip_issue() {
  local id="$1"
  local reason="$2"
  comment "$id" "Skipped: ${reason}"
  bw close "$id" --reason "skipped:${reason}"
  bw sync
}

prepare_issue_worktree() {
  local id="$1"
  local branch="$2"
  local worktree="$3"
  local base_ref="$4"
  local dry_run="${5:-0}"
  local status current_branch

  if [[ "$dry_run" == "1" ]]; then
    echo "[dry-run] would fetch origin"
    if [[ -e "$worktree" ]]; then
      echo "[dry-run] would reuse worktree $worktree"
    elif git show-ref --verify --quiet "refs/heads/${branch}"; then
      echo "[dry-run] would create worktree $worktree from existing branch $branch"
    else
      echo "[dry-run] would create worktree $worktree with branch $branch from $base_ref"
    fi
    echo "[dry-run] would start $id if it is open"
    return
  fi

  git fetch origin

  if [[ -e "$worktree" ]]; then
    [[ -e "$worktree/.git" ]] || die "worktree path exists but is not a git worktree: $worktree"
    current_branch="$(git -C "$worktree" branch --show-current)"
    [[ "$current_branch" == "$branch" ]] ||
      die "worktree $worktree is on $current_branch, expected $branch"
    echo "reusing worktree $worktree"
  elif git show-ref --verify --quiet "refs/heads/${branch}"; then
    git worktree add "$worktree" "$branch"
  else
    git worktree add -b "$branch" "$worktree" "$base_ref"
  fi

  status="$(issue_status "$id")"
  case "$status" in
    open)
      bw start "$id"
      comment "$id" "Started branch ${branch} in worktree ${worktree} from ${base_ref}."
      bw sync
      ;;
    in_progress)
      echo "issue $id is already in progress"
      ;;
    closed)
      echo "issue $id is already closed"
      ;;
    *)
      die "unsupported Beadwork status for $id: $status"
      ;;
  esac
}

default_run_parent() {
  if [[ -n "${EPIC_ID:-}" ]]; then
    printf '%s\n' "$EPIC_ID"
    return
  fi

  epic_id_by_title "${EPIC_TITLE:-Architecture review remediation}"
}

run_issue_ids() {
  local parent="$1"
  local limit="$2"
  local jq_filter

  jq_filter='.[] | select(.parent == $parent and .type == "bug" and (.status == "open" or .status == "in_progress")) | .id'
  if [[ -n "$limit" ]]; then
    bw list --all --parent "$parent" --json |
      jq -r --arg parent "$parent" "$jq_filter" |
      head -n "$limit"
  else
    bw list --all --parent "$parent" --json |
      jq -r --arg parent "$parent" "$jq_filter"
  fi
}

run_one_issue() {
  local id="$1"
  local dry_run="$2"
  local watch_checks="$3"
  local base_ref branch worktree prompt pr_url status runner

  base_ref="${BASE_REF:-origin/main}"
  branch="$(issue_branch "$id")"
  worktree="$(issue_worktree "$id")"
  runner="$(script_path)"

  echo "==> $id"
  echo "branch:   $branch"
  echo "worktree: $worktree"

  prepare_issue_worktree "$id" "$branch" "$worktree" "$base_ref" "$dry_run"

  if [[ "$dry_run" == "1" ]]; then
    if [[ "${CODEX_EXEC_MODE:-bypass}" == "sandbox" ]]; then
      echo "[dry-run] would run: codex exec --cd \"$worktree\" --sandbox danger-full-access \"\$(${runner} prompt $id)\""
    else
      echo "[dry-run] would run: codex exec --cd \"$worktree\" --dangerously-bypass-approvals-and-sandbox \"\$(${runner} prompt $id)\""
    fi
    echo "[dry-run] would inspect PR with: gh pr view --json url -q .url"
    if [[ "$watch_checks" == "1" ]]; then
      echo "[dry-run] would watch checks with: gh pr checks --watch"
      echo "[dry-run] would close $id after green checks"
    else
      echo "[dry-run] would record the PR URL and leave $id open"
    fi
    return 0
  fi

  prompt="$(print_prompt "$id")"
  if [[ "${CODEX_EXEC_MODE:-bypass}" == "sandbox" ]]; then
    if ! codex exec --cd "$worktree" --sandbox danger-full-access "$prompt"; then
      comment "$id" "Automation stopped: codex exec failed for branch ${branch}."
      bw sync
      return 1
    fi
  else
    if ! codex exec --cd "$worktree" --dangerously-bypass-approvals-and-sandbox "$prompt"; then
      comment "$id" "Automation stopped: codex exec failed for branch ${branch}."
      bw sync
      return 1
    fi
  fi

  status="$(issue_status "$id")"
  if [[ "$status" == "closed" ]]; then
    echo "issue $id was closed during Codex run"
    return 0
  fi

  pr_url="$(cd "$worktree" && gh pr view --json url -q .url 2>/dev/null || true)"
  if [[ -z "$pr_url" ]]; then
    comment "$id" "Automation stopped: Codex finished without an open PR for branch ${branch}."
    bw sync
    echo "no PR found for $id on branch $branch" >&2
    return 1
  fi

  record_pr "$id" "$pr_url"

  if [[ "$watch_checks" != "1" ]]; then
    comment "$id" "Automation recorded PR without watching checks: ${pr_url}"
    bw sync
    echo "PR recorded without watching checks: $pr_url"
    return 0
  fi

  if (cd "$worktree" && gh pr checks --watch); then
    finish_issue "$id" "$pr_url"
  else
    comment "$id" "Automation stopped: GitHub checks failed or did not complete successfully for ${pr_url}."
    bw sync
    echo "checks failed for $id: $pr_url" >&2
    return 1
  fi
}

run_loop() {
  local parent=""
  local limit=""
  local dry_run=0
  local continue_on_error=0
  local watch_checks=1
  local ids=()
  local id

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --parent)
        [[ $# -ge 2 ]] || die "--parent requires an epic id"
        parent="$2"
        shift 2
        ;;
      --limit)
        [[ $# -ge 2 ]] || die "--limit requires a count"
        limit="$2"
        [[ "$limit" =~ ^[0-9]+$ ]] || die "--limit must be a positive integer"
        shift 2
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      --continue-on-error)
        continue_on_error=1
        shift
        ;;
      --no-watch)
        watch_checks=0
        shift
        ;;
      *)
        die "unknown run option: $1"
        ;;
    esac
  done

  need_cmd jq
  if [[ "$dry_run" != "1" ]]; then
    need_cmd codex
    need_cmd gh
  fi

  [[ -n "$parent" ]] || parent="$(default_run_parent)"
  [[ -n "$parent" ]] || die "no parent epic found; pass --parent <epic-id> or set EPIC_ID"

  while IFS= read -r id; do
    [[ -n "$id" ]] && ids+=("$id")
  done < <(run_issue_ids "$parent" "$limit")
  if [[ "${#ids[@]}" -eq 0 ]]; then
    echo "no open or in-progress child bug issues found for $parent"
    return 0
  fi

  echo "parent: $parent"
  echo "issues: ${ids[*]}"
  if [[ "$dry_run" == "1" ]]; then
    echo "mode: dry-run"
  fi

  for id in "${ids[@]}"; do
    if ! run_one_issue "$id" "$dry_run" "$watch_checks"; then
      if [[ "$continue_on_error" == "1" ]]; then
        echo "continuing after failure for $id" >&2
      else
        return 1
      fi
    fi
  done
}

main() {
  need_cmd git
  need_cmd bw

  local cmd="${1:-}"
  case "$cmd" in
    prime)
      bw prime
      ;;
    ready)
      bw ready
      ;;
    seed-fable)
      seed_fable "${2:-fable/review}"
      ;;
    start)
      [[ $# -ge 2 ]] || die "usage: $0 start <issue-id> [slug]"
      start_issue "$2" "${3:-}"
      ;;
    prompt)
      [[ $# -eq 2 ]] || die "usage: $0 prompt <issue-id>"
      print_prompt "$2"
      ;;
    run|run-all)
      shift
      run_loop "$@"
      ;;
    quality)
      run_quality
      ;;
    pr)
      [[ $# -eq 3 ]] || die "usage: $0 pr <issue-id> <pr-url>"
      record_pr "$2" "$3"
      ;;
    finish)
      [[ $# -eq 3 ]] || die "usage: $0 finish <issue-id> <pr-url>"
      finish_issue "$2" "$3"
      ;;
    skip)
      [[ $# -ge 3 ]] || die "usage: $0 skip <issue-id> <reason>"
      skip_issue "$2" "${*:3}"
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      die "unknown command: $cmd"
      ;;
  esac
}

main "$@"
