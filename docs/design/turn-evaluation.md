> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the current core scope](../../guides/core-scope.md).

# Turn evaluation

[Design overview](README.md) | Previous: [Agent](agent.md) | Next: [Plugins](plugins.md)

- Depends on: Agent, Signal, Action, Flow, Plugin, and `Jido.Exec`.
- Defines: the deterministic command sequence and the private evaluator shared
  by direct and live execution.

The Turn Evaluator is a fixed compiled-Elixir pipeline. It uses normal function
calls, `with`, and `Enum.reduce_while/3`. It does not build or execute a Runic
graph around an Agent Turn.

`Jido.Exec` remains the execution boundary for the selected Action or Flow. A
selected `Jido.Flow` can use Runic inside `Jido.Exec`. That Flow execution does
not change the fixed outer Agent pipeline.

## Command evaluation boundary

`Agent.cmd/3` is the shared command evaluation boundary:

```text
Agent A0 + Signal S0
  -> run the Turn Evaluator to completion
  -> execute one protected Action or Flow Turn
  -> apply serial Plugin contributions
  -> validate the candidate Agent and Directives
  -> return Agent A1 and Directives D
```

During a command, the Action or Flow is the only writer of `Agent.state`. It
returns one complete domain state map. Each Plugin contribution can replace
only its complete entry in `Agent.plugin_state`. Jido assembles and validates
both state classes in one candidate Agent value.

The Turn Evaluator has fixed ordering. Command preparation and state assembly
are deterministic for fixed inputs and executable results. Plugin preparation
and contribution callbacks remain pure. The selected Action or Flow can
perform synchronous external work. A changing external response can change
the candidate even when the Agent, Signal, and options are unchanged.

