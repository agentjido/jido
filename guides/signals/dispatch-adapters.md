# Signal Dispatch Adapters

Send a Signal to a process, a Bus, Phoenix PubSub, Logger, or an HTTP endpoint, and write your own adapter. `Jido.Signal.Dispatch` validates a target and delivers to it in the calling process.

Dispatch is synchronous. The caller owns asynchronous work, retries, concurrency limits, and circuit breaking.

## Send a Signal

A target is an `{adapter, options}` tuple. `Jido.Signal.Dispatch.dispatch/2` returns `:ok` or `{:error, reason}`.

```elixir
alias Jido.Signal
alias Jido.Signal.Dispatch

signal = Signal.new!("order.placed", %{"order_id" => "ord-100"}, source: "/shop")

:ok = Dispatch.dispatch(signal, {:pid, target: self()})

received =
  receive do
    {:signal, message} -> message
  after
    1_000 -> :timeout
  end

^signal = received
```

Pass a list to deliver to several targets in order. A failure does not stop the remaining targets. The result is `:ok`, or `{:error, reasons}` with one reason per failed target.

```elixir
alias Jido.Signal
alias Jido.Signal.Dispatch

signal = Signal.new!("order.placed", %{"order_id" => "ord-100"}, source: "/shop")

{:error, [:process_not_found]} =
  Dispatch.dispatch(signal, [
    {:named, target: {:name, :missing_order_worker}},
    {:noop, []},
    {:pid, target: self()}
  ])

:delivered_after_failure =
  receive do
    {:signal, _signal} -> :delivered_after_failure
  after
    1_000 -> :timeout
  end
```

## Validate a target early

`Jido.Signal.Dispatch.validate_opts/1` checks a target without sending anything, and returns the options with defaults applied. Run it at startup or when you read a target from configuration.

```elixir
alias Jido.Signal.Dispatch

{:ok, {:http, [url: "https://example.com/events", headers: [], timeout: 5_000]}} =
  Dispatch.validate_opts({:http, url: "https://example.com/events"})

{:error, "must be an HTTP or HTTPS URL with a host, at url"} =
  Dispatch.validate_opts({:http, url: "ftp://example.com/events"})

{:error, "unrecognized key: retry"} =
  Dispatch.validate_opts({:logger, retry: 3})

{:error, ":ftp is not a valid adapter" <> _rest} = Dispatch.validate_opts({:ftp, []})
{:error, :invalid_dispatch_config} = Dispatch.validate_opts(:order_worker)
```

Each adapter rejects unknown options.

## Built-in adapters

| Input | Module | Delivers to |
| --- | --- | --- |
| `:pid` | `Jido.Signal.Dispatch.PidAdapter` | A local PID or registered name. |
| `:named` | `Jido.Signal.Dispatch.PidAdapter` | The same adapter under another name. |
| `:bus` | `Jido.Signal.Dispatch.Bus` | A named `Jido.Signal.Bus`. |
| `:pubsub` | `Jido.Signal.Dispatch.PubSub` | A Phoenix PubSub topic. |
| `:logger` | `Jido.Signal.Dispatch.LoggerAdapter` | Elixir Logger. |
| `:http` | `Jido.Signal.Dispatch.Http` | An HTTP `POST` endpoint. |
| `:noop` | None | Nothing. Emits dispatch telemetry and returns `:ok`. |
| `nil` | None | Nothing. Accepts any keyword list, emits no telemetry, and returns `:ok`. |

### Process

| Option | Default | Value |
| --- | --- | --- |
| `:target` | Required | A local PID or `{:name, atom}`. |
| `:delivery_mode` | `:async` | `:async` sends a message. `:sync` uses `GenServer.call/3`. |
| `:timeout` | `5_000` | Milliseconds for `:sync`. |
| `:message_format` | `{:signal, signal}` | A one-argument function that builds the message. |

Sync mode returns `:ok` for any reply except `{:error, reason}`, which it returns as the failure. A sync call can return `{:error, :timeout}` or `{:error, :process_not_alive}`, and a process cannot call itself.

