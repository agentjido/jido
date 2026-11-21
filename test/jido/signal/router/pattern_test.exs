defmodule Jido.Signal.Router.PatternTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Router

  describe "matches?/2" do
    test "rejects newline characters at segment boundaries" do
      for pattern <- ["event\n", "a\n.b", "a.b\n"] do
        assert {:error, _} = Router.normalize({pattern, :target})
        refute Router.matches?(pattern, pattern)
        assert Router.filter([%Signal{type: pattern, id: "test", source: "/test"}], pattern) == []
      end
    end

    test "treats multi-wildcards as patterns when type segments contain stars" do
      for {type, pattern} <- [
            {"**.x.a", "**.a"},
            {"a.**.x", "a.**"},
            {"**.x", "**"}
          ] do
        signal = Signal.new!(type: type, source: "/test")
        router = Router.new!({pattern, :matched})

        assert {:ok, [:matched]} = Router.route(router, signal)
        assert Router.matches?(type, pattern)
        assert Router.filter([signal], pattern) == [signal]
      end
    end

    test "matches exact paths" do
      assert Router.matches?("user.created", "user.created")
      refute Router.matches?("user.updated", "user.created")
    end

    test "matches single wildcards" do
      assert Router.matches?("user.created", "user.*")
      assert Router.matches?("user.updated", "user.*")
      refute Router.matches?("payment.processed", "user.*")
      refute Router.matches?("user.profile.updated", "user.*")
    end

    test "matches multi-level wildcards" do
      assert Router.matches?("audit.user.created", "audit.**")
      assert Router.matches?("audit.payment.processed.success", "audit.**")
      assert Router.matches?("audit", "audit.**")
      refute Router.matches?("user.audit.created", "audit.**")
    end

    test "matches complex patterns" do
      assert Router.matches?("user.profile.updated", "user.*.updated")
      assert Router.matches?("system.audit.user.created", "system.audit.**")
      refute Router.matches?("user.profile.created", "user.*.updated")
    end

    test "handles invalid inputs" do
      refute Router.matches?(nil, "user.*")
      refute Router.matches?("user.created", nil)
      refute Router.matches?(123, "user.*")
      refute Router.matches?("user.created", 123)
    end
  end

  describe "filter/2" do
    setup do
      signals = [
        %Signal{type: "user.created", data: %{id: 1}, source: "test", id: "1"},
        %Signal{type: "user.updated", data: %{id: 1}, source: "test", id: "2"},
        %Signal{type: "payment.processed", data: %{amount: 100}, source: "test", id: "3"},
        %Signal{type: "audit.user.created", data: %{user_id: 1}, source: "test", id: "4"},
        %Signal{type: "audit.payment.processed", data: %{payment_id: 1}, source: "test", id: "5"}
      ]

      {:ok, signals: signals}
    end

    test "filters by exact match", %{signals: signals} do
      filtered = Router.filter(signals, "user.created")
      assert length(filtered) == 1
      assert hd(filtered).type == "user.created"
    end

    test "filters by single wildcard", %{signals: signals} do
      filtered = Router.filter(signals, "user.*")
      assert length(filtered) == 2
      assert Enum.all?(filtered, &String.starts_with?(&1.type, "user."))
    end

    test "filters by multi-level wildcard", %{signals: signals} do
      filtered = Router.filter(signals, "audit.**")
      assert length(filtered) == 2
      assert Enum.all?(filtered, &String.starts_with?(&1.type, "audit."))
    end

    test "returns empty list for non-matching pattern", %{signals: signals} do
      assert Router.filter(signals, "profile.**") == []
    end

    test "handles invalid inputs" do
      assert Router.filter(nil, "user.*") == []
      assert Router.filter([], nil) == []
      assert Router.filter("not a list", "user.*") == []
    end

    test "handles signals with nil types", %{signals: signals} do
      signals = [%Signal{type: nil, source: "test", id: "6"} | signals]
      filtered = Router.filter(signals, "user.*")
      assert length(filtered) == 2
      assert Enum.all?(filtered, &String.starts_with?(&1.type, "user."))
    end
  end
end
