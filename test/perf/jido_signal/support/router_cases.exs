defmodule Jido.Test.Perf.Signal.RouterCases do
  @moduledoc false
  alias Jido.Signal.Router
  alias Jido.Test.Perf.Signal.Helpers
  import Helpers, only: [plain: 5, expect!: 2]

  def workloads(size) do
    count = size * 16
    # Distinct wildcard paths grow both the index and the result set. Each
    # path matches the same deep Signal; no generated path is a duplicate.
    depth = min(size, 16)
    segments = for index <- 1..depth, do: "s#{index}"
    [event] = Helpers.events(1)
    deep_event = %{event | type: Enum.join(["bench" | segments] ++ ["created"], ".")}
    specs = wildcard_specs(count)
    router = Router.new!(specs)

    matching = %{
      event
      | type: Enum.join(["bench" | for(index <- 1..9, do: "n#{index}")] ++ ["created"], ".")
    }

    dimensions = %{wildcard_routes: count}
    # Membership is independent of the route sorter. The original cases
    # check exact precedence, specificity, priority, and registration order.
    expected = Enum.to_list(1..count)
    deep_specs = for index <- 1..count, do: {"branch#{index}.**.created", index}
    deep_specs = deep_specs ++ [{"bench.**.created", :deep}, {"bench.*.created", :shallow}]
    deep = Router.new!(deep_specs)
    extra = {matching.type, :added}
    {:ok, added} = Router.add(router, extra)
    other = Router.new!([extra])

    [
      plain(
        "router/wildcard_build",
        specs,
        fn _ -> Router.new(specs) end,
        fn {:ok, built} ->
          expect!(Router.count(built), count)
          targets!(Router.route(built, matching), expected)
        end,
        dimensions
      ),
      plain(
        "router/wildcard_many",
        router,
        fn _ -> Router.route(router, matching) end,
        &targets!(&1, expected),
        dimensions
      ),
      plain(
        "router/deep",
        deep,
        fn _ -> Router.route(deep, deep_event) end,
        &expect!(&1, {:ok, [:deep]}),
        %{routes: count + 2, depth: depth + 2}
      ),
      plain(
        "router/add",
        router,
        fn _ -> Router.add(router, extra) end,
        fn {:ok, result} ->
          {:ok, [:added | targets]} = Router.route(result, matching)
          expect!(Enum.sort(targets), expected)
        end,
        dimensions
      ),
      plain(
        "router/remove",
        added,
        fn _ -> Router.remove(added, elem(extra, 0)) end,
        fn {:ok, result} ->
          expect!(Router.count(result), count)
          targets!(Router.route(result, matching), expected)
        end,
        dimensions
      ),
      plain(
        "router/merge",
        {router, other},
        fn _ -> Router.merge(router, other) end,
        fn {:ok, result} ->
          expect!(Router.count(result), count + 1)
          {:ok, [:added | targets]} = Router.route(result, matching)
          expect!(Enum.sort(targets), expected)
        end,
        dimensions
      )
    ]
  end

  def wildcard_specs(count) do
    for index <- 1..count do
      segments =
        for bit <- 0..8 do
          if Bitwise.band(index - 1, Bitwise.bsl(1, bit)) == 0, do: "*", else: "n#{bit + 1}"
        end

      {Enum.join(["bench" | segments] ++ ["*"], "."), index}
    end
  end

  defp targets!({:ok, targets}, expected), do: expect!(Enum.sort(targets), expected)
end
