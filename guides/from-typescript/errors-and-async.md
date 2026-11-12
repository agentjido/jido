# Errors and Async

This guide shows how to move `try`/`catch` and `Promise` code to Elixir, and what Jido gives you in their place. It covers errors as values, crashes, concurrent tasks, timeouts, retries, and requests to live Agents.

## Return expected failures

TypeScript usually signals a failure with `throw`, and the type of a thrown value is not part of the signature. Some code returns a result union instead so that callers must handle it.

```typescript
type Result<T> = { ok: true; value: T } | { ok: false; reason: string };

function parseQuantity(raw: string): Result<number> {
  const quantity = Number(raw);
  return Number.isInteger(quantity)
    ? { ok: true, value: quantity }
    : { ok: false, reason: "not_a_number" };
}
```

The result union is the normal style in Elixir. A function returns `{:ok, value}` or `{:error, reason}`, and the caller matches on it. A name ending in `!` is the raising form of the same function, as with `File.read/1` and `File.read!/1`. Jido follows this: `instantiate/1` returns a tuple, and `instantiate!/1` raises.

```elixir
defmodule AsyncGuide.Quantity do
  def parse(raw) do
    case Integer.parse(raw) do
      {quantity, ""} -> {:ok, quantity}
      _other -> {:error, :not_a_number}
    end
  end
end

{:ok, 3} = AsyncGuide.Quantity.parse("3")
{:error, :not_a_number} = AsyncGuide.Quantity.parse("three")
```

## Chain fallible steps with `with`

`with` plays the part of a sequence of `await` calls inside one `try`. It runs each step while the pattern matches, and it returns the first value that does not match.

```typescript
async function pay(id: string, cents: number): Promise<Receipt> {
  try {
    const invoice = await loadInvoice(id);
    return await charge(invoice, cents);
  } catch (error) {
    if (error instanceof CardDeclinedError) return { status: "declined" };
    throw error;
  }
}
```

```elixir
defmodule AsyncGuide.Payments do
  def load_invoice("inv-1"), do: {:ok, %{id: "inv-1", balance_cents: 500}}
  def load_invoice(_id), do: {:error, :invoice_not_found}

  def charge(%{balance_cents: balance}, cents) when cents > balance, do: {:error, :over_balance}
  def charge(invoice, cents), do: {:ok, %{invoice_id: invoice.id, charged_cents: cents}}

  def pay(id, cents) do
    with {:ok, invoice} <- load_invoice(id),
         {:ok, receipt} <- charge(invoice, cents) do
      {:ok, receipt}
    end
  end
end

{:ok, %{charged_cents: 100}} = AsyncGuide.Payments.pay("inv-1", 100)
{:error, :over_balance} = AsyncGuide.Payments.pay("inv-1", 900)
{:error, :invoice_not_found} = AsyncGuide.Payments.pay("inv-404", 100)
```

## Let bugs crash

