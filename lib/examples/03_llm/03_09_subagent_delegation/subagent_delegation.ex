defmodule Jido.Examples.LLMSubagentDelegation.Work do
  @moduledoc "A portable request dispatched to one child Agent after the parent commits."
  @schema Zoi.struct(__MODULE__, %{
            request_id: Zoi.string(),
            tag: Zoi.string(),
            role: Zoi.enum(["researcher", "reviewer"]),
            prompt: Zoi.string() |> Zoi.min(1)
          })
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.LLMSubagentDelegation.Deliver do
  @moduledoc """
  Transfers the specialist client explicitly through the child's caller context.
  Signals and Directives contain request data only. Each child runs its own Turn.
  A failed child call becomes a correlated result Signal to the parent.
  """
  use Jido.Plugin
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.LLM.Adapter
  alias Jido.Examples.LLMSubagentDelegation.Work

  def directives(_), do: [Work]
  def validate_directive(%Work{} = work, _), do: Zoi.parse(Work.schema(), work)

  def dispatch(nil, %Work{} = work, context, _) do
    child =
      Jido.whereis_agent(context.jido, "#{context.agent_id}/#{work.tag}",
        partition: context.partition
      )

    signal =
      Adapter.signal(
        "specialist.work",
        Map.take(Map.from_struct(work), [:request_id, :tag, :role, :prompt])
      )

    # The child has an independent execution deadline. A Server.call wait timeout
    # alone would not cancel its work, so the parent also stops failed children.
    case call_child(child, signal, context.turn_context.specialist) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        parent = Jido.whereis_agent(context.jido, context.agent_id, partition: context.partition)

        Server.cast(
          parent,
          Adapter.signal("delegate.result", %{
            request_id: work.request_id,
            tag: work.tag,
            status: :failed,
            answer: "",
            error: inspect(reason)
          })
        )
    end
  end

  defp call_child(child, signal, client) do
    Server.call(child, signal, context: %{model: client}, timeout: 2_000)
  catch
    :exit, reason -> {:error, reason}
  end
end

defmodule Jido.Examples.LLMSubagentDelegation.SpecialistWork do
  @moduledoc false
  alias Jido.Agent.Directive
  alias Jido.Examples.LLM.Adapter

  use Jido.Action,
    name: "llm_specialist_work",
    schema:
      Zoi.object(%{
        request_id: Zoi.string() |> Zoi.min(1),
        tag: Zoi.string() |> Zoi.min(1),
        role: Zoi.enum(["researcher", "reviewer"]),
        prompt: Zoi.string() |> Zoi.min(1)
      })

  def run(input, context) do
    with {:ok, raw} <- Adapter.call(context, :model, :complete, Map.take(input, [:role, :prompt])),
         {:ok, result} <- Adapter.parse(Adapter.answer_schema(), raw) do
      reply =
        Adapter.signal("delegate.result", %{
          request_id: input.request_id,
          tag: input.tag,
          status: :complete,
          answer: result.answer,
          error: ""
        })

      {:ok, %{answer: result.answer, request_id: input.request_id},
       [Directive.emit_to_parent(reply)]}
    end
  end
end

defmodule Jido.Examples.LLMSubagentDelegation.Specialist do
  @moduledoc "One child Agent with a model client supplied per work Signal."
  use Jido.Agent, name: "llm_specialist_agent"

  agent do
    schema Zoi.object(%{
             answer: Zoi.string() |> Zoi.default(""),
             request_id: Zoi.string() |> Zoi.default("")
           })
  end

  routes do
    route "llm.specialist.work", Jido.Examples.LLMSubagentDelegation.SpecialistWork
  end
end