Direct evaluation does not save or commit live Agent state, or dispatch returned
Directives. It can still perform I/O through its executable. An error does not
undo completed external work. Applications own idempotency and recovery; fixed
or recorded dependency responses are required for reproducible evaluation.
See the [state and effect contract](commit-and-effects.md#state-and-effect-contract).

`Jido.Agent.cmd/3` and `Jido.AgentServer` use the same Turn Evaluator. A
direct call runs it in the caller. A live Server runs the complete pre-commit
evaluation in one owner-bound task under the Jido Task Supervisor.

The direct `cmd/3` success is an evaluation return. It proves only that Jido
built and validated a candidate Agent and Directive list. The capitalized
`Result` term is reserved for the live instance reply at the commit boundary.

## Protected executable output

The selected Action or Flow returns complete domain state and Directives. Jido
validates this output and keeps it in the private evaluator accumulator. No
Plugin receives the complete output value.

For each Plugin, Jido builds one `%Jido.Plugin.Transition{}`. It contains only
the Plugin's declared top-level state projection, Signal identities and type,
and Turn Directives owned by that Plugin. The Plugin Context also contains only
that Plugin's configuration, state, and prepared input.

This keeps executable output protected without a public
`Jido.Agent.Turn.Result` type. A Plugin cannot replace the output, change its
domain state, inspect undeclared state fields, or inspect another owner's
Directive.

## Fixed command pipeline

The Agent command pipeline is:

```text
Command input
  -> Resolve Route            original source Signal
  -> Prepare Plugins          effective Signal plus isolated owned inputs
  -> Build Executable Input   effective Signal plus fixed route parameters
  -> Execute Turn             one Jido.Exec call
  -> Compose Plugins          ordered serial reduce
  -> Validate Candidate       one final validation
```

Route resolution uses the original source Signal. It selects one executable and
its route parameters before Plugin preparation. These values stay in the
private evaluator accumulator and cannot change during the Turn. Jido does not
run route resolution again for a prepared effective Signal.

Preparation uses `Enum.reduce_while/3` because each Plugin receives the
command returned by the previous Plugin. The first error stops the reduce.

Plugin composition uses one `Enum.reduce_while/3`. Every Plugin receives its
own bounded Transition and Context from `A0`. It does not receive the private
executable output or candidate accumulator. After each callback, Jido validates
and applies that contribution to the accumulator. The first error stops the
reduce and discards the candidate. A Plugin cannot supply or replace the
reducer.

This fused contribution and assembly step avoids an intermediate contribution
list. It keeps the same isolation rule because no Plugin can read the result of
an earlier Plugin.

The first v3 implementation does not run Agent-level Plugin callbacks
concurrently. Agent Plugin lists are small, and serial execution gives simple
ordering, failure, timeout, and test behavior. A selected Flow remains free to
use the execution rules that `Jido.Exec` defines for that Flow.

## Compiled Elixir implementation

The evaluator follows this direct shape:

```elixir
def run(agent, signal, opts) do
  with {:ok, executable, route_params} <-
         resolve_executable(agent, signal),
       {:ok, command, plugin_inputs} <-
         prepare_plugins(agent, signal, opts),
       {:ok, input} <- build_input(command.signal, route_params),
       {:ok, exec_result} <-
         execute_turn(
           agent,
           command,
           executable,
           input,
           plugin_inputs,
           opts
       ),
       {:ok, candidate, directives} <-
         compose_plugins(agent, exec_result, plugin_inputs),
       {:ok, candidate, directives} <-
         validate_candidate(candidate, directives) do
    {:ok, candidate, directives, exec_result, command.signal}
  end
end
```

This code is illustrative. The implementation can use private values to keep
validated inputs and error context. It must keep the stage order and ownership
rules in this document.

Jido invokes application callbacks through narrow wrappers. The wrappers
convert callback exceptions, throws, exits, invalid returns, and schema errors
to defined Splode errors. An unexpected evaluator invariant failure exits
the live evaluation task. The Agent Server then crashes and restores through
OTP instead of continuing with uncertain state.

## Live execution

The core live path is:

```text
receive Signal S0 while Agent A0 is at version V
  -> assign a stable Turn ID
  -> start one owner-bound Turn evaluation task
  -> run the fixed compiled-Elixir pipeline
  -> receive one terminal candidate or error
  -> verify the active Turn ID and task reference
  -> save one commit record at version V + 1
  -> replace A0 with A1 and set version V + 1
  -> reply {:ok, A1}
  -> dispatch the current Directive batch in list order
  -> record the terminal Turn Outcome
  -> admit the next Signal when the Turn settles
```

The Agent Server stores the active Turn and task identity before it accepts a
task result. A late or duplicate task result cannot advance another Turn.

Rules:

- Only one state-changing Turn runs at a time.
- The Server processes admitted Signals one at a time.
- Signal order follows OTP mailbox delivery order.
- Route selection uses the original source Signal and completes before Plugin
  preparation.
- The selected executable and route parameters cannot change during the Turn.
- Plugin callbacks cannot change the pipeline shape.
- Plugin preparation and composition run serially in declaration order.
- Plugin callbacks cannot read or replace the complete executable output.
- Each Plugin receives only its declared Transition projection and owned
  preparation data.
- A pre-commit error keeps `A0` and runs no Directive.
- Persistence succeeds before live state changes.
- The state version increases once per commit.
- Directives run only after commit.
- The Agent Server validates Directive ownership before commit. Ordinary
  Directives are not automatically persisted for replay.
- Explicit durable work belongs to Agent or Plugin state in the checkpoint.
- A Directive error does not roll back `A1`.
- A later state change requires another Signal.
- The next Signal starts after the live Turn settles. A Plugin can dispatch
  a wake-up and complete its background business work in a later Turn.

## `Jido.Agent.Turn.Evaluator`

`Jido.Agent.Turn.Evaluator` is a private module with `@moduledoc false`. It
owns Jido's Turn evaluation rules. It is not a public API or a semantic-version
contract.

Its internal API has one main operation:

```elixir
Turn.Evaluator.run(agent, signal, opts)
# => {:ok, candidate_agent, directives, private_exec_result, effective_signal}
#  | {:error, stage, Jido.Error.t()}
```

`Jido.Agent.cmd/3` removes private terminal details and returns
`{:ok, agent, directives}` or `{:error, Jido.Error.t()}`. The Agent Server
uses the private executable result, effective Signal, and failure stage to
build runtime observation.

The evaluator module owns no process, task, timer, supervisor, or runtime
handle. The Agent Server owns the live evaluation task. The evaluator and its
private accumulators never enter an Agent, checkpoint, or public result.

The evaluator has no cancellation API and owns no timer. In live execution,
the Agent Server can terminate the one evaluation task only while its control
stage is `:evaluate`. It waits for the task `:DOWN`, discards a late result,
and keeps the committed Agent unchanged. Commit and Directive dispatch are not
cancellable. Direct `Jido.Agent.cmd/3` runs the evaluator in the caller and has
no Server cancellation or `:turn_timeout`. The v3 design does not persist or
recover a partly completed evaluation.

## Start-small limits

The first implementation has these limits:

- One local Turn evaluation for one admitted Signal.
- One active Turn evaluation task per Agent Server.
- One fixed compiled-Elixir pipeline owned by Jido.
- Serial Plugin preparation and composition.
- No mid-command persistence, restore, retry, or distribution.
- No Plugin-defined stages or pipeline changes.
- No Agent-level Plugin contribution concurrency.

These limits keep the first implementation small and testable. Runic remains
an internal implementation detail of a selected `Jido.Flow`; it is not the
Agent Turn coordinator.