`raise` and `try`/`rescue` exist, and you use them less often than `throw` and `catch`. Elixir code returns a tuple for a failure the caller can act on, such as a declined card. It lets a bug or a lost dependency end the process, and a supervisor starts a clean one. This works because a crash ends one process. See [Node.js and the BEAM](nodejs-and-the-beam.md#crashes-stay-local).

So do not wrap each function in a defensive `try`. Write the case you handle, and let the rest fail with a stack trace.

## Action failures are values

`Jido.Exec.run/4` is a boundary that catches everything. Whether an Action returns an error, raises, or exits, the caller gets `{:error, exception}`. The result is always a struct, so a `struct` match plays the part of `instanceof`.

```typescript
try {
  await chargeCard(card);
} catch (error) {
  if (error instanceof ValidationError) return badRequest(error);
  if (error instanceof TimeoutError) return retryLater();
  throw error;
}
```

```elixir
defmodule AsyncGuide.ChargeCard do
  use Jido.Action,
    name: "async_guide_charge_card",
    schema: Jido.Joi.object(%{card: Jido.Joi.string()})

  @impl true
  def run(%{card: "expired"}, _context), do: {:error, :card_expired}
  def run(%{card: "buggy"}, _context), do: raise(ArgumentError, "gateway sent nonsense")
  def run(%{card: "hung"}, _context), do: Process.sleep(:infinity)
  def run(_params, _context), do: {:ok, %{charged: true}}
end

{:ok, %{charged: true}} = Jido.Exec.run(AsyncGuide.ChargeCard, %{card: "ok"})

{:error, %Jido.Error.ValidationError{}} = Jido.Exec.run(AsyncGuide.ChargeCard, %{card: 42})

{:error, %Jido.Error.ExecutionError{details: %{reason: :card_expired}}} =
  Jido.Exec.run(AsyncGuide.ChargeCard, %{card: "expired"})

{:error, %Jido.Error.ExecutionError{details: %{exception: ArgumentError}}} =
  Jido.Exec.run(AsyncGuide.ChargeCard, %{card: "buggy"})

{:error, %Jido.Error.TimeoutError{timeout: 20}} =
  Jido.Exec.run(AsyncGuide.ChargeCard, %{card: "hung"}, %{}, timeout: 20)
```

`Jido.Error.to_map/1` turns an error into a plain map for a JSON response or a log.

```elixir
{:error, error} = Jido.Exec.run(AsyncGuide.ChargeCard, %{card: "expired"})

%{type: :execution_error, retryable?: true} = Jido.Error.to_map(error)
true = is_binary(JSON.encode!(Jido.Error.to_map(error)))
```

[Actions](../actions/actions.md#handle-failures) has the full failure table, and [Jido Error Contracts](../data/error-contracts.md) covers each error type.

## From Promises to Tasks

An async function in TypeScript returns a `Promise` at once. In Elixir, `Task.async/1` starts a process and returns a handle.

| TypeScript | Elixir | What to watch |
| --- | --- | --- |
| `const p = work()` | `task = Task.async(&work/0)` | The task is linked to the caller |
| `await p` | `Task.await(task, ms)` | Exits the caller on timeout. The default is 5,000 ms |
| `await Promise.all(ps)` | `Task.await_many(tasks, ms)` | Same timeout behavior |
| `await Promise.allSettled(ps)` | `Task.yield_many(tasks, ms)` | Use tasks that are not linked |
| `await Promise.race(ps)` | No single function | Use `receive` for the first `{ref, result}` reply, then shut down the rest |

The link in the first row is the main difference. When a `Task.async/1` task crashes, the link ends the caller too, and a `try` around `Task.await/2` does not stop that. To keep failures apart, start tasks that are not linked. This is the shape of `Promise.allSettled`.

```typescript
const results = await Promise.allSettled(ids.map((id) => loadInvoice(id)));
// [{ status: "fulfilled", value }, { status: "rejected", reason }]
```

```elixir
{:ok, loaders} = Task.Supervisor.start_link()

load = fn
  "inv-404" -> raise "invoice not found"
  id -> %{id: id}
end

results =
  ["inv-1", "inv-404"]
  |> Enum.map(fn id -> Task.Supervisor.async_nolink(loaders, fn -> load.(id) end) end)
  |> Task.yield_many(1_000)
  |> Enum.map(fn {_task, result} -> result end)

[{:ok, %{id: "inv-1"}}, {:exit, {%RuntimeError{message: "invoice not found"}, _stacktrace}}] = results
```

This cell logs the crash. A `nil` result from `Task.yield_many/2` means that the task did not finish in time.

For Actions, the boundary is already there. `Jido.Exec.run/4` blocks its caller like a plain function, and a crash in the Action comes back as an error. A `Task.async/1` around it is not at risk from that crash.

## Run many items with a limit

A package such as `p-limit` bounds how many promises run together. `Task.async_stream/3` does this for plain functions, and a Flow `map` does it for Actions. `:max_concurrency` sets the limit, and `on_error: :collect_errors` gives the `allSettled` shape.

```typescript
const limit = pLimit(2);
const prices = await Promise.all(skus.map((sku) => limit(() => priceSku(sku))));
```

```elixir
[20, 40, 60] =
  [1, 2, 3]
  |> Task.async_stream(fn quantity -> quantity * 20 end, max_concurrency: 2)
  |> Enum.map(fn {:ok, cents} -> cents end)

defmodule AsyncGuide.PriceSku do
  use Jido.Action, name: "async_guide_price_sku"

  @impl true
  def run(%{sku: "gone"}, _context), do: {:error, Jido.Error.execution_error("sku withdrawn")}
  def run(%{sku: sku}, _context), do: {:ok, %{sku: sku, cents: 500}}
end

defmodule AsyncGuide.PriceAll do
  use Jido.Flow, name: "async_guide_price_all"

  flow do
    map "prices",
      collection: input(:skus),
      action: AsyncGuide.PriceSku,
      params: %{sku: item()},
      on_error: :collect_errors

    output %{prices: result("prices")}
  end
end

{:ok, %{prices: [%{status: :ok, value: %{sku: "A-1"}}, %{status: :error, error: %{message: "sku withdrawn"}}]}} =
  Jido.Exec.run(AsyncGuide.PriceAll, %{skus: ["A-1", "gone"]}, %{}, max_concurrency: 2)
```

Results keep input order. Without the option, a Flow uses the `:jido` application setting, or else the smaller of the online scheduler count and 10. See [Map and Reduce](../flows/flow-collections.md).

## Time out and retry

In TypeScript, a timeout is usually an `AbortSignal` that the callee must observe. If a function ignores the signal, it keeps running.

```typescript
const response = await fetch(url, { signal: AbortSignal.timeout(2000) });
```

A BEAM process can be killed from outside, wherever it is in its code. `Task.shutdown/2` does this for a task, and the `:timeout` option does it for an Action. Killing the process does not undo work that already left it, so a request sent to another system can still complete.

```elixir
slow = Task.async(fn -> Process.sleep(:infinity) end)

nil = Task.yield(slow, 20) || Task.shutdown(slow, :brutal_kill)
```

A retry loop in TypeScript is yours to write, or comes from a package. `Jido.Exec.run/4` takes the policy as options at the call site.

```typescript
for (let attempt = 1; ; attempt++) {
  try {
    return await chargeCard(card);
  } catch (error) {
    if (attempt === 3 || !isRetryable(error)) throw error;
    await sleep(100 * 2 ** (attempt - 1));
  }
}
```

```elixir
defmodule AsyncGuide.FlakyCharge do
  use Jido.Action, name: "async_guide_flaky_charge"

  @impl true
  def run(_params, %{attempts: attempts}) do
    :counters.add(attempts, 1, 1)

    case :counters.get(attempts, 1) do
      attempt when attempt < 3 -> {:error, Jido.Error.execution_error("gateway unavailable")}
      attempt -> {:ok, %{attempt: attempt}}
    end
  end
end

attempts = :counters.new(1, [])

{:ok, %{attempt: 3}} =
  Jido.Exec.run(AsyncGuide.FlakyCharge, %{}, %{attempts: attempts},
    timeout: 1_000,
    max_attempts: 3,
    backoff: :exponential,
    base_delay_ms: 1,
    max_delay_ms: 10
  )
```

Any retry can repeat side effects in `run/2`. Most failures retry when you set `:max_attempts`, and validation errors do not. To mark a permanent failure, set `retry: false` in its details. See [Execution Policy](../actions/action-execution-policy.md).

## Send requests to a live Agent

Each request mode of `Jido.AgentServer` has a familiar shape:

| You want | TypeScript | `Jido.AgentServer` | What the caller sees |
| --- | --- | --- | --- |
| Wait for the result | `await agent.send(signal)` | `call/3` | The result. On timeout it exits the caller, so catch `:exit` if you need to continue |
| Start now, wait later | `const p = agent.send(signal)`, later `await p` | `submit/3`, then `await/2` | The result. On timeout it returns `{:error, :timeout}`, and you can wait again |
| Send with no reply | `void agent.send(signal)` | `cast/3` | `:ok` at once. A failure only logs |
| Stop the work | `controller.abort()` | `cancel/2`, `cancel_turn/3` | `:ok` after the work has stopped |

A caller timeout is like `Promise.race` against a timer: the caller stops waiting, and the Turn keeps running. To stop a Turn, cancel it. An abort in TypeScript needs the callee's cooperation. `Jido.AgentServer.cancel/2` stops the Action's process, and no state is committed.

```elixir
defmodule AsyncGuide.BuildReport do
  use Jido.Action,
    name: "async_guide_build_report",
    schema: Jido.Joi.object(%{name: Jido.Joi.string()})

  @impl true
  def run(%{name: name}, %{agent_state: state, notify: notify}) do
    send(notify, {:building, self()})

    receive do
      :finish -> {:ok, %{state | reports: state.reports ++ [name]}}
    end
  end
end

defmodule AsyncGuide.Reports do
  use Jido.Agent, name: "async_guide_reports"

  state do
    schema Jido.Joi.object(%{reports: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/reports"
    route "report.build", AsyncGuide.BuildReport, as: :build
  end
end

{:ok, _instance} = Jido.start(name: AsyncGuide.Jido)
{:ok, reports} = Jido.start_agent(AsyncGuide.Jido, AsyncGuide.Reports, id: "reports-1")
:ok = Jido.AgentServer.await_ready(reports)

await_action = fn ->
  receive do
    {:building, pid} -> pid
  after
    1_000 -> raise "the Turn did not start"
  end
end

# Hold a handle, as with a Promise. A timed-out await can wait again.
q1 =
  Jido.AgentServer.submit(reports, AsyncGuide.Reports.build_signal!(%{name: "q1"}),
    context: %{notify: self()}
  )

action = await_action.()
{:error, :timeout} = Jido.AgentServer.await(q1, 0)
send(action, :finish)
{:ok, %{state: %{reports: ["q1"]}}, []} = Jido.AgentServer.await(q1)

# Cancel a Turn. The Action does not have to cooperate.
q2 =
  Jido.AgentServer.submit(reports, AsyncGuide.Reports.build_signal!(%{name: "q2"}),
    context: %{notify: self()}
  )

_action = await_action.()
:ok = Jido.AgentServer.cancel(reports)
{:error, :cancelled} = Jido.AgentServer.await(q2)

%{reports: ["q1"]} = Jido.AgentServer.snapshot(reports).agent.state

:ok = Jido.stop(AsyncGuide.Jido)
```

A handle belongs to the process that made it, so it cannot be passed around in the way a `Promise` can. Cancellation undoes nothing outside the Agent. See [Call, Cast, and Await](../agent-servers/send-signals-to-live-agents.livemd) and [Cancel Turns](../agent-servers/cancel-turns.livemd).

## Next steps

- [Effects as Data](effects-as-data.md) moves side effects out of handlers.
- [Execution Policy](../actions/action-execution-policy.md) lists each timeout and retry option.
- [Agent Lifecycle](../agent-servers/agent-activation-control.md) covers what the server does after a failed Turn.
