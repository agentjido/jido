# Example layout plan

Status: Implemented on `v3-spike`.

## Changes

1. Move `lib/examples/` to root `examples/`. Compile examples in development
   and test only. Retain the explicit Hex file list for core code and guides.
2. Move the ten application scenarios from `test/integration` into
   `examples/08_applications` and `test/examples/08_applications`. Compile their
   Agent and Plugin modules as `.ex` files. Remove fixture `Code.require_file`
   calls and the misleading `example_test.exs` filenames.
3. Use one ExUnit selection tag, `:example`. Define default exclusions once in
   `test/test_helper.exs`. `mix examples` runs all example tests. Explicit CI
   paths retain the existing application checks.
4. Update formatter, Credo, coverage, links, and demo paths. Keep generated API
   docs limited to core modules and link to example source on GitHub. Keep the
   90% core coverage requirement and target above 93%.
5. Verify the default selection, complete suite, quality checks, docs, a clean
   production build, and the contents of a Hex archive. Commit to `v3-spike`.

## Test ownership

The two old trees had overlapping topics but different obligations. Preserve
those checks in one example test tree. Do not delete tests based on names alone.

| Topic | Small example proves | Application example adds |
| --- | --- | --- |
| ReAct | Tool bounds, cancellation, transcript commit | Scheduled follow-up and history across later Turns |
| Inbox | Stable event ID rejection at admission | Input Plugin burst handling and runtime restart |
| Audit | Durable outbox intent and idempotent delivery | Flow failure and Plugin runtime outcomes |
| Child work | Correlation, cancellation, child failure | Ordered Flow directives and scheduled timeout |
| Agent groups | Bounded workers and declarative topology | Bus coordination, scaling, reclaim, and drain |
| Identity and subscription | Core Signal and Plugin contracts | Signed/encrypted exchanges and runtime reconciliation |

Core tests already own several remote, observation, and persistence acceptance
checks. Their example README files continue to link to those checks. Core tests
can reuse compiled example fixtures without becoming optional example tests.
All existing assertions remain enabled in the complete suite, including the 11
known research failures and the one approved DIST-03 exclusion.

See the [current test commands](../../guides/testing.md) and
[example catalog](../../examples/README.md). Older result logs retain historical
commands; their file links point to the current locations.

## Verification on 2026-09-06

| Check | Result |
| --- | --- |
| Default selection | 959 core tests selected; all 303 example tests excluded |
| `mix examples` selection | All 303 example tests selected, including 13 application tests |
| Complete suite with coverage | 1,251 passed; the same 11 research failures; one approved DIST-03 exclusion |
| Core coverage | 93.6%; repository minimum remains 90% |
| `mix quality` | Format, compile, Credo, and Dialyzer passed |
| Docs with warnings as errors | Passed; core API pages and GitHub example links checked |
| Clean production build | 183 core modules; no example or test source modules |
| Hex archive | 155 entries; no example or test files |
| Development smoke test | Moved Minimal Agent increments its state correctly |

Test bodies were compared before and after the move. Only module names, file
loading, and selection tags changed. No assertion was removed. Updated relative
links resolve, and no source module has a second definition.
