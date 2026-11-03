defmodule Jido.Exec.Node.Wait do
  @moduledoc false
  alias Jido.Exec.{Frame, ValueResolver}
  alias Runic.Workflow.{Fact, Runnable}
  alias Runic.Workflow.Events.{ActivationConsumed, FactProduced}

  @enforce_keys [:id, :name, :hash, :component, :options, :node_path]
  defstruct [:id, :name, :hash, :component, :options, :node_path, :location]
  @type t :: %__MODULE__{}

  @doc false
  @spec new(keyword()) :: t()
  def new(opts) do
    id = Keyword.fetch!(opts, :id)

    struct!(
      __MODULE__,
      Keyword.put(
        opts,
        :hash,
        Runic.Identity.digest(:component_definition, %{
          kind: :jido_wait,
          version: 1,
          id: inspect(id)
        })
      )
    )
  end

  @doc false
  @spec open(t(), Runnable.t()) :: Runnable.t()
  def open(node, runnable) do
    runtime = runnable.context.run_context

    case Map.get(runtime, :__jido_wait_host__) do
      %{execution_id: execution_id, clock: clock} ->
        with {:ok, now} <- read_clock(clock),
             {:ok, frame} <- Frame.merge(Jido.Exec.Fact.value(runnable.input_fact)),
             {:ok, options} <-
               resolve_options(node.options, Frame.resolver_state(frame, runtime), now) do
          request = %{
            type: :jido_wait_request,
            version: 1,
            id: to_string(Runic.Identity.derive(:activation, [execution_id, runnable.activation_id])),
            execution_id: execution_id,
            node_hash: node.hash,
            input_id: runnable.input_fact.hash,
            path: node.node_path,
            options: options,
            opened_at: now
          }

          fact =
            Fact.new(
              value: request,
              meta: %{jido_wait_record: true},
              ancestry: {node.hash, runnable.input_fact.hash}
            )

          # Opening a wait consumes this activation without producing output.
          # A skip would suppress downstream work, including earlier join inputs.
          Runnable.complete(runnable, :waiting, [
            FactProduced.new(fact,
              producer_label: :state_produced,
              weight: runnable.context.ancestry_depth + 1
            ),
            %ActivationConsumed{
              fact_hash: runnable.input_fact.hash,
              node_hash: node.hash,
              from_label: :runnable
            }
          ])
        else
          {:error, [error | _]} -> Runnable.fail(runnable, error)
          {:error, error} -> Runnable.fail(runnable, error)
        end

      _ ->
        Runnable.fail(runnable, unsupported())
    end
  end

  defp resolve_options(options, state, now) do
    Jido.Flow.Component.sequence(options, fn option ->
      with {:ok, match} <- ValueResolver.resolve(option.match, state),
           true <- is_map(match) and not is_struct(match) do
        {:ok,
         %{
           name: option.name,
           event: option.event,
           match: match,
           deadline: if(is_integer(option.after_ms), do: now + option.after_ms)
         }}
      else
        false -> {:error, Jido.Error.validation_error("wait match must resolve to a map")}
        error -> error
      end
    end)
  end

  defp read_clock(clock) when is_function(clock, 0), do: read_clock(clock.())
  defp read_clock(now) when is_integer(now) and now >= 0, do: {:ok, now}

  defp read_clock(_),
    do: {:error, Jido.Error.config_error("invalid wait clock", %{reason: :invalid_clock})}

  @doc false
  @spec validate_host(Runic.Workflow.t(), map()) :: :ok | {:error, Exception.t()}
  def validate_host(workflow, runtime \\ %{}) do
    if not Map.has_key?(runtime, :__jido_wait_host__) and
         Enum.any?(Multigraph.vertices(workflow.graph), &is_struct(&1, __MODULE__)),
       do: {:error, unsupported()},
       else: :ok
  end

  @doc false
  @spec unsupported() :: Exception.t()
  def unsupported,
    do:
      Jido.Error.config_error("execution host does not support waits", %{
        reason: :unsupported_host,
        capability: :waits
      })
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Node.Wait do
  def identity_document(node), do: %{kind: :jido_wait, version: 1, id: inspect(node.id)}
end

defimpl Runic.Workflow.Invokable, for: Jido.Exec.Node.Wait do
  def match_or_execute(_node), do: :execute
  defdelegate prepare(node, workflow, fact), to: Runic.Workflow.SingleOutput
  defdelegate execute(node, runnable), to: Jido.Exec.Node.Wait, as: :open

  def invoke(node, workflow, fact) do
    {:ok, runnable} = prepare(node, workflow, fact)
    Runic.Workflow.apply_runnable(workflow, execute(node, runnable))
  end
end

defimpl Runic.Component, for: Jido.Exec.Node.Wait do
  alias Runic.Workflow
  def connectable?(_node, _other), do: true

  def connect(node, parents, workflow) when is_list(parents) do
    join = Runic.Workflow.Join.new(Enum.map(parents, & &1.hash))
    workflow = Enum.reduce(parents, workflow, &Workflow.add_step(&2, &1, join))
    connect(node, join, workflow)
  end

  def connect(node, parent, workflow) do
    workflow
    |> Workflow.add_step(parent, node)
    |> Workflow.draw_connection(node, node, :component_of, properties: %{kind: :wait})
    |> Workflow.register_component(node)
  end

  def source(node) do
    opts = node |> Map.from_struct() |> Map.delete(:hash) |> Map.to_list()
    quote do: Jido.Exec.Node.Wait.new(unquote(Macro.escape(opts)))
  end

  def hash(node), do: node.hash
  def inputs(_node), do: [in: [type: :any]]
  def outputs(_node), do: [out: [type: :any]]
end
