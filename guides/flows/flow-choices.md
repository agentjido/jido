# Choices and Conditions

Use a `choice` to route one Flow component on data. It tests its options in order, runs the Action of the first option whose condition is true, and otherwise runs a required fallback. Its result is the result of the Action that ran.

## Route on a value

```elixir
defmodule FlowChoices.Route do
  use Jido.Action, name: "flow_choices_route"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule FlowChoices.TicketQueue do
  use Jido.Flow, name: "flow_choices_ticket_queue"

  flow do
    choice "route" do
      option "urgent",
        condition: input(:priority) >= 90,
        action: FlowChoices.Route,
        params: %{queue: :urgent, ticket_id: input(:ticket_id)}

      option "priority",
        condition: input(:priority) >= 50,
        action: FlowChoices.Route,
        params: %{queue: :priority, ticket_id: input(:ticket_id)}

      otherwise action: FlowChoices.Route,
                params: %{queue: :standard, ticket_id: input(:ticket_id)}
    end

    output result("route")
  end
end

{:ok, %{queue: :urgent, ticket_id: 1}} =
  Jido.Exec.run(FlowChoices.TicketQueue, %{ticket_id: 1, priority: 100})

{:ok, %{queue: :standard, ticket_id: 2}} =
  Jido.Exec.run(FlowChoices.TicketQueue, %{ticket_id: 2, priority: 10})
```

A priority of 100 matches both options, but only `"urgent"` runs. Jido stops testing after the first match.

A Choice needs at least one option and exactly one `otherwise`. Option names must be unique within the Choice. Each target has `action` and `params`, and options also have `condition`. These fields can go in keywords or a field block:

```elixir
defmodule FlowChoices.BlockForm do
  use Jido.Flow, name: "flow_choices_block_form"

  flow do
    choice "route" do
      option "refund" do
        condition input(:amount) < 0
        action FlowChoices.Route
        params %{kind: :refund}
      end

      otherwise do
        action FlowChoices.Route
        params %{kind: :charge}
      end
    end

    output result("route")
  end
end

{:ok, %{kind: :refund}} = Jido.Exec.run(FlowChoices.BlockForm, %{amount: -5})
```

## Write conditions

A condition is a Boolean literal, a reference, or an operation from [Expressions](flow-expressions.md). It can combine comparisons, arithmetic, `in`, `and`, `or`, and `not`:

```elixir
defmodule FlowChoices.Eligibility do
  use Jido.Flow,
    name: "flow_choices_eligibility",
    schema:
      Jido.Joi.object(%{
        enabled: Jido.Joi.boolean(),
        blocked: Jido.Joi.boolean(),
        score: Jido.Joi.integer()
      })

  flow do
    choice "check" do
      option "eligible",
        condition: input(:enabled) and not input(:blocked) and input(:score) * 2 >= 100,
        action: FlowChoices.Route,
        params: %{eligible: true}

      otherwise action: FlowChoices.Route, params: %{eligible: false}
    end

    output result("check")
  end
end

{:ok, %{eligible: true}} =
  Jido.Exec.run(FlowChoices.Eligibility, %{enabled: true, blocked: false, score: 60})

{:ok, %{eligible: false}} =
  Jido.Exec.run(FlowChoices.Eligibility, %{enabled: true, blocked: true, score: 60})
```

A condition cannot call application functions. Put a complex or effectful decision in an Action before the Choice, then test that Action's result.

A condition must evaluate to `true` or `false` at runtime. A `nil`, number, or string fails the Flow in the `:choice_condition` phase, with `reason: :invalid_boolean_operand`. A missing key fails the same phase with `reason: :missing_key`. The `schema` above prevents both. See [Conditions and missing values](flow-expressions.md#conditions-and-missing-values).

```elixir
defmodule FlowChoices.Unchecked do
  use Jido.Flow, name: "flow_choices_unchecked"

  flow do
    choice "check" do
      option "enabled", condition: input(:enabled), action: FlowChoices.Route, params: %{on: true}
      otherwise action: FlowChoices.Route, params: %{on: false}
    end

    output result("check")
  end
end

{:error, %Jido.Error.ExecutionError{phase: :choice_condition, details: %{reason: reason}}} =
  Jido.Exec.run(FlowChoices.Unchecked, %{enabled: nil})

:invalid_boolean_operand = reason
```

## The fallback routes and does not recover

`otherwise` is the normal route when no option matches. It is not an error handler. When the selected Action fails, the Choice fails and the fallback does not run. A fallback failure also fails the Choice.

## Targets

Option and fallback targets must be Action modules. A Flow module raises `CompileError` with "Flow component has the wrong target kind", and inline bodies are not supported. To branch into a child Flow, use an Action that returns the data you route on, or select the Flow at runtime with `invoke`. See [Dynamic Flows](dynamic-flows.md).

## Every option's references run first

Every `result` reference in every option and the fallback is a static dependency. The referenced components run before the Choice, even when the option that reads them is not selected. [Flow Dependencies](flow-dependencies.livemd) shows this behavior. Put work that must stay lazy inside the selected Action.

## Route an expected failure as data

Step and Choice have no `on_error` option. A failed Step fails the Flow before a later Choice can read it. To route on an expected failure, have an Action convert that one error to data and return every other error unchanged.

```elixir
defmodule FlowChoices.Provider do
  def fetch(:missing), do: {:error, :not_found}
  def fetch(:offline), do: {:error, :offline}
  def fetch(id), do: {:ok, %{id: id}}
end

defmodule FlowChoices.Fetch do
  use Jido.Action, name: "flow_choices_fetch"

  @impl true
  def run(%{id: id}, _context) do
    case FlowChoices.Provider.fetch(id) do
      {:ok, value} -> {:ok, %{status: :ok, value: value}}
      {:error, :not_found} -> {:ok, %{status: :not_found, value: nil}}
      {:error, reason} -> {:error, Jido.Error.execution_error("fetch failed", %{reason: reason})}
    end
  end
end

defmodule FlowChoices.ExpectedFailure do
  use Jido.Flow, name: "flow_choices_expected_failure"

  flow do
    step "fetch", action: FlowChoices.Fetch, params: %{id: input(:id)}

    choice "route" do
      option "missing",
        condition: result("fetch", :status) == :not_found,
        action: FlowChoices.Route,
        params: %{route: :missing}

      otherwise action: FlowChoices.Route,
                params: %{route: :found, value: result("fetch", :value)}
    end

    output result("route")
  end
end

{:ok, %{route: :found, value: %{id: 1}}} =
  Jido.Exec.run(FlowChoices.ExpectedFailure, %{id: 1})

{:ok, %{route: :missing}} = Jido.Exec.run(FlowChoices.ExpectedFailure, %{id: :missing})

{:error, %Jido.Error.ExecutionError{message: "fetch failed"}} =
  Jido.Exec.run(FlowChoices.ExpectedFailure, %{id: :offline})
```

The Flow treats `:not_found` as a successful result, and an unexpected error still fails it. If the operation is another Action, run it through `Jido.Exec` so its validation runs, or move the shared code to an ordinary function.

## Data form

In a map definition, a Choice has `kind: :choice`, an ordered `options` list, and a `fallback` map. See [Flow Data Definitions](../flow-data/flow-data.md).
