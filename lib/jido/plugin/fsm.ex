defmodule Jido.Plugin.FSM do
  @moduledoc """
  Adds deterministic finite-state route control to one Agent.

  The Plugin owns the `:fsm` field in Agent state. It selects only an authored
  route alias that already matches the incoming Signal. Actions and Flows keep
  ownership of execution and output projection. The Plugin advances its state
  only after that execution succeeds.

  Declare the Plugin as an Agent extension to use its authoring section:

      use Jido.Agent,
        name: "setup_guide",
        extensions: [Jido.Plugin.FSM]

      state_machine do
        initial :idle
        terminal :ready

        transition :start,
          from: :idle,
          route: :start_scan,
          to: :scanning
      end

  The DSL lowers to the same canonical Plugin data used by map-authored Agent
  definitions. The runtime has no second state-machine representation.
  """

  alias Jido.Agent.{Data, Error}
  alias Jido.Agent.Plugin.{Preparation, Reduction, RouteSelection}
  alias Jido.Plugin.FSM.Transition
  alias Spark.Dsl.Extension, as: SparkExtension

  @default_version 1

  @transition %Spark.Dsl.Entity{
    name: :transition,
    target: Transition,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      from: [type: :atom, required: true],
      route: [type: :atom, required: true],
      to: [type: :atom, required: true]
    ]
  }

  @state_machine %Spark.Dsl.Section{
    name: :state_machine,
    entities: [@transition],
    schema: [
      version: [type: :pos_integer, default: @default_version],
      initial: [type: :atom, required: true],
      terminal: [type: {:wrap_list, :atom}, default: []]
    ]
  }

  use Jido.Plugin,
    id: "jido.fsm",
    sections: [@state_machine]

  @type machine_state :: atom()
  @type transition :: %{
          name: atom(),
          from: machine_state(),
          route: atom(),
          to: machine_state()
        }
  @type config :: %{
          version: pos_integer(),
          initial: machine_state(),
          terminal: [machine_state()],
          transitions: [transition()]
        }
  @type owned_state :: %{version: pos_integer(), current: machine_state()}

  @impl Jido.Agent.Extension
  def lower(dsl, config) do
    transitions = SparkExtension.get_entities(dsl, [:state_machine])
    initial = SparkExtension.get_opt(dsl, [:state_machine], :initial)
    terminal = SparkExtension.get_opt(dsl, [:state_machine], :terminal, [])
    version = SparkExtension.get_opt(dsl, [:state_machine], :version, @default_version)
    dsl? = not is_nil(initial) or terminal != [] or transitions != []

    cond do
      config != %{} and dsl? ->
        Error.fail(:ambiguous_config, [], "Use state_machine DSL or Plugin data, not both")

      config != %{} ->
        {:ok, config}

      true ->
        {:ok,
         %{
           version: version,
           initial: initial,
           terminal: terminal,
           transitions: Enum.map(transitions, &transition_data/1)
         }}
    end
  end

  @impl Jido.Agent.Extension
  def normalize(value) do
    with {:ok, value} <-
           Data.fields(
             value,
             [:version, :initial, :terminal, :transitions],
             %{version: @default_version, terminal: [], transitions: []}
           ),
         :ok <- Error.at(Data.positive(value[:version]), :version),
         :ok <- Error.at(Data.name(value[:initial]), :initial),
         {:ok, terminal} <-
           Error.at(Data.list(value.terminal, &state/1), :terminal),
         :ok <- Error.at(Data.unique(terminal, & &1), :terminal),
         {:ok, transitions} <-
           Error.at(Data.list(value.transitions, &normalize_transition/1), :transitions),
         :ok <- unique_transitions(transitions),
         :ok <- terminal_rules(terminal, transitions),
         :ok <- reachable(value.initial, terminal, transitions) do
      {:ok,
       %{
         version: value.version,
         initial: value.initial,
         terminal: terminal,
         transitions: transitions
       }}
    end
  end

  @impl Jido.Agent.Extension
  def verify(config, definition) do
    config.transitions
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {transition, index}, :ok ->
      case Enum.find(definition.routes, &(&1.as == transition.route)) do
        nil ->
          {:halt,
           Error.fail(
             :unknown_fsm_route,
             [:transitions, index, :route],
             "FSM transition references an unknown route alias",
             %{route: transition.route}
           )}

        %{handler: %{kind: kind}} when kind in [:action, :flow] ->
          {:cont, :ok}

        route ->
          {:halt,
           Error.fail(
             :invalid_fsm_route,
             [:transitions, index, :route],
             "FSM transitions require an Action or Flow route",
             %{route: transition.route, handler: route.handler.kind}
           )}
      end
    end)
  end

  @impl true
  def state_spec(opts) do
    config = config(opts)
    states = states(config)

    schema =
      Zoi.object(%{
        version: Zoi.enum([config.version]) |> Zoi.default(config.version),
        current: Zoi.enum(states) |> Zoi.default(config.initial)
      })
      |> Zoi.default(%{version: config.version, current: config.initial})

    {:fsm, schema}
  end

  @impl true
  def prepare(%Preparation{} = preparation, opts) do
    config = config(opts)

    with :ok <- state_version(preparation.plugin_state, config),
         {:ok, decision} <-
           resolve_transition(
             preparation.plugin_state.current,
             preparation.route_candidates,
             config
           ) do
      {:ok, decision}
    end
  end

  @impl true
  def select_route(%RouteSelection{prepared_input: %{kind: :default}}, _opts), do: :default

  def select_route(
        %RouteSelection{prepared_input: %{kind: :transition, route: route}},
        _opts
      ),
      do: {:ok, route}

  def select_route(%RouteSelection{prepared_input: prepared}, _opts) do
    {:error,
     Jido.Error.execution_error("FSM prepared route decision is invalid",
       details: %{code: :invalid_fsm_decision, decision: prepared}
     )}
  end

  @impl true
  def reduce(%Reduction{prepared_input: %{kind: :default}} = reduction, _opts),
    do: {:ok, reduction.plugin_state}

  def reduce(
        %Reduction{
          plugin_state: %{current: current} = state,
          prepared_input: %{
            kind: :transition,
            name: name,
            from: from,
            to: to
          }
        },
        _opts
      ) do
    if current == from do
      {:ok, %{state | current: to}}
    else
      {:error,
       Jido.Error.execution_error("FSM state changed before reduction",
         details: %{
           code: :stale_fsm_transition,
           transition: name,
           expected: from,
           current: current
         }
       )}
    end
  end

  def reduce(%Reduction{prepared_input: prepared}, _opts) do
    {:error,
     Jido.Error.execution_error("FSM prepared reduction is invalid",
       details: %{code: :invalid_fsm_decision, decision: prepared}
     )}
  end

  defp transition_data(%Transition{} = transition) do
    Map.take(transition, [:name, :from, :route, :to])
  end

  defp normalize_transition(value) do
    with {:ok, transition} <- Data.fields(value, [:name, :from, :route, :to]),
         :ok <- Error.at(Data.name(transition[:name]), :name),
         :ok <- Error.at(Data.name(transition[:from]), :from),
         :ok <- Error.at(Data.name(transition[:route]), :route),
         :ok <- Error.at(Data.name(transition[:to]), :to),
         do: {:ok, transition}
  end

  defp state(value) do
    with :ok <- Data.name(value), do: {:ok, value}
  end

  defp unique_transitions(transitions) do
    with :ok <- Error.at(Data.unique(transitions, & &1.name), :name),
         do: Error.at(Data.unique(transitions, &{&1.from, &1.route}), :source_route)
  end

  defp terminal_rules(terminal, transitions) do
    case Enum.find(transitions, &(&1.from in terminal)) do
      nil ->
        :ok

      transition ->
        Error.fail(
          :terminal_fsm_transition,
          [],
          "FSM terminal states cannot have outgoing transitions",
          %{state: transition.from, transition: transition.name}
        )
    end
  end

  defp reachable(initial, terminal, transitions) do
    all =
      transitions
      |> Enum.flat_map(&[&1.from, &1.to])
      |> Kernel.++([initial | terminal])
      |> MapSet.new()

    reached = walk_states(MapSet.new([initial]), transitions)
    unreachable = all |> MapSet.difference(reached) |> MapSet.to_list() |> Enum.sort()

    if unreachable == [] do
      :ok
    else
      Error.fail(
        :unreachable_fsm_state,
        [],
        "FSM contains states that cannot be reached from its initial state",
        %{states: unreachable}
      )
    end
  end

  defp walk_states(reached, transitions) do
    next =
      Enum.reduce(transitions, reached, fn transition, acc ->
        if MapSet.member?(reached, transition.from),
          do: MapSet.put(acc, transition.to),
          else: acc
      end)

    if MapSet.equal?(next, reached), do: reached, else: walk_states(next, transitions)
  end

  defp state_version(%{version: version}, %{version: version}), do: :ok

  defp state_version(state, config) do
    {:error,
     Jido.Error.execution_error("FSM state version does not match its definition",
       details: %{
         code: :fsm_version_mismatch,
         state_version: Map.get(state, :version),
         definition_version: config.version
       }
     )}
  end

  defp resolve_transition(current, candidates, config) do
    aliases = candidates |> Enum.map(& &1.as) |> MapSet.new()

    managed =
      Enum.filter(config.transitions, fn transition ->
        MapSet.member?(aliases, transition.route)
      end)

    valid = Enum.filter(managed, &(&1.from == current))

    case {valid, managed} do
      {[transition], _managed} ->
        {:ok, Map.put(transition, :kind, :transition)}

      {[], []} ->
        {:ok, %{kind: :default}}

      {[], managed} ->
        {:error,
         Jido.Error.execution_error("FSM rejected an event in the current state",
           details: %{
             code: :invalid_fsm_transition,
             current: current,
             routes: Enum.map(managed, & &1.route)
           }
         )}

      {transitions, _managed} ->
        {:error,
         Jido.Error.execution_error("FSM found more than one valid transition",
           details: %{
             code: :ambiguous_fsm_transition,
             current: current,
             transitions: Enum.map(transitions, & &1.name)
           }
         )}
    end
  end

  defp config(opts), do: Map.new(opts)

  defp states(config) do
    config.transitions
    |> Enum.flat_map(&[&1.from, &1.to])
    |> Kernel.++([config.initial | config.terminal])
    |> Enum.uniq()
  end
end
