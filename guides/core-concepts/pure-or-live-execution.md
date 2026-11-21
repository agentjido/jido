# Pure or Live Execution

The same Agent and Signal can run in two places: on a value with `Jido.Agent.cmd/3`, or in a process with `Jido.AgentServer.call/3`. This guide explains what the two paths share, where they differ, and how to choose.

## The same evaluation

Both paths select a route, run the handler, and build a candidate with the same code. For this Agent and Signal they produce equal state and an equal Directive batch.

```elixir
defmodule PureLiveGuide.AddLine do
  use Jido.Action,
    name: "pure_live_guide_add_line",
    schema: Jido.Joi.object(%{cents: Jido.Joi.integer() |> Jido.Joi.min(1)})

  @impl Jido.Action
  def run(%{cents: cents}, %{agent_state: state}) do
    {:ok, %{state | total_cents: state.total_cents + cents},
     [Jido.Agent.Directive.emit("invoice.line_added", %{cents: cents})]}
  end
end

defmodule PureLiveGuide.Invoice do
  use Jido.Agent, name: "invoice"

  state do
    schema Jido.Joi.object(%{total_cents: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/billing/invoice"

    route "invoice.add_line", PureLiveGuide.AddLine, as: :add_line

    route "invoice.line_added" do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, context.agent_state}
      end
    end

    route "invoice.report_up", as: :report_up do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        report = Jido.Signal.new!("invoice.reported", %{}, source: "/billing/invoice")
        {:ok, context.agent_state, [Jido.Agent.Directive.parent_send(report)]}
      end
    end
  end
end

signal = PureLiveGuide.Invoice.add_line_signal!(%{cents: 1200})

# Pure: a value goes in and a value comes out.
invoice = PureLiveGuide.Invoice.instantiate!(id: "inv-1")
{:ok, candidate, [%Jido.Agent.Directive.Emit{}]} = Jido.Agent.cmd(invoice, signal)

0 = invoice.state.total_cents
1200 = candidate.state.total_cents

# Live: the server keeps the result.
{:ok, _instance} = Jido.start(name: PureLiveGuide.Jido)
{:ok, server} = Jido.start_agent(PureLiveGuide.Jido, PureLiveGuide.Invoice, id: "inv-live")
:ok = Jido.AgentServer.await_ready(server)

{:ok, %Jido.AgentServer.TurnResult{status: :committed}} = Jido.AgentServer.call(server, signal)

true = Jido.AgentServer.snapshot(server).agent.state == candidate.state
```

On the pure path, `invoice` still holds the old state, and `candidate` is yours to keep or drop. The emitted Signal went nowhere. On the live path, the server committed the state and then delivered the Signal.

"Pure" describes the evaluation, and it does not extend to your handler. An Action can still call an API or write to a database on either path.

## What each path does

| Concern | `Jido.Agent.cmd/3` | `Jido.AgentServer.call/3` |
| --- | --- | --- |
| Needs | An Agent value | A running Jido instance and an AgentServer |
| Route selection, handler, and candidate | Yes | Yes |
| Plugin `prepare/2`, `select_route/2`, `reduce/2` | Yes | Yes |
| Plugin `admit/3`, `after_commit/3`, `dispatch/4`, `prepare_outbound/4` | No | Yes |
| Plugin runtime process | No. `plugin_inputs[plugin].runtime` is `nil` | Yes |
| Directives | Returned to you | Applied after commit |
| Keeps the result | No | Yes, with a new Agent revision |
| Saves to a store | No | With persistence |
| Serializes concurrent work | No | One Turn at a time, with a queue |
| Limit on total time | None | `:turn_timeout`, 60,000 ms by default |
| Reply Directive | Validated and returned | Reported in `TurnResult.reply` and delivered to the caller |
| Flow with a wait | Fails with `:unsupported_host` | Runs with persistence. Otherwise fails with `:unsupported_host` |
| Flow ending in a Handoff | Returns `{:handoff, candidate, instruction, directives}` | Commits and runs the successor as a new Turn |

## Where results can differ

The evaluation matches, but the live path applies more rules. A Signal that passes on the pure path can fail on the live path.

### The server checks the batch against its situation

The pure path checks that each Directive is well formed. The live path also asks whether this server can carry it out. A `ParentSend` needs a parent, a `Reply` needs a caller, and the batch must fit `:max_directives_per_turn`. A batch that fails here fails the Turn before commit.

```elixir
report_up = PureLiveGuide.Invoice.report_up_signal!(%{})

{:ok, _agent, [%Jido.Agent.Directive.ParentSend{}]} = Jido.Agent.cmd(invoice, report_up)
{:error, :parent_not_found} = Jido.AgentServer.call(server, report_up)
```

Test these cases against a live server.

### A Plugin can refuse on the live path

`admit/3` runs only in the server. A rule that lives there does not protect a `Jido.Agent.cmd/3` caller. Put a rule in `reduce/2` or in the Action when it must hold on both paths.

### Execution options differ

`Jido.Agent.cmd/3` passes its options to `Jido.Exec.run/4`, so they use that function's defaults. The server takes the same policy from `:exec_opts` with some different defaults:

| Option | `Jido.Agent.cmd/3` | AgentServer `:exec_opts` |
| --- | --- | --- |
| `:max_concurrency` | The smaller of `System.schedulers_online/0` and 10, or `config :jido, max_concurrency: n` | 1 |
| `:base_delay_ms` | 0 | 500 |
| `:max_delay_ms` | 0 | 30,000 |

A Flow whose steps have overlapping side effects can therefore behave differently on the pure path, because its ready steps run concurrently there. Set `:max_concurrency` on both paths when the order of side effects matters. See [Execution Policy](../actions/action-execution-policy.md).

### Each path handles failures in its own way

A failure on the pure path is a return value. Your code holds the old value and decides what to do. A failure on the live path also records a `last_outcome`, raises `error_count`, and runs `:error_policy`, which can stop the server.

## Where `Jido.Exec` fits

`Jido.Exec.run/4` sits below both paths. It runs an Action or Flow with no Agent at all: no state, no routes, no Directive rules. `Jido.Agent.cmd/3` adds the Agent evaluation around it. An AgentServer adds the process, the commit, and the effects.

The live path does not call `Jido.Exec.run/4`. It compiles the same Flow with `Jido.Exec.compile/2` and runs it under a Worker it can cancel, which is why a Turn can time out or be cancelled from outside. See [Execution](../flow-runtime/execution.md).

## Choose a path

| Use | When |
| --- | --- |
| `Jido.Exec.run/4` | The work has no Agent state. |
| `Jido.Agent.cmd/3` | You want the Agent's decision and own what happens next. Tests, previews, and scripts are typical. |
| `Jido.AgentServer.call/3` and the other live functions | State must persist between requests, requests must take turns, or Directives must run. |

You can test one Agent on both paths. Call `Jido.Agent.cmd/3` to match on the candidate and the batch. Start a server to cover Plugin runtime work and effects. See [Test Agent Definitions](../agents/testing-agent-definitions.livemd) and [Test Jido Systems](../operations/test-jido-systems.livemd).

To run the pure path as your own process, keep the returned candidate and pass it to the next `Jido.Agent.cmd/3` call. You then own ordering, Directive dispatch, and crash handling, which is what AgentServer provides.

## Related

- [Life of a Signal](signal-to-effects.md) follows the live path stage by stage.
- [Turns and Effects](turns-commits-and-effects.md) explains the commit boundary.
- [Agent Turns and Replies](../agents/turns-state-and-replies.md) covers the shared evaluation.
