defmodule Jido.Agent.PortableStateTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Signal

  defmodule NonportableAction do
    use Jido.Action,
      name: "nonportable_state_action",
      output_schema: Zoi.any()

    @impl Jido.Action
    def run(%{payload: value}, _context), do: {:ok, %{payload: value}}
  end

  defmodule NonportableCheckpointAgent do
    use Jido.Agent, name: "nonportable_checkpoint_agent"

    @impl Jido.Agent
    def checkpoint(_agent, _context), do: {:ok, %{runtime: self()}}

    @impl Jido.Agent
    def restore(%{id: id}, _context), do: instantiate(id: id)
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

    definition =
      Agent.define!(%{name: "portable_state", schema: Zoi.object(%{payload: Zoi.any()})})

    for value <- values do
      assert {:ok, agent} =
               Agent.instantiate(definition,
                 id: Jido.Signal.ID.generate!(),
                 state: %{payload: value}
               )

      assert agent.state.payload === value
      assert {:ok, ^agent} = Agent.validate(agent)

      assert {:error, %Jido.Agent.Error{code: :non_portable_term, path: path}} =
               Jido.Persistence.snapshot(agent)

      assert Enum.take(path, 4) == [:snapshot, :agent, :state, :payload]
      assert length(path) <= 20
      assert {:ok, checkpoint} = Jido.Persistence.snapshot(%{agent | state: %{payload: nil}})

      assert {:error, %{code: :non_portable_term, path: ^path}} =
               Jido.Persistence.restore(%{
                 checkpoint
                 | agent: %{checkpoint.agent | state: %{payload: value}}
               })
    end

    deep_value = Enum.reduce(1..30, self(), fn index, value -> %{index => value} end)

    assert {:error, %Jido.Agent.Error{code: :non_portable_term, path: deep_path}} =
             checkpoint_value(definition, deep_value)

    assert length(deep_path) == 20
  end

  test "bounds every diagnostic path segment" do
    definition =
      Agent.define!(%{name: "portable_path", schema: Zoi.object(%{payload: Zoi.any()})})

    long_binary = String.duplicate("b", 100)
    long_integer = String.to_integer(String.duplicate("9", 100))
    long_atom = :aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

    for key <- [long_binary, long_atom] do
      assert {:error,
              %Jido.Agent.Error{
                code: :non_portable_term,
                path: [:snapshot, :agent, :state, :payload, segment]
              }} = checkpoint_value(definition, %{key => self()})

      assert is_binary(segment)
      assert byte_size(segment) == 64
    end

    assert {:error,
            %Jido.Agent.Error{
              code: :non_portable_term,
              path: [:snapshot, :agent, :state, :payload, {:map_value, 0}]
            }} = checkpoint_value(definition, %{long_integer => self()})

    assert {:error, [root_segment]} =
             Jido.PortableTerm.validate(self(), [String.duplicate("r", 100)])

    assert root_segment == String.duplicate("r", 64)
  end

  test "transition and command candidates permit schema-approved local values" do
    definition =
      Agent.define!(%{
        name: "local_transition",
        schema: Zoi.object(%{payload: Zoi.any()}),
        routes: [
          %{
            path: "local.run",
            handler: %{kind: :action, target: NonportableAction},
            state: %{source: :output, path: []}
          }
        ]
      })

    agent =
      Agent.instantiate!(definition, id: Jido.Signal.ID.generate!(), state: %{payload: :initial})

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
    definition = Agent.define!(%{name: "typed_local", schema: Zoi.object(%{payload: Zoi.pid()})})

    agent =
      Agent.instantiate!(definition, id: Jido.Signal.ID.generate!(), state: %{payload: self()})

    assert {:error, %{__exception__: true}} =
             Agent.instantiate(definition,
               id: Jido.Signal.ID.generate!(),
               state: %{payload: <<5::size(3)>>}
             )

    assert {:error, %{__exception__: true}} = Agent.transition(agent, %{payload: :invalid})
    assert {:error, %{__exception__: true}} = Agent.validate(%{agent | id: ""})
  end

  test "checkpoint output is portable and reports the invalid payload path" do
    agent = NonportableCheckpointAgent.instantiate!(id: "checkpoint")

    assert {:error,
            %Jido.Agent.Error{
              code: :non_portable_term,
              path: [:snapshot, :agent, :state, :runtime]
            }} = Jido.Persistence.snapshot(agent)
  end

  test "definition metadata rejects live data before snapshot creation" do
    assert {:error, %{code: :live_value, path: [:metadata | _]}} =
             Agent.define(%{name: "runtime_definition", metadata: %{runtime: fn -> :ok end}})
  end

  defp checkpoint_value(definition, value) do
    definition
    |> Agent.instantiate!(id: Jido.Signal.ID.generate!(), state: %{payload: value})
    |> Jido.Persistence.snapshot()
  end
end
