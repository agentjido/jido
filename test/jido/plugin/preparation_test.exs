defmodule Jido.Plugin.PreparationTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Command.Runner
  alias Jido.Agent.Plugin.Preparation
  alias Jido.Plugin
  alias Jido.Signal
  alias JidoTest.AgentFixtures.Add

  defmodule IsolatedFacet do
    @moduledoc false
    use Jido.Agent.Plugin

    def observes(opts), do: Keyword.get(opts, :observes, [:visible])
    def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(7)}

    def prepare(preparation, opts) do
      if observer = opts[:observer],
        do: send(Process.whereis(observer), {:preparation, preparation})

      result =
        case opts[:mode] do
          {:change, field, value} -> Map.put(preparation, field, value)
          :nonportable -> %{preparation | input: self()}
          _other -> %{preparation | input: %{visible: preparation.agent_state.visible}}
        end

      {:ok, result}
    end
  end

  defmodule Isolated do
    @moduledoc false
    use Jido.Plugin, agent: IsolatedFacet
  end

  defmodule InvalidObservationsFacet do
    @moduledoc false
    use Jido.Agent.Plugin

    def observes(opts), do: Keyword.fetch!(opts, :observes)
    def prepare(preparation, _opts), do: {:ok, preparation}
  end

  defmodule InvalidObservations do
    @moduledoc false
    use Jido.Plugin, agent: InvalidObservationsFacet
  end

  defmodule MixedPreparation do
    @moduledoc false
    use Jido.Plugin

    def prepare(command, _opts), do: {:ok, command}
    def prepare_turn(preparation, _opts), do: {:ok, preparation}
  end

  test "Agent facet preparation receives only declared domain state and owned Plugin state" do
    Process.register(self(), IsolatedFacet)
    on_exit(fn -> if Process.whereis(IsolatedFacet), do: Process.unregister(IsolatedFacet) end)

    agent = agent([{Isolated, observer: IsolatedFacet}])
    signal = signal()

    assert {:ok, prepared} = Runner.prepare(agent, signal, [])

    assert_receive {:preparation,
                    %Preparation{
                      plugin: Isolated,
                      agent_id: agent_id,
                      agent_module: Agent,
                      agent_state: %{visible: 2},
                      plugin_state: 7,
                      source_signal: ^signal,
                      effective_signal: ^signal,
                      context: %{},
                      input: nil
                    }}

    assert is_binary(agent_id)
    assert prepared.plugin_inputs == %{Isolated => %{visible: 2}}
    assert prepared.context.plugin_inputs == prepared.plugin_inputs
    refute Map.has_key?(prepared.plugin_inputs[Isolated], :private)
    refute Map.has_key?(prepared.plugin_inputs[Isolated], :owned)
  end

  test "normalization validates observation and compatibility callback rules" do
    assert {:ok, [%{observations: [:visible], agent: %{module: IsolatedFacet}}]} =
             Plugin.normalize_all([Isolated])

    for observations <- [["visible"], [:visible, :visible], :visible] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Plugin.normalize_all([{InvalidObservations, observes: observations}])
    end

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Plugin.normalize_all([MixedPreparation])

    assert message == "Agent Plugin must define only one preparation callback"
  end

  test "an Agent facet cannot change read-only preparation fields" do
    source = signal()
    replacement = Signal.new!("other.route", %{}, source: "/test")

    changes = [
      plugin: String,
      agent_state: %{visible: 99},
      plugin_state: 99,
      source_signal: replacement
    ]

    for {field, value} <- changes do
      assert {:error, %Jido.Error.ExecutionError{message: message}} =
               Agent.cmd(agent([{Isolated, mode: {:change, field, value}}]), source)

      assert message == "Agent Plugin preparation changed read-only fields"
    end
  end

  test "prepared input must be portable and observations must name domain fields" do
    assert {:error, %Jido.Error.ExecutionError{details: %{code: :non_portable_term}}} =
             Agent.cmd(agent([{Isolated, mode: :nonportable}]), signal())

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Agent.cmd(agent([{Isolated, observes: [:missing]}]), signal())

    assert message == "Agent Plugin observes unknown Agent fields"
  end

  test "Preparation validates its complete public shape" do
    signal = signal()

    preparation = %Preparation{
      plugin: Isolated,
      agent_id: "agent-1",
      agent_module: Agent,
      agent_state: %{visible: 2},
      plugin_state: 7,
      source_signal: signal,
      effective_signal: signal,
      context: %{},
      input: nil
    }

    assert {:ok, ^preparation} = Preparation.validate(preparation)

    assert {:error, %Jido.Error.ValidationError{}} =
             Preparation.validate(%{preparation | effective_signal: :invalid})

    assert {:error, %Jido.Error.ValidationError{}} = Preparation.validate(:invalid)
  end

  defp agent(plugins) do
    Agent.new!(
      name: "plugin_preparation",
      schema:
        Zoi.object(%{
          visible: Zoi.integer() |> Zoi.default(2),
          private: Zoi.string() |> Zoi.default("secret"),
          count: Zoi.integer() |> Zoi.default(0),
          history: Zoi.list(Zoi.string()) |> Zoi.default([])
        }),
      plugins: plugins,
      routes: [{"plugin.prepare", Add}]
    )
    |> Agent.instantiate!()
  end

  defp signal do
    Signal.new!("plugin.prepare", %{by: 0, label: "prepared"}, source: "/test")
  end
end
