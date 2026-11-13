defmodule Jido.Examples.DataDefinedAgent do
  @moduledoc "Builds, encodes, and runs one neutral Agent definition."

  alias Jido.Agent
  alias Jido.Catalog
  alias Jido.Plugin.Scheduler

  defmodule Add do
    @moduledoc "Adds one validated amount to the current count."
    use Jido.Action,
      name: "basic_data_defined_add",
      schema: Jido.Joi.object(%{amount: Jido.Joi.integer()})

    def run(%{amount: amount}, %{agent_state: state}),
      do: {:ok, %{state | count: state.count + amount}}
  end

  defmodule ScheduleTick do
    @moduledoc "Requests a later count change through the Scheduler Plugin."
    use Jido.Action,
      name: "basic_data_defined_schedule",
      schema: Jido.Joi.object(%{delay_ms: Jido.Joi.integer() |> Jido.Joi.min(0)})

    def run(%{delay_ms: delay_ms}, %{agent_state: state}) do
      tick = Jido.Examples.DataDefinedAgent.signal!(1)
      {:ok, state, [Scheduler.schedule(delay_ms, tick)]}
    end
  end

  defmodule CountTurns do
    @moduledoc "Owns a count of committed Turns."
    use Jido.Plugin

    @impl true
    def state_spec(_opts), do: {:turns, Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.default(0)}

    @impl true
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
  end

  @doc "Returns the validated neutral Agent definition."
  def definition do
    Agent.define!(%{
      name: "basic_data_defined_agent",
      schema: Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)}),
      plugins: [
        %{id: CountTurns.id(), provider: CountTurns, vsn: CountTurns.vsn(), data: %{}},
        %{
          id: Scheduler.id(),
          provider: Scheduler,
          vsn: Scheduler.vsn(),
          data: %{retry_delay_ms: 25}
        }
      ],
      routes: [
        %{
          path: "examples.basic.data_defined.add",
          handler: %{kind: :action, target: Add}
        },
        %{
          path: "examples.basic.data_defined.schedule",
          handler: %{kind: :action, target: ScheduleTick}
        }
      ]
    })
  end

  @doc "Returns the application-owned references required by the stored document."
  def registry do
    Catalog.from_targets!(__MODULE__, :jido, %{
      {"schemas/counter", 1} => definition().schema,
      {"actions/add", 1} => Add,
      {"actions/schedule", 1} => ScheduleTick,
      {"plugins/count-turns", 1} => CountTurns,
      {"plugins/scheduler", 1} => Scheduler,
      {"atoms/retry-delay", 1} => :retry_delay_ms,
      {"atoms/turns", 1} => :turns,
      {"atoms/scheduler", 1} => :scheduler
    })
  end

  @doc "Encodes one validated definition with stable application references."
  def encode do
    registry = registry()

    {:ok, document} = Jido.Codec.encode(definition(), catalog: registry)

    {document, registry}
  end

  @doc "Reads the stored authoring input used by the lesson."
  def fixture_json, do: File.read!(Path.join(__DIR__, "fixtures/agent.json"))

  @doc "Imports the JSON document without starting an Agent or its Plugins."
  def from_json(json) do
    {:ok, codec} = Jido.Codec.Encoder.codec(definition())
    Jido.Codec.decode_json(json, catalog: registry(), codec: codec)
  end

  @doc "Builds a request to deliver a count command after the current Turn."
  def schedule_signal!(delay_ms) do
    Jido.Signal.new!(
      "examples.basic.data_defined.schedule",
      %{delay_ms: delay_ms},
      source: "/examples/basic/data_defined_agent"
    )
  end

  @doc "Builds one command Signal for the data-defined route."
  def signal!(amount) do
    Jido.Signal.new!(
      "examples.basic.data_defined.add",
      %{amount: amount},
      source: "/examples/basic/data_defined_agent"
    )
  end
end
