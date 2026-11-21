# 03_15 Human Approval

A request waits for one approval, denial, or expiry event and then returns the
selected result.

## What you will learn

- How a Flow combines a submitted request with a bounded selection wait.
- How one addressed event resumes only the matching request.

## Read the code

Read [the Flow](human_approval.ex) first. Then read
[the integration proof](human_approval_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_15_human_approval --warnings-as-errors`

Expected result: the matching approval event resumes the Flow and returns an
approved request with its submission effect.

## Important behavior

The request ID is part of the wait match. An unrelated approval cannot resume
the request. The timer gives the wait a finite expiry path.

## Limits

This lesson does not prove durable recovery after a process or BEAM failure.
Chapter 13 owns those recovery claims.

## Core Fit and Gaps

The Flow DSL expresses the three-way wait and correlation rule directly. The
current proof still uses internal deterministic wait support. A later pass must
replace that support with a public durable execution boundary before this is a
complete public integration example.

## Files

- [Flow](human_approval.ex)
- [Tests](human_approval_test.exs)