defmodule Jido.Examples.LLMSubagentDelegation.Start do
  @moduledoc false
  alias Jido.Agent.Directive
  alias Jido.Examples.LLM.Adapter
  alias Jido.Examples.LLMSubagentDelegation.{Specialist, Work}

  use Jido.Action,
    name: "llm_delegate_start",
    schema:
      Zoi.object(%{request_id: Zoi.string() |> Zoi.min(1), prompt: Zoi.string() |> Zoi.min(1)})

  def run(input, %{agent_state: state} = context) do
    cond do
      state.status == :working ->
        Adapter.invalid("a subagent request is already active")

      input.request_id in state.seen ->
        Adapter.invalid("duplicate request ID")

      not match?({module, _} when is_atom(module), context[:specialist]) ->
        Adapter.invalid("specialist client is required")

      true ->
        plan(input, state, context)
    end
  end

  defp plan(input, state, context) do
    schema =
      Zoi.object(%{
        role: Zoi.enum(["researcher", "reviewer"]),
        prompt: Zoi.string() |> Zoi.min(1)
      })

    with {:ok, raw} <- Adapter.call(context, :model, :delegate, %{prompt: input.prompt}),
         {:ok, plan} <- Adapter.parse(schema, raw) do
      tag = input.request_id
      work = %Work{request_id: input.request_id, tag: tag, role: plan.role, prompt: plan.prompt}

      next = %{
        state
        | status: :working,
          pending: %{request_id: input.request_id, tag: tag},
          seen: state.seen ++ [input.request_id]
      }

      {:ok, next,
       [
         Directive.spawn_agent(Specialist, tag,
           restart: :temporary,
           opts: %{exec_opts: [timeout: 1_000], error_policy: :log_only}
         ),
         work
       ]}
    end
  end
end

defmodule Jido.Examples.LLMSubagentDelegation.Result do
  @moduledoc false
  alias Jido.Agent.Directive

  use Jido.Action,
    name: "llm_delegate_result",
    schema:
      Zoi.object(%{
        request_id: Zoi.string(),
        tag: Zoi.string(),
        status: Zoi.enum([:complete, :failed]),
        answer: Zoi.string(),
        error: Zoi.string()
      })

  def run(%{request_id: id, tag: tag} = input, %{
        agent_state: %{status: :working, pending: %{request_id: id, tag: tag}} = state
      }) do
    result = Map.take(input, [:request_id, :status, :answer, :error])

    {:ok, %{state | status: input.status, pending: %{}, results: state.results ++ [result]},
     [Directive.stop_child(tag)]}
  end

  # Stale/duplicate replies are accepted as unchanged state. A successful no-op
  # Turn still advances the SDK commit revision; request deduplication is separate.
  def run(_, %{agent_state: state}), do: {:ok, state}
end

defmodule Jido.Examples.LLMSubagentDelegation.ChildExit do
  @moduledoc false
  alias Jido.Examples.LLMSubagentDelegation.Result
  use Jido.Action, name: "llm_delegate_child_exit"

  def run(
        %{tag: tag, reason: reason},
        %{agent_state: %{status: :working, pending: %{request_id: id, tag: tag}}} = context
      ) do
    Result.run(
      %{request_id: id, tag: tag, status: :failed, answer: "", error: inspect(reason)},
      context
    )
  end

  def run(_, %{agent_state: state}), do: {:ok, state}
end

defmodule Jido.Examples.LLMSubagentDelegation do
  @moduledoc """
  A model selects one approved specialist role. The parent commits a pending
  request, starts a child Agent, and transfers work through a Signal. The child
  uses its own model Turn and emits a result to the parent. Request IDs reject
  stale replies. This is several commits, not a transaction across Agents.
  """

  use Jido.Agent, name: "llm_delegation_agent"

  agent do
    schema Zoi.object(%{
             status: Zoi.enum([:idle, :working, :complete, :failed]) |> Zoi.default(:idle),
             pending: Zoi.map() |> Zoi.default(%{}),
             seen: Zoi.list(Zoi.string()) |> Zoi.default([]),
             results: Zoi.list(Zoi.map()) |> Zoi.default([])
           })

    plugin Jido.Examples.LLMSubagentDelegation.Deliver
  end

  routes do
    signal_source "/examples/llm"

    route "llm.delegate", Jido.Examples.LLMSubagentDelegation.Start do
      define :delegate, args: [:request_id, :prompt]
    end

    route "llm.delegate.result", Jido.Examples.LLMSubagentDelegation.Result
    route "jido.agent.child.exit", Jido.Examples.LLMSubagentDelegation.ChildExit

    route "jido.agent.child.started" do
      action _input, name: "llm_delegate_child_started", context: context do
        {:ok, context.agent_state}
      end
    end
  end
end
