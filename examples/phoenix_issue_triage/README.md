# Phoenix Issue Triage

This example is a larger showcase for the Phoenix + Pod story.

The core idea is simple:

- the public domain module defines the application API
- the nested pod module defines the durable runtime shape
- Phoenix code calls the domain module
- plugin subscriptions own long-lived sensors for the run
- named role nodes are backed by focused agent modules

That means the answer to "what is the API surface for interacting with a pod?"
is not "controllers should call `Jido.Pod` directly." The answer is:

> wrap a pod inside a domain module, and treat that domain module as the app
> boundary

## Shape

```text
examples/phoenix_issue_triage/
└── lib/examples/phoenix_issue_triage/
    ├── issue_triage.ex
    └── issue_triage/
        ├── actions/
        ├── agents/
        ├── plugins/
        ├── sensors/
        ├── artifacts.ex
        ├── policy.ex
        └── pod.ex
```

## Responsibilities

`IssueTriage`

- is the public domain API
- is what Phoenix should call
- opens keyed runs
- ingests webhook events through a sensor child
- orchestrates triage, research, review, and publish steps
- wraps lazy role activation, mutation, and status waiting

`IssueTriage.Pod`

- owns topology
- owns signal handling for the durable run record
- mounts plugin-backed sensor subscriptions
- stays focused on runtime definition and persistent run state

`IssueTriage.Plugins.IssueRunOpsPlugin`

- owns isolated runtime ops state
- subscribes the pod to a heartbeat sensor and a webhook sensor
- demonstrates plugin state plus sensor-driven signal flow

`IssueTriage.Artifacts`

- writes workflow artifacts into memory and thread state
- converts nested memory/thread changes into explicit `StateOp` updates
- exposes one of the missing ergonomic seams in the current end-to-end story

`IssueTriage.Policy`

- holds the example's classification and review heuristics
- separates app policy from runtime plumbing

## Controller / LiveView Usage

```elixir
alias Examples.PhoenixIssueTriage.IssueTriage

{:ok, run_pid} =
  IssueTriage.open_run("issue-123")

payload = %{
  issue_id: "issue-123",
  repo: "agentjido/jido",
  title: "Need runtime-defined pod topology",
  body: "We want to load pod definitions from the database and keep the workflow durable.",
  labels: ["bug", "needs-research", "customer-facing"]
}

{:ok, reviewed} =
  IssueTriage.process_issue(run_pid, payload)

{:ok, published} =
  IssueTriage.publish_run(run_pid)
```

## What This Example Uses

- `Jido.Pod` as the durable run root
- custom actions on the pod and roles
- custom sensor for webhook intake
- built-in `Jido.Sensors.Heartbeat`
- plugin subscriptions
- default memory and thread plugins through helper APIs
- lazy role activation
- live pod mutation to add a publisher role

## Why This Matters

This example is deliberately more opinionated:

- the domain module is the app boundary
- the pod is nested under the domain
- sensors stay attached to the pod runtime
- agent modules emit results upward
- Phoenix code talks to a clean API instead of directly to `Jido.Pod`

If this pattern holds up, Jido should document and eventually generate this
shape for multi-agent Phoenix apps.