```elixir
defmodule GuideDispatch.OrderWorker do
  use GenServer

  def init(state), do: {:ok, state}

  def handle_call({:signal, %{data: %{"order_id" => "bad"}}}, _from, state),
    do: {:reply, {:error, :rejected}, state}

  def handle_call({:signal, _signal}, _from, state), do: {:reply, :accepted, state}
end

alias Jido.Signal
alias Jido.Signal.Dispatch

{:ok, _worker} = GenServer.start_link(GuideDispatch.OrderWorker, [], name: :order_worker)
target = {:named, target: {:name, :order_worker}, delivery_mode: :sync, timeout: 1_000}

good = Signal.new!("order.placed", %{"order_id" => "ord-100"}, source: "/shop")
bad = Signal.new!("order.placed", %{"order_id" => "bad"}, source: "/shop")

:ok = Dispatch.dispatch(good, target)
{:error, :rejected} = Dispatch.dispatch(bad, target)

{:error, :process_not_found} = Dispatch.dispatch(good, {:named, target: {:name, :missing_worker}})

:ok =
  Dispatch.dispatch(good,
    {:pid, target: self(), message_format: fn signal -> {:order_event, signal.data["order_id"]} end}
  )

"ord-100" =
  receive do
    {:order_event, order_id} -> order_id
  after
    1_000 -> :timeout
  end
```

A remote PID fails validation. Use `:pubsub` or `:http` to reach another node.

### Bus

The `:bus` adapter finds a Bus by name and publishes the Signal. `:target` is the Bus name as an atom. `:jido` selects a scoped Bus.

```elixir
alias Jido.Signal
alias Jido.Signal.{Bus, Dispatch}

{:ok, _bus} = Bus.start_link(name: :order_events)
{:ok, _subscription} = Bus.subscribe(:order_events, "order.*")

signal = Signal.new!("order.placed", %{"order_id" => "ord-100"}, source: "/shop")
:ok = Dispatch.dispatch(signal, {:bus, target: :order_events})

^signal =
  receive do
    {:signal, message} -> message
  after
    1_000 -> :timeout
  end

{:error, :bus_not_found} = Dispatch.dispatch(signal, {:bus, target: :missing_events})
```

When an AgentServer dispatches to a `:bus` target with no `:jido`, it adds its own Instance as the scope.

### Phoenix PubSub

This adapter needs the optional `phoenix_pubsub` dependency. Without it, delivery returns `{:error, {:missing_dependency, :phoenix_pubsub}}`.

<!-- partial -->
```elixir
{:phoenix_pubsub, "~> 2.1"}
```

`:target` is the PubSub server name and `:topic` is the topic. Subscribers receive the bare Signal, with no `{:signal, signal}` wrapper.

```elixir
alias Jido.Signal
alias Jido.Signal.Dispatch

{:ok, _supervisor} =
  Supervisor.start_link([{Phoenix.PubSub, name: GuideDispatch.PubSub}], strategy: :one_for_one)

:ok = Phoenix.PubSub.subscribe(GuideDispatch.PubSub, "orders")

signal = Signal.new!("order.placed", %{"order_id" => "ord-100"}, source: "/shop")
:ok = Dispatch.dispatch(signal, {:pubsub, target: GuideDispatch.PubSub, topic: "orders"})

^signal =
  receive do
    %Signal{} = message -> message
  after
    1_000 -> :timeout
  end

{:error, :pubsub_not_found} =
  Dispatch.dispatch(signal, {:pubsub, target: GuideDispatch.MissingPubSub, topic: "orders"})
```

### Logger

| Option | Default | Value |
| --- | --- | --- |
| `:level`, `:log_level` | `config :jido, default_log_level`, or `:info` | `:debug`, `:info`, `:warning`, or `:error`. `:log_level` wins when both are set. |
| `:structured` | `false` | `true` logs a map instead of text. |
| `:include_data` | `true` | `false` leaves `data` out of the message. |

The adapter sanitizes `data` before it logs it. See [Signal Boundaries](signal-boundaries.md).

```elixir
alias Jido.Signal
alias Jido.Signal.Dispatch

signal = Signal.new!("order.placed", %{"order_id" => "ord-100"}, source: "/shop")

:ok = Dispatch.dispatch(signal, {:logger, level: :info, include_data: false})
# Logs: SIGNAL: order.placed from /shop

:ok = Dispatch.dispatch(signal, {:logger, level: :info})
# Logs: SIGNAL: order.placed from /shop with data=%{"order_id" => "ord-100"}
```

### HTTP

The `:http` adapter sends one synchronous `POST` through OTP `:httpc`. The body is the structured CloudEvents JSON from `Jido.Signal.Codec`, with the content type `application/cloudevents+json`.

<!-- partial -->
```elixir
Jido.Signal.Dispatch.dispatch(signal,
  {:http,
   url: "https://api.example.com/events",
   headers: [{"authorization", "Bearer " <> api_token}],
   timeout: 5_000}
)
```

