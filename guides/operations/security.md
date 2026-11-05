# Security Model

This guide explains what Jido enforces and what your application must enforce. Read it before you accept outside input, store Agent state, or run more than one tenant.

Jido bounds and validates data. It has no concept of a user, a role, or a permission. Any code that can call an instance can act on any of its Agents, and an Action runs with the full rights of your application.

## Trust boundaries

Treat the BEAM node as one trust zone. Anything inside can reach anything else, and Jido adds no boundary within it.

| Item | Trusted? | Why |
| --- | --- | --- |
| Your compiled code, including Actions, Plugins, and inline Actions | Yes | It runs with full rights. |
| Other nodes connected through Erlang distribution | Yes | Distribution gives full access to a node. Protect it as you would a root shell. |
| Your persistence store | Yes | A writer can change Agent state. Flow execution records use unrestricted term decoding. |
| Signals from outside your system | No | Validate them. See below. |
| Flow definitions from outside your code | No | A stored Flow is a program. See [Flow Security](../flow-runtime/flow-security.md). |
| Model output and tool arguments in AI Agents | No | Treat them as untrusted input to your Actions. |

## Tenants

A partition, a namespace, and an instance organize Agents. None of them is an access control.

A `Jido.Agent.Ref` is an identifier and not a credential. Anyone holding one can address that Agent through the instance. Check authorization in your application before you build a Ref or look up an Agent, and take the tenant from your authenticated session rather than from the request's data. All tenants in one BEAM also share memory and schedulers, and a tenant that must not affect another needs a separate node. See [Instances and Tenants](configuration-and-tenant-isolation.md#what-a-partition-does-not-do).

## Inbound Signals

A Signal's `source`, `subject`, and `id` are claims made by the sender. Jido checks their form and nothing else. Authenticate the request first, then decode it with `Jido.Signal.Catalog.decode/3`, which checks size, envelope, and the `data` schema against an explicit list. See [Signal Boundaries](../signals/signal-boundaries.md).

Routing does not check `data`. A route's Action checks its own schema, so give each Action that takes outside input a strict schema. Do not put authorization data in Signal `data` or context unless your own code has set it.

These size limits apply. Set them in configuration, or per call for the Signal codec.

| Limit | Default | Applies to |
| --- | --- | --- |
| `config :jido, :max_payload_bytes` | 10,000,000 | `Jido.Signal.Codec` input. |
| `config :jido, Jido.Codec, maximum_json_bytes:` | 8,388,608 | `Jido.Codec` JSON input. |
| `:max_postponed_signals` | 1,000 | Requests queued per Agent. It does not bound the mailbox. |

Jido has no rate limit. Add one at your edge.

The next example shows a decoder refusing an unknown Signal type, then accepting a known one.

```elixir
defmodule SecurityGuide.TicketOpened do
  use Jido.Signal,
    type: "ticket.opened",
    default_source: "/support",
    schema: Jido.Joi.object(%{"subject" => Jido.Joi.string()}, unrecognized_keys: :error)
end

catalog = Jido.Signal.Catalog.new!([SecurityGuide.TicketOpened])

known = ~s({"specversion":"1.0","id":"evt-1","source":"/partner","type":"ticket.opened","data":{"subject":"Refund"}})
unknown = ~s({"specversion":"1.0","id":"evt-2","source":"/partner","type":"account.deleted","data":{}})

{:ok, %Jido.Signal{type: "ticket.opened"}} = Jido.Signal.Catalog.decode(catalog, known)
{:error, _reason} = Jido.Signal.Catalog.decode(catalog, unknown)
```

Choose from your own list in code. Do not turn a Signal's text into a module, an atom, or a target name, and do not let outside input pick an Action. A `Jido.Catalog` gives stored Flows the same protection. See [Flow Security](../flow-runtime/flow-security.md).

## Secrets

Keep secrets out of Agent state, Signal data, Turn context, and Flow input. These values reach places that you may not protect:

- **Agent state** is written to your store as it is, and Jido does not encrypt records. Encrypt in your store if you need that.
- **Crash reports.** `Jido.AgentServer` does not filter its data from OTP crash reports, so a process crash can log Agent state.
- **Action failures.** A failed step can log its node. A direct `Jido.Exec.run/4` call can include its params and context. See [Flow Security](../flow-runtime/flow-security.md).
- **Emitted Signals** go to wherever you dispatch them.

Use `Jido.Plugin.Config.env/1` for Plugin credentials. It stores a variable name, so the Agent definition, its JSON form, and its snapshots hold no secret. The Plugin reads the value when its runtime starts.

```elixir
{:env, "BILLING_API_KEY"} = Jido.Plugin.Config.env("BILLING_API_KEY")
```

Read other credentials from your application's configuration inside the Action, at the moment it needs them.

## What leaves through observation

Turn, effect, lifecycle, and persistence telemetry uses a fixed allowlist. It excludes Agent and Plugin state, Signal and Directive data, raw errors, process handles, and caller context. The semantic logger uses the same fields. It does include IDs and Signal types, so do not put personal data in an Agent ID or a Signal type.

Other events have looser rules. Review Action, Flow, Dispatch, and Bus metadata before you send it to an outside service. See [Telemetry and Tracing](telemetry-tracing-and-logs.md#what-events-contain).

`Jido.Error.to_map/1` builds a map for external use. It redacts values under known sensitive keys, bounds its size, and has no stacktrace.

```elixir
error =
  Jido.Error.execution_error("billing call failed", %{
    api_key: "sk-live-example",
    invoice: "inv-1"
  })

public = Jido.Error.to_map(error)
false = inspect(public) =~ "sk-live-example"
true = inspect(public) =~ "inv-1"
```

Redaction works by key name, so a secret under another key stays visible. Do not return raw errors to clients, and use `Jido.Error.to_map/1` at that boundary.

## Outbound dispatch

`Jido.Signal.Dispatch.Http` treats its URL as trusted configuration. It allows private network targets, has no DNS rebinding protection, and has no response size limit. Do not build a dispatch URL from outside input. Use a custom adapter for untrusted targets. See [Signal Dispatch Adapters](../signals/dispatch-adapters.md).

A dispatch target also reaches whatever it names. Any Directive your code builds from input can send data to that target, so choose targets in code.

## AI Agents

A `Jido.AI.Toolset` is the allowlist of tools for one Agent definition. A request can narrow it but cannot widen it. Model output decides which allowed tool runs, and with which arguments, so:

- Give an AI Agent only the tools that the least trusted person in its conversation may use.
- Validate each tool's input with a strict schema, and check authorization inside the Action from trusted context.
- Treat text from tool results and documents as untrusted, because it can steer the model.
- Set budgets, which `Jido.AI.Budget` checks before more work starts.

Jido's AI semantic logs omit prompts, model output, reasoning text, tool arguments, and tool results. Your own logging and your provider's retention are your responsibility.

## Production checklist

- Your application authenticates and authorizes each request before it reaches Jido.
- Outside Signals pass through `Jido.Signal.Catalog.decode/3`, and each Action has a strict schema.
- Outside Flow definitions, if any, resolve through a limited `Jido.Catalog`.
- Agent state holds no secrets, and your store is encrypted and access-controlled as your data requires.
- Erlang distribution is off or protected, and the cookie is secret.
- Dispatch URLs and targets come from your code or configuration.
- Crash reports and logs go to a place that may hold Agent state.
- Your edge applies rate limits.

## Next steps

- [Flow Security](../flow-runtime/flow-security.md)
- [Signal Boundaries](../signals/signal-boundaries.md)
- [Instances and Tenants](configuration-and-tenant-isolation.md)
