defmodule Jido.Signal.Router.RoutingEquivalenceTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Router

  describe "pattern matching equivalence" do
    # Comprehensive test cases covering all wildcard combinations
    @test_cases [
      # Exact matches
      {"user.created", "user.created", true},
      {"user.updated", "user.created", false},

      # Single wildcard
      {"user.123", "user.*", true},
      {"user.123.updated", "user.*", false},
      {"user.123", "*.123", true},

      # Multi-level wildcard (zero segments)
      {"user.created", "user.**.created", true},
      {"user.created", "**.created", true},

      # Multi-level wildcard (multiple segments)
      {"order.123.payment.completed", "order.**", true},
      {"order.123.payment.completed", "order.**.completed", true},
      {"order.123.payment.completed", "**.completed", true},

      # Combined wildcards
      {"user.123.created", "user.*.created", true},
      {"order.456.payment.completed", "*.*.payment.*", true},
      {"a.b.c.d.e", "a.**.e", true},
      {"a.e", "a.**.e", true},

      # Edge cases
      {"a", "**", true},
      {"a.b.c", "**", true},

      # No match
      {"user.deleted", "user.created", false},
      {"order.payment", "order.**.completed", false}
    ]

    for {type, pattern, expected} <- @test_cases do
      test "matches?(#{inspect(type)}, #{inspect(pattern)}) == #{expected}" do
        assert Router.matches?(unquote(type), unquote(pattern)) == unquote(expected)
      end
    end

    # Long path test (no stack overflow)
    test "handles deep paths without stack overflow" do
      long_type = Enum.join(1..100, ".")

      assert Router.matches?(long_type, "**")
      assert Router.matches?(long_type, "1.**.100")
      refute Router.matches?(long_type, "1.**.999")
    end

    # Invalid patterns return false
    test "rejects invalid patterns gracefully" do
      refute Router.matches?("user.created", "user..created")
      refute Router.matches?("user.created", "")
      refute Router.matches?(nil, "user.*")
      refute Router.matches?("user.created", nil)
    end

    test "matches patterns with multiple ** segments" do
      assert Router.matches?("a.b.c.d.e.f", "a.**.c.**.f")
      assert Router.matches?("a.c.f", "a.**.c.**.f")
      refute Router.matches?("a.b.c.d.e", "a.**.c.**.f")
    end

    test "matches patterns with adjacent wildcards" do
      assert Router.matches?("user.123.created", "user.*.*")
      assert Router.matches?("a.b.c.d", "a.**.d")
      assert Router.matches?("a.d", "a.**.d")
    end

    test "handles trailing ** correctly" do
      assert Router.matches?("audit", "audit.**")
      assert Router.matches?("audit.user", "audit.**")
      assert Router.matches?("audit.user.created", "audit.**")
      refute Router.matches?("user.audit", "audit.**")
    end

    test "handles leading ** correctly" do
      assert Router.matches?("created", "**.created")
      assert Router.matches?("user.created", "**.created")
      assert Router.matches?("audit.user.created", "**.created")
      refute Router.matches?("created.user", "**.created")
    end

    test "handles middle ** correctly" do
      assert Router.matches?("user.created", "user.**.created")
      assert Router.matches?("user.profile.created", "user.**.created")
      assert Router.matches?("user.profile.address.created", "user.**.created")
      refute Router.matches?("user.updated", "user.**.created")
    end

    test "trie routing agrees with matches?/2" do
      patterns = [
        "user.created",
        "user.*",
        "user.*.created",
        "user.**",
        "user.**.created",
        "**.created",
        "a.**.c.**.f",
        "**"
      ]

      types = [
        "user",
        "user.created",
        "user.profile.created",
        "user.profile.address.updated",
        "a.c.f",
        "a.b.c.d.e.f",
        "system.completed"
      ]

      Enum.each(patterns, fn pattern ->
        router = Router.new!({pattern, :matched})

        Enum.each(types, fn type ->
          signal = %Jido.Signal{id: "equivalence", source: "/test", type: type}

          assert match_result(Router.route(router, signal)) == Router.matches?(type, pattern),
                 "route mismatch for type #{inspect(type)} and pattern #{inspect(pattern)}"
        end)
      end)
    end

    test "routes deep paths through repeated multi-wildcards" do
      middle = Enum.join(1..98, ".")
      deep = %Jido.Signal{id: "deep", source: "/test", type: "start.#{middle}.end"}
      assert {:ok, [:deep]} = Router.route(Router.new!({"start.**.end", :deep}), deep)

      repeated = %Jido.Signal{id: "repeated", source: "/test", type: "a.b.c.m.x.y.z"}

      router =
        Router.new!([
          {"a.**.z", :outer, 0},
          {"**.m.**.z", :middle, 50}
        ])

      assert {:ok, [:middle, :outer]} = Router.route(router, repeated)
    end
  end

  defp match_result({:ok, [:matched]}), do: true
  defp match_result({:error, %Jido.Signal.Error.RoutingError{}}), do: false
end
