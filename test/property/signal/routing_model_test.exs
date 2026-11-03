Code.require_file("support/fuzz.exs", __DIR__)
Code.require_file("support/model.exs", __DIR__)

defmodule JidoTest.Property.Signal.RoutingModelTest do
  use ExUnit.Case, async: false
  import StreamData
  alias Jido.Signal
  alias Jido.Signal.Router
  alias Jido.Signal.Bus.Store.Memory
  alias JidoTest.Property.Signal.{Fuzz, Model}

  @paths ~w(a b a.b a.* *.a ** a.** **.a **.a.** **.a.**.b **.*.a)
  @modes ~w(scalar group nested empty opaque)
  @predicates ~w(true false other raise throw exit)
  @compiled JidoTest.Property.Signal.CompiledRouter

  def predicate(_signal, "true"), do: true
  def predicate(_signal, "false"), do: false
  def predicate(_signal, "other"), do: :truthy
  def predicate(_signal, "raise"), do: raise("predicate")
  def predicate(_signal, "throw"), do: throw(:predicate)
  def predicate(_signal, "exit"), do: exit(:predicate)

  for {suite, runs, bound} <- [{:property, 40, 6}, {:fuzz, 500, 16}] do
    @tag [
      {suite, true},
      max_runs: runs,
      max_run_time: if(suite == :fuzz, do: 300_000, else: 10_000),
      timeout: if(suite == :fuzz, do: 900_000, else: 90_000)
    ]
    @tag contracts: ["ROUTE-001", "ROUTE-002", "ROUTE-003"]
    @tag contract_cases: [
           "ROUTE-001/globstar-star-types",
           "ROUTE-002/order-predicates-targets",
           "ROUTE-003/immutable-mutations",
           "ROUTE-003/compiled-static",
           "ROUTE-003/invalid-paths"
         ]
    test "#{suite}: routing matches an independent list model", context do
      route =
        fixed_map(%{
          "path" => member_of(@paths),
          "priority" => integer(-100..100),
          "mode" => member_of(@modes),
          "predicate" => member_of(@predicates)
        })

      generator =
        fixed_map(%{
          "type" =>
            map(
              list_of(member_of(~w(a b * **)), min_length: 1, max_length: 5),
              &Enum.join(&1, ".")
            ),
          "routes" => list_of(route, max_length: unquote(bound))
        })

      examples =
        for mode <- @modes,
            predicate <- @predicates,
            do: %{
              "type" => "**.x.a",
              "routes" => [
                spec("**.a", mode, predicate),
                spec("**", "group", "true"),
                spec("**.a", "scalar", "true")
              ]
            }

      Fuzz.check(
        "routing_model",
        generator,
        Map.to_list(context) ++ [examples: examples],
        &check/1
      )
    end
  end

  defp spec(path, mode, predicate),
    do: %{"path" => path, "mode" => mode, "predicate" => predicate, "priority" => 0}

  defp target("scalar", i), do: {:target, i}
  defp target("group", i), do: [{:target, i}, {:target, i}]
  defp target("nested", i), do: [[i, i], {:target, i}]
  defp target("empty", _), do: []
  defp target("opaque", i), do: [i | :opaque]
  defp targets("last", _), do: [:last]
  defp targets("empty", _), do: []
  defp targets(mode, i) when mode in ["group", "nested"], do: target(mode, i)
  defp targets(mode, i), do: [target(mode, i)]

  defp check(%{"type" => type, "routes" => routes}) do
    signal = Signal.new!(type, %{}, source: "/property")

    specs =
      for {r, i} <- Enum.with_index(routes),
          do: {r["path"], {__MODULE__, :predicate, [r["predicate"]]}, target(r["mode"], i), r["priority"]}

    assert {:ok, router} = Router.new(specs)

    indexed = Enum.with_index(routes)
    expected = expected(indexed, type)

    assert_route(router, signal, expected)

    for path <- @paths do
      wanted = Model.matches?(type, path)
      assert Router.matches?(type, path) == wanted
      assert Router.filter([signal], path) == if(wanted, do: [signal], else: [])
      assert {:ok, state} = Memory.init([])
      record = Model.record(1, type)
      assert {:ok, state} = Memory.append([record], state)
      assert {:ok, found} = Memory.read([path: path], state)
      assert found == if(wanted, do: [record], else: [])
    end

    declarations =
      for {path, match, target, priority} <- specs,
          do:
            quote(
              do:
                route(
                  unquote(path),
                  unquote(Macro.escape(match)),
                  unquote(Macro.escape(target)),
                  unquote(priority)
                )
            )

    try do
      quoted =
        quote do
          use Jido.Signal.Router
          unquote_splicing(declarations)
        end

      assert {:module, @compiled, _, _} =
               Module.create(@compiled, quoted, Macro.Env.location(__ENV__))

      assert apply(@compiled, :routes, []) == elem(Router.list(router), 1)
      assert_route(apply(@compiled, :router, []), signal, expected)
    after
      :code.delete(@compiled)
      :code.purge(@compiled)
      refute :code.is_loaded(@compiled)
      refute :erlang.check_old_code(@compiled)
    end

    extra = {"**", :last, -100}
    extra_model = Map.put(spec("**", "last", "true"), "priority", -100)
    combined = indexed ++ [{extra_model, length(routes)}]
    added_expected = expected(combined, type)
    assert {:ok, added} = Router.add(router, extra)
    assert_route(router, signal, expected)
    assert Router.count(added) == length(routes) + 1
    assert_route(added, signal, added_expected)
    assert {:ok, merged} = Router.merge(router, Router.new!([extra]))
    assert_route(merged, signal, added_expected)
    assert {:ok, removed} = Router.remove(added, "**")
    remaining = Enum.reject(combined, fn {r, _i} -> r["path"] == "**" end)
    assert_route(removed, signal, expected(remaining, type))
    assert_route(added, signal, added_expected)
    assert {:ok, ^removed} = Router.remove(removed, "**")

    for invalid <- ["", "a..b", "a\n", "**.**", "a*", "é"] do
      assert {:error, _} = Router.new([{invalid, :invalid}])
      refute Router.matches?(type, invalid)
    end

    assert {:error, _} = Router.new([{"a", :x} | :tail])
    ["route-count-#{length(routes)}", "star-type-#{String.contains?(type, "*")}"]
  end

  defp expected(indexed, type) do
    indexed
    |> Enum.filter(fn {r, _} -> Model.matches?(type, r["path"]) and r["predicate"] == "true" end)
    |> Enum.sort_by(fn {r, i} -> {rank(r["path"]), r["priority"], -i} end, :desc)
    |> Enum.flat_map(fn {r, i} -> targets(r["mode"], i) end)
  end

  # The documented score expressed as a list sum, separate from trie traversal.
  defp rank(path) do
    segments = String.split(path, ".")
    n = length(segments)

    class =
      cond do
        "**" in segments -> 0
        "*" in segments -> 1
        true -> 2
      end

    adjustments =
      Enum.map(Enum.with_index(segments), fn {segment, i} ->
        case segment do
          "*" -> -1000 + i * 100
          "**" -> -2000 + i * 200
          _ -> 3000 * (n - i)
        end
      end)

    score = n * 2000 + Enum.sum(adjustments)

    {class, score}
  end

  defp assert_route(router, signal, []),
    do: assert(match?({:error, _}, Router.route(router, signal)))

  defp assert_route(router, signal, targets),
    do: assert(Router.route(router, signal) == {:ok, targets})
end
