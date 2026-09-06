> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Flow factory results

The `06_04_flow_factory` example coordinates nine real worker Agents with a
Jido Flow. It adds 14 passing integration tests. The existing Factory tests
also pass: 43 tests. Together, the Factory group has four examples and 57 tests.

## Verified behavior

| Contract | Evidence |
| --- | --- |
| Parallel discovery | Both Research and Design enter before either is released. Component work waits for both. |
| Ordered component Map | API, UI, and Test enter concurrently. Integration receives their actual committed artifacts in declaration order. |
| Nested review and Choice | Quality and Security enter concurrently. Omitted security takes the fallback without calling that worker. |
| Bounded repair | Initial acceptance skips repair; one repair and the last allowed repair succeed; continued rejection stops after two repairs. |
| Review feedback | Revision 1 receives the original package and the actual revision 0 findings. |
| Accepted handoff | Delivery receives the accepted package revision and its reviews. |
| Failure boundaries | A failed implementation worker starts no integration or delivery. Prior worker commits remain visible. |
| Lifecycle | Cancel, a worker crash, and owner shutdown stop active worker calls. Owner shutdown is also tested during a nested repair Flow. |
| Deadline | The complete execution deadline fails the mission and releases its workers. |
| Correlation | Wrong-mission results and duplicate submissions do not replace active work. Worker retries return the same committed artifact; changed inputs are rejected. |
| Input validation | A blank goal starts no workers and leaves no mission Agent. |
| ReqLLM path | Real provider request encoding and response decoding, validated review JSON, invalid review rejection, and portable state without keys. |

## Commands and results

```sh
mix test --include example --include integration test/examples/06_factory/06_04_flow_factory --seed 0
```

Result: **14 passed**, no skips. Runtime: 93.4 seconds on the local Elixir
1.20.3 / OTP 29 environment. Tests use barriers and eventual assertions rather
than sleep calls. Each expected work wave has a separate barrier bound.

```sh
mix test --include example --include integration \
  test/examples/06_factory/06_01_live_conversation \
  test/examples/06_factory/06_02_three_agent_system \
  test/examples/06_factory/06_03_department_factory \
  test/examples/06_factory/streaming_test.exs --seed 0
```

Result: **43 passed**, no skips.

The default shell demo completed one repair with 15 artifacts. The shell demo
with `--no-security --accept-after 0` completed with eight artifacts. The
`--accept-after 3` demo recorded 20 artifacts, failed at the repair bound, ran no
handoff, and returned exit status 1. Live mode is implemented and tested through
the local ReqLLM HTTP boundary; a live provider run of this new example was not
performed.

`mix compile --warnings-as-errors` and formatting checks for the new source and
tests passed. The repository-wide quality run initially stopped on formatting
in concurrent `lib/jido/topology` work. A separate Dialyzer run reported two
opaque-type issues in `lib/jido/topology/controller/runtime.ex`, with no
reported Flow factory issues. These files are outside this example's changes.
The final `mix q` attempt still stopped on formatting in the separate Topology
source, examples, and tests. All 196 local links checked in the new and updated
Factory documentation resolve. The scoped whitespace check also passed.

## Runtime findings

The outer Mission Action commits work intent and returns Directives. The
Plugin owns the asynchronous Exec handle. It forwards progress and terminal
Signals from one sender, preserving their order without synchronous progress
calls into a busy Mission Agent.

Workers own their state commits. The Flow checks assignment identity and input
hash before it uses an artifact. The Mission Agent keeps an event history and
accepted artifact copies through separate turns. Flow failure cannot roll back
these worker commits.

Iterate returns a result envelope with local state and iteration count. The
pipeline selects that state before handoff. The repair Action runs another
Cycle Flow with the remaining mission deadline. Owner shutdown tests cover this
nested execution as well as the independently running worker Agents.

The example generates proposals. It provides no repository execution, durable
Flow checkpoint, result-delivery acknowledgement, or recovery after Plugin or
VM loss. Database adapters remain outside this example.

[Guide and graph](../../examples/06_factory/06_04_flow_factory/README.md)
· [Flow](../../examples/06_factory/06_04_flow_factory/pipeline.ex)
· [Tests](../../test/examples/06_factory/06_04_flow_factory/flow_factory_test.exs)
