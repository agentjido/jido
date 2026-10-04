defmodule JidoTest.Examples.Basic.AgentExtensionTest do
  use JidoTest.BasicSDKCase

  alias Jido.Agent.Extension
  alias Jido.Examples.AgentExtension
  alias Jido.Examples.AgentExtension.{Flag, Flags, Label, Labels}

  defmodule Foreign do
    defstruct [:value]
  end

  defmodule Invalid do
    def lower_agent(config, entities),
      do: {:ok, Map.put(config, :unknown_field, true), entities}
  end

  test "owned entities lower in order without starting a process", %{jido: jido} do
    definition = AgentExtension.Agent.definition()

    assert definition.metadata == %{
             owner: "examples",
             flags: [:audited],
             extension_order: [:labels, :flags]
           }

    instance = AgentExtension.Agent.new!(id: unique_id("agent-extension"))
    assert Jido.whereis_agent(jido, instance.id) == nil

    {:ok, signal} = AgentExtension.Agent.add_signal(%{amount: 3})
    assert {:ok, result, []} = Jido.Agent.cmd(instance, signal)
    assert result.state.count == 3
    assert Jido.whereis_agent(jido, instance.id) == nil

    config = %{metadata: %{}, routes: []}

    assert {:ok, lowered} =
             Extension.lower(
               [Labels, Flags],
               config,
               [%Label{key: :team, value: "sdk"}, %Flag{name: :stable}]
             )

    assert lowered.metadata == %{
             team: "sdk",
             flags: [:stable],
             extension_order: [:labels, :flags]
           }
  end

  test "unclaimed data and invalid lowered configuration are rejected" do
    config = %{metadata: %{}, routes: []}

    assert {:error, error} = Extension.lower([Labels], config, [%Foreign{value: :unknown}])
    assert Exception.message(error) == "Unclaimed Agent extension entities"

    assert {:ok, lowered} = Extension.lower([Invalid], config, [])
    assert {:error, %Jido.Error.ValidationError{}} = Jido.Agent.new(lowered)
  end
end
