defmodule Jido.Agent.PortableStateTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Signal

  defmodule NonportableAction do
    use Jido.Action, name: "nonportable_state_action"

    @impl Jido.Action
    def run(_input, _context), do: {:ok, %{payload: self()}}
  end

  defmodule NonportableCheckpointAgent do
    use Jido.Agent, name: "nonportable_checkpoint_agent"

    @impl Jido.Agent
    def checkpoint(_agent, _context), do: {:ok, %{runtime: self()}}

    @impl Jido.Agent
    def restore(_checkpoint, _context), do: new()
  end

  test "every prohibited state term returns a typed error with a bounded path" do
    port = Port.open({:spawn_executable, System.find_executable("true")}, [])
    on_exit(fn -> if Port.info(port), do: Port.close(port) end)

    values = [
      self(),
      port,
      make_ref(),
      fn -> :runtime end,
      [1 | :improper],
      <<1::size(1)>>
    ]

    definition = Agent.new!(name: "portable_state", schema: Zoi.object(%{payload: Zoi.any()}))

    for value <- values do
      assert {:error,
              %Jido.Error.ValidationError{
                details: %{code: :non_portable_term, path: path}
              }} = Agent.instantiate(definition, state: %{payload: value})

      assert Enum.take(path, 2) == [:agent_state, :payload]
      assert length(path) <= 20
    end

    deep_value = Enum.reduce(1..30, self(), fn index, value -> %{index => value} end)

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{code: :non_portable_term, path: deep_path}
            }} = Agent.instantiate(definition, state: %{payload: deep_value})

    assert length(deep_path) == 20
  end

  test "transition and command candidates use the same portable-state boundary" do
    definition =
      Agent.new!(
        name: "portable_transition",
        schema: Zoi.object(%{payload: Zoi.any()}),
        routes: [{"portable.run", NonportableAction}]
      )

    agent = Agent.instantiate!(definition, state: %{payload: :portable})

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{code: :non_portable_term, path: [:agent_state, :payload]}
            }} = Agent.transition(agent, %{payload: self()})

    signal = Signal.new!("portable.run", %{}, source: "/test")

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{code: :non_portable_term, path: [:agent_state, :payload]}
            }} = Agent.cmd(agent, signal)
  end

  test "checkpoint output is portable and reports the invalid payload path" do
    agent = NonportableCheckpointAgent.new!(id: "checkpoint")

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{
                code: :non_portable_term,
                path: [:checkpoint, :payload, :runtime]
              }
            }} = Agent.checkpoint(agent)
  end

  test "direct definitions remain valid but only portable embedded definitions checkpoint" do
    definition = Agent.new!(name: "runtime_definition", metadata: %{runtime: fn -> :ok end})
    agent = Agent.instantiate!(definition, id: "runtime-definition")

    assert agent.metadata.runtime.() == :ok

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{
                code: :non_portable_term,
                path: [:checkpoint, :definition, :metadata, :runtime]
              }
            }} = Agent.checkpoint(agent)
  end
end
