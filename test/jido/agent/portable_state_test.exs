defmodule Jido.Agent.PortableStateTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Signal

  defmodule NonportableAction do
    use Jido.Action, name: "nonportable_state_action"

    @impl Jido.Action
    def run(%{payload: value}, _context), do: {:ok, %{payload: value}}
  end

  defmodule NonportableCheckpointAgent do
    use Jido.Agent, name: "nonportable_checkpoint_agent"

    @impl Jido.Agent
    def checkpoint(_agent, _context), do: {:ok, %{runtime: self()}}

    @impl Jido.Agent
    def restore(_checkpoint, _context), do: new()
  end

  test "local values pass live validation but default checkpoints reject them with bounded paths" do
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
      assert {:ok, agent} = Agent.instantiate(definition, state: %{payload: value})
      assert agent.state.payload === value
      assert {:ok, ^agent} = Agent.validate_instance(agent)

      assert {:error,
              %Jido.Error.ValidationError{
                details: %{code: :non_portable_term, path: path}
              }} = Agent.checkpoint(agent)

      assert Enum.take(path, 3) == [:checkpoint, :state, :payload]
      assert length(path) <= 20
      assert {:ok, checkpoint} = Agent.checkpoint(%{agent | state: %{payload: nil}})

      assert {:error, %{details: %{code: :non_portable_term, path: ^path}}} =
               Agent.restore(Agent, %{checkpoint | state: %{payload: value}})
    end

    deep_value = Enum.reduce(1..30, self(), fn index, value -> %{index => value} end)

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{code: :non_portable_term, path: deep_path}
            }} = checkpoint_value(definition, deep_value)

    assert length(deep_path) == 20
  end

  test "bounds every diagnostic path segment" do
    definition = Agent.new!(name: "portable_path", schema: Zoi.object(%{payload: Zoi.any()}))
    long_binary = String.duplicate("b", 100)
    long_integer = String.to_integer(String.duplicate("9", 100))
    long_atom = :aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    for key <- [long_binary, long_atom] do
      assert {:error,
              %Jido.Error.ValidationError{
                details: %{
                  code: :non_portable_term,
                  path: [:checkpoint, :state, :payload, segment]
                }
              }} = checkpoint_value(definition, %{key => self()})

      assert is_binary(segment)
      assert byte_size(segment) == 64
    end

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{
                code: :non_portable_term,
                path: [:checkpoint, :state, :payload, {:map_value, 0}]
              }
            }} = checkpoint_value(definition, %{long_integer => self()})

    assert {:error, [root_segment]} =
             Jido.PortableTerm.validate(self(), [String.duplicate("r", 100)])

    assert root_segment == String.duplicate("r", 64)
  end

  test "transition and command candidates permit schema-approved local values" do
    definition =
      Agent.new!(
        name: "local_transition",
        schema: Zoi.object(%{payload: Zoi.any()}),
        routes: [{"local.run", NonportableAction}]
      )

    agent = Agent.instantiate!(definition, state: %{payload: :initial})
    port = Port.open({:spawn_executable, System.find_executable("true")}, [])
    on_exit(fn -> if Port.info(port), do: Port.close(port) end)

    for value <- [self(), port, make_ref(), fn -> :ok end, [1 | :tail], <<5::size(3)>>] do
      assert {:ok, transitioned} = Agent.transition(agent, %{payload: value})
      assert transitioned.state.payload === value
      signal = Signal.new!("local.run", %{payload: value}, source: "/test")
      assert {:ok, candidate, []} = Agent.cmd(agent, signal)
      assert candidate.state.payload === value
    end

    assert agent.state.payload == :initial
  end

  test "live local values must still match the declared schema and identity" do
    definition = Agent.new!(name: "typed_local", schema: Zoi.object(%{payload: Zoi.pid()}))
    agent = Agent.instantiate!(definition, state: %{payload: self()})

    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.instantiate(definition, state: %{payload: <<5::size(3)>>})

    assert {:error, %Jido.Error.ValidationError{}} = Agent.transition(agent, %{payload: :invalid})
    assert {:error, %Jido.Error.ValidationError{}} = Agent.validate_instance(%{agent | id: ""})
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

  defp checkpoint_value(definition, value) do
    definition |> Agent.instantiate!(state: %{payload: value}) |> Agent.checkpoint()
  end
end
