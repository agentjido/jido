defmodule Jido.Signal.Router.InspectTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Router

  defmodule Target do
    defstruct [:id]
  end

  test "shows a concise route summary for each target shape" do
    matcher = fn _signal -> true end

    router =
      Router.new!([
        {"one", {:pid, [target: self()]}, 5},
        {"two", matcher, [:a, :b]},
        {"three", %Target{id: 1}},
        {"four", :atom},
        {"five", 42}
      ])

    text = inspect(router)

    assert text =~ "#Router<routes: 5>"
    assert text =~ "one (priority: 5) → {:pid,"
    assert text =~ "two [with matcher] → [2 items]"
    assert text =~ "three → %Jido.Signal.Router.InspectTest.Target{}"
    assert text =~ "four → :atom"
    assert text =~ "five → 42"
  end

  test "supports verbose protocol inspection" do
    router = Router.new!()

    assert inspect(router) == "#Router<routes: 0>\n"
    assert inspect(router, custom_options: [verbose: true]) =~ "entries: []"
  end

  test "preserves improper list targets in lookup and inspection" do
    target = [:head | :tail]

    for path <- ["term.target", "term.*", "term.**"] do
      router = Router.new!([{path, target}, {path, [:a, :b]}])
      signal = Jido.Signal.new!("term.target", %{}, source: "/test")

      assert {:ok, [^target, :a, :b]} = Router.route(router, signal)
      assert inspect(router) =~ "→ [:head | :tail]"
      assert inspect(router) =~ "→ [2 items]"
    end
  end
end
