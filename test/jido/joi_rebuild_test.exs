defmodule Jido.JoiRebuildTest do
  use Jido.Test.AgentServer.PeerCase, async: false

  @fixture Jido.Test.JoiRebuildFixture
  @action Jido.Test.JoiRebuildAction
  @source_file "joi_rebuild_fixture.ex"

  test "independent builds retain schema order, code identity, and checkpoints", c do
    compile_pair(c, :same)

    assert peer_call(c.peer_a, @fixture, :schemas, []) ==
             peer_call(c.peer_b, @fixture, :schemas, [])

    assert peer_call(c.peer_a, @action, :module_info, [:md5]) ==
             peer_call(c.peer_b, @action, :module_info, [:md5])

    assert {:ok, snapshot} = peer_call(c.peer_a, @fixture, :snapshot, [])
    assert {:ok, restored} = peer_call(c.peer_b, Jido.Persistence, :restore, [snapshot])
    assert restored.id == "joi-rebuild-agent"
    assert restored.state == %{count: 42}
  end

  test "a real executable body change still rejects a saved checkpoint", c do
    compile_pair(c, :changed)

    assert {:ok, snapshot} = peer_call(c.peer_a, @fixture, :snapshot, [])

    assert {:error, %Jido.Error.ValidationError{code: :changed_reference}} =
             peer_call(c.peer_b, Jido.Persistence, :restore, [snapshot])
  end

  defp compile_pair(c, mode) do
    # Atom table order differs between independent compilations in production.
    # More than 32 fields also exercises map hash order, not only flat maps.
    names = Enum.map(1..48, &"joi_rebuild_field_#{&1}")
    intern(c.peer_a, names)
    intern(c.peer_b, Enum.reverse(names))

    source_a = source("{:ok, params}")

    source_b =
      source(if(mode == :changed, do: "{:ok, Map.put(params, :changed, true)}", else: "{:ok, params}"))

    peer_call(c.peer_a, Code, :compile_string, [source_a, @source_file], 30_000)
    peer_call(c.peer_b, Code, :compile_string, [source_b, @source_file], 30_000)
  end

  defp intern(peer, names) do
    # Evaluate on the peer so control-channel argument decoding does not intern
    # the fixture's atom keys before their intended order is established.
    peer_call(peer, Code, :eval_string, ["Enum.each(names, &String.to_atom/1)", [names: names]])
  end

  defp source(body) do
    """
    defmodule Jido.Test.JoiRebuildStruct do
      @keys Enum.map(1..48, &String.to_atom("joi_rebuild_field_\#{&1}"))
      defstruct @keys
    end

    defmodule Jido.Test.JoiRebuildFixture do
      alias Jido.Joi
      @fields Map.new(1..48, fn n ->
        {String.to_atom("joi_rebuild_field_\#{n}"), Joi.integer() |> Joi.default(0)}
      end)
      @schemas %{
        object: Joi.object(@fields),
        map: Joi.map(@fields),
        struct: Joi.struct(Jido.Test.JoiRebuildStruct, @fields),
        nested: Joi.object(%{payload: Joi.object(@fields)})
      }
      def schemas, do: @schemas

      def snapshot do
        Jido.Test.JoiRebuildAgent.instantiate!(
          id: "joi-rebuild-agent", state: %{count: 42}
        )
        |> Jido.Persistence.snapshot()
      end
    end

    defmodule Jido.Test.JoiRebuildAction do
      alias Jido.Joi
      @fields Map.new(1..48, fn n ->
        {String.to_atom("joi_rebuild_field_\#{n}"), Joi.integer() |> Joi.default(0)}
      end)
      use Jido.Action,
        name: "joi_rebuild_action",
        schema: Joi.object(%{payload: Joi.object(@fields)})
      def run(params, _context), do: #{body}
    end

    defmodule Jido.Test.JoiRebuildAgent do
      use Jido.Agent, name: "joi_rebuild_agent"
      state do
        schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
      end
      routes do
        route "rebuild.test", Jido.Test.JoiRebuildAction
      end
    end
    """
  end
end