| Option | Default | Limits |
| --- | --- | --- |
| `:url` | Required | `http` or `https` with a host. ASCII only, at most 8,192 bytes. No user information or fragment. |
| `:headers` | `[]` | `{name, value}` strings. At most 32 headers and 64,000 bytes in total. Names are at most 128 bytes and values at most 8,192 bytes. |
| `:timeout` | `5_000` | 1 to 60,000 milliseconds. Applies to the connection and to the request. |

Headers cannot repeat a name, use a `ce-` prefix, or be one of `connection`, `content-encoding`, `content-length`, `content-type`, `expect`, `host`, `proxy-connection`, `te`, `trailer`, `transfer-encoding`, or `upgrade`.

Any 2xx response is `:ok`. Redirects are not followed. HTTPS requests verify the host. Failures return:

| Reason | Cause |
| --- | --- |
| `{:http_status, status}` | The response was not 2xx. This includes a 3xx response. |
| `:timeout` | The request timed out. |
| `{:transport, reason}` | The connection or request failed. |
| `{:serialization, reason}` | `data` cannot encode as JSON, such as a map with atom keys. |

```elixir
alias Jido.Signal
alias Jido.Signal.Dispatch

signal = Signal.new!("order.placed", %{order_id: "ord-100"}, source: "/shop")

{:error, {:serialization, {:json_encode_failed, _message}}} =
  Dispatch.dispatch(signal, {:http, url: "http://127.0.0.1:1/events"})
```

Dispatch adds no retry loop. OTP `:httpc` can honor `Retry-After` on a 503 response, and OTP 27 has no option to turn this off.

Treat the URL as trusted application configuration. The adapter allows private network targets and does not protect against DNS rebinding. OTP 27 `:httpc` has no response size limit for this request type. Write a custom adapter for untrusted URLs, a strict response limit, request signing, custom TLS, or another HTTP method.

## Write a custom adapter

Implement `Jido.Signal.Dispatch.Adapter` and pass the module as the adapter. Dispatch parses the options with `options_schema/0` before each `deliver/2` call. The module must declare the behaviour, or Dispatch rejects it.

```elixir
defmodule GuideDispatch.OutboxAdapter do
  @behaviour Jido.Signal.Dispatch.Adapter

  alias Jido.Joi

  @impl true
  def options_schema do
    Joi.keyword(
      [table: Joi.atom() |> Joi.required(), tag: Joi.string() |> Joi.default("default")],
      unrecognized_keys: :error
    )
  end

  @impl true
  def deliver(signal, opts) do
    table = Keyword.fetch!(opts, :table)

    if :ets.whereis(table) == :undefined do
      {:error, :outbox_not_found}
    else
      true = :ets.insert(table, {signal.id, Keyword.fetch!(opts, :tag), signal.type})
      :ok
    end
  end
end

alias Jido.Signal
alias Jido.Signal.Dispatch

:order_outbox = :ets.new(:order_outbox, [:named_table, :public])
signal = Signal.new!("order.placed", %{"order_id" => "ord-100"}, id: "evt-1", source: "/shop")

:ok = Dispatch.dispatch(signal, {GuideDispatch.OutboxAdapter, table: :order_outbox})
[{"evt-1", "default", "order.placed"}] = :ets.lookup(:order_outbox, "evt-1")

{:error, :outbox_not_found} =
  Dispatch.dispatch(signal, {GuideDispatch.OutboxAdapter, table: :missing_outbox})

{:error, _missing_table} = Dispatch.validate_opts({GuideDispatch.OutboxAdapter, []})
{:error, "GenServer is not a valid adapter" <> _rest} = Dispatch.validate_opts({GenServer, []})
```

Return `{:error, reason}` for a delivery failure. An exception or exit from `deliver/2` emits a dispatch exception event and then reaches the caller.

## Structured errors

By default, reasons reach the caller unchanged. Set this option to wrap them in `Jido.Error` values:

<!-- partial -->
```elixir
config :jido, normalize_dispatch_errors: true
```

With it on, a delivery failure returns a `Jido.Error.RoutingError` with the original reason in `details.reason`. An invalid target returns a `Jido.Error.ValidationError`.

## Telemetry

Each delivery through an adapter or `:noop` emits `[:jido, :dispatch, :start]`, then `[:jido, :dispatch, :stop]` or `[:jido, :dispatch, :exception]`. The stop and exception events measure `latency_ms`. See [Telemetry Events](../reference/telemetry-event-reference.md).

## Related

- State and Directives to dispatch from an Agent with `Jido.Agent.Directive.Emit`.
- [Signal Bus](signal-bus-and-subscriptions.md) for the Bus that the `:bus` adapter publishes to.
