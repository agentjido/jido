defmodule Jido.Plugin.RouteSelectionTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Plugin.{Preparation, RouteSelection}

  defmodule Select do
    use Jido.Action,
      name: "plugin_route_selection_select",
      schema: Zoi.object(%{selected: Zoi.atom()})

    @impl true
    def run(%{selected: selected}, context) do
      {:ok, %{context.agent_state | selected: selected}}
    end
  end

  defmodule StatefulSelector do
    use Jido.Plugin

    @impl true
    def state_spec(_opts) do
      schema =
        Zoi.object(%{route: Zoi.atom() |> Zoi.default(:left)})
        |> Zoi.default(%{route: :left})

      {:selector, schema}
    end

    @impl true
    def prepare(%Preparation{} = preparation, _opts) do
      {:ok,
       %{
         route: preparation.plugin_state.route,
         candidates: Enum.map(preparation.route_candidates, & &1.as)
       }}
    end

    @impl true
    def select_route(%RouteSelection{} = selection, _opts) do
      expected = Enum.map(selection.candidates, & &1.as)

      if selection.prepared_input.candidates == expected do
        {:ok, selection.prepared_input.route}
      else
        {:error, :candidate_order_changed}
      end
    end
  end

  defmodule DefaultSelector do
    use Jido.Plugin

    @impl true
    def select_route(%RouteSelection{}, _opts), do: :default
  end

  defmodule MissingSelector do
    use Jido.Plugin

    @impl true
    def select_route(%RouteSelection{}, _opts), do: {:ok, :missing}
  end

  defmodule WildcardSelector do
    use Jido.Plugin

    @impl true
    def select_route(%RouteSelection{}, _opts), do: {:ok, :wildcard}
  end

  defmodule StatefulAgent do
    use Jido.Agent,
      name: "plugin_stateful_route_selector",
      plugins: [StatefulSelector]

    state do
      schema Zoi.object(%{selected: Zoi.atom() |> Zoi.default(:none)})
    end

    routes do
      signal_source "/plugin/route_selection/stateful"

      route "select", Select, as: :left, defaults: %{selected: :left}
      route "select", Select, as: :right, defaults: %{selected: :right}
    end
  end

  defmodule DefaultAgent do
    use Jido.Agent,
      name: "plugin_default_route_selector",
      plugins: [DefaultSelector]

    state do
      schema Zoi.object(%{selected: Zoi.atom() |> Zoi.default(:none)})
    end

    routes do
      signal_source "/plugin/route_selection/default"

      route "select", Select, as: :left, defaults: %{selected: :left}
      route "select", Select, as: :right, defaults: %{selected: :right}
    end
  end

  defmodule MissingAgent do
    use Jido.Agent,
      name: "plugin_missing_route_selector",
      plugins: [MissingSelector]

    state do
      schema Zoi.object(%{selected: Zoi.atom() |> Zoi.default(:none)})
    end

    routes do
      signal_source "/plugin/route_selection/missing"

      route "select", Select, as: :left, defaults: %{selected: :left}
      route "select", Select, as: :right, defaults: %{selected: :right}
    end
  end

  defmodule OrderedAgent do
    use Jido.Agent, name: "plugin_ordered_route_selection"

    state do
      schema Zoi.object(%{selected: Zoi.atom() |> Zoi.default(:none)})
    end

    routes do
      signal_source "/plugin/route_selection/ordered"

      route "select.exact", Select, as: :exact, defaults: %{selected: :exact}
      route "select.*", Select, defaults: %{selected: :wildcard}
    end
  end

  defmodule WildcardAgent do
    use Jido.Agent,
      name: "plugin_wildcard_route_selector",
      plugins: [WildcardSelector]

    state do
      schema Zoi.object(%{selected: Zoi.atom() |> Zoi.default(:none)})
    end

    routes do
      signal_source "/plugin/route_selection/wildcard"

      route "select.exact", Select, as: :exact, defaults: %{selected: :exact}
      route "select.*", Select, as: :wildcard, defaults: %{selected: :wildcard}
    end
  end

  test "one selector chooses between same-Signal routes from Plugin state" do
    agent =
      StatefulAgent.instantiate!(
        id: "stateful",
        state: %{selector: %{route: :right}}
      )

    assert {:ok, signal} = StatefulAgent.left_signal(%{})
    assert {:ok, selected, []} = Agent.cmd(agent, signal)
    assert selected.state.selected == :right
    assert selected.state.selector == %{route: :right}
  end

  test "default preserves ordered selection when no selector Plugin exists" do
    agent = OrderedAgent.instantiate!(id: "ordered")
    signal = Jido.Signal.new!("select.exact", %{}, source: agent.signal_source)

    assert {:ok, selected, []} = Agent.cmd(agent, signal)
    assert selected.state.selected == :exact
  end

  test "default rejects unresolved ambiguity when a selector is active" do
    agent = DefaultAgent.instantiate!(id: "default")
    signal = Jido.Signal.new!("select", %{}, source: agent.signal_source)

    assert {:error, error} = Agent.cmd(agent, signal)
    assert error.details.code == :ambiguous_route_selection
  end

  test "a selector cannot choose a route that does not match the Signal" do
    agent = MissingAgent.instantiate!(id: "missing")
    signal = Jido.Signal.new!("select", %{}, source: agent.signal_source)

    assert {:error, error} = Agent.cmd(agent, signal)
    assert error.details.code == :invalid_route_selection
    assert error.details.route == :missing
  end

  test "a selector can use a wildcard alias without generating an invalid Signal helper" do
    agent = WildcardAgent.instantiate!(id: "wildcard")
    signal = WildcardAgent.exact_signal!(%{})

    assert {:ok, selected, []} = Agent.cmd(agent, signal)
    assert selected.state.selected == :wildcard
    refute function_exported?(WildcardAgent, :wildcard_signal, 0)
    refute function_exported?(WildcardAgent, :wildcard_signal, 2)
  end

  test "duplicate paths still fail without a selector Plugin" do
    assert {:error, error} =
             Agent.define(%{
               name: "duplicate_without_selector",
               routes: [
                 route("same", :left),
                 route("same", :right)
               ]
             })

    assert error.code == :duplicate
  end

  test "multiple selector Plugins fail definition validation" do
    assert {:error, error} =
             Agent.define(%{
               name: "multiple_route_selectors",
               plugins: [extension(StatefulSelector), extension(DefaultSelector)]
             })

    assert error.message == "Only one Agent Plugin can select routes"
  end

  test "ambiguous candidates require non-nil aliases" do
    assert {:error, error} =
             Agent.define(%{
               name: "missing_route_alias",
               plugins: [extension(DefaultSelector)],
               routes: [
                 route("same", nil),
                 route("same", :named)
               ]
             })

    assert error.message == "Duplicate routes require aliases for Plugin selection"
  end

  defp extension(module) do
    %{id: module.id(), provider: module, vsn: module.vsn(), data: %{}}
  end

  defp route(path, as) do
    %{
      path: path,
      as: as,
      defaults: %{},
      handler: %{kind: :action, target: Select},
      state: :unchanged,
      reply: nil
    }
  end
end
