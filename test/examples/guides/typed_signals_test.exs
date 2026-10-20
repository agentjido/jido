# Run the notebook examples against the current Jido package.
filename = Path.expand("../../../guides/typed-signal-actions.livemd", __DIR__)

ExUnit.CaptureLog.capture_log(fn ->
  ~r/```elixir\n(.*?)\n```/s
  |> Regex.scan(File.read!(filename), capture: :all_but_first)
  |> Enum.map(&hd/1)
  |> Enum.reject(&String.contains?(&1, "Mix.install("))
  |> Enum.reduce({[], Code.env_for_eval(file: filename)}, fn code, {bindings, env} ->
    ast = Code.string_to_quoted!(code, file: filename)
    {_result, bindings, env} = Code.eval_quoted_with_env(ast, bindings, env)
    {bindings, env}
  end)
end)

defmodule Jido.Examples.TypedSignalsTest do
  use ExUnit.Case, async: false
  @moduletag :example
  @moduletag capture_log: true

  test "SignalAction builds and validates the routed Signal" do
    assert {:ok, signal} = Typed.AddItem.new(%{sku: "tea"})
    assert signal.type == "cart.item.add"
    assert signal.source == "/guides/typed"
    assert signal.data == %{quantity: 1, sku: "tea"}

    assert {:error, issues} = Typed.AddItem.new(%{sku: 1})
    assert Enum.any?(issues, &(&1.message == "invalid type: expected string"))
  end

  test "module route uses the SignalAction type and defaults" do
    agent = Typed.Cart.instantiate!(id: "typed-guide-cart")
    signal = Typed.Cart.add_item_signal!(%{sku: "tea", quantity: 2})

    assert signal.type == Typed.AddItem.type()
    assert {:ok, candidate, []} = Typed.Cart.cmd(agent, signal)
    assert candidate.state.items == %{"tea" => 2}
  end

  test "typed reply gets a new identity and the request causation" do
    request = Typed.PriceQuote.new!(%{items: %{"tea" => 3}})

    assert {:ok, result} = Jido.Exec.run(Typed.PriceQuote, request.data)
    assert {:ok, reply} = Typed.PriceQuote.reply(request, result)
    assert reply.type == "cart.quote.ready"
    assert reply.data == %{total_cents: 1_350}
    assert reply.id != request.id
    assert reply.extensions["jidocausationid"] == request.id
  end

  test "via route returns the owned Directive after pure evaluation" do
    agent =
      Typed.QuotingCart.instantiate!(
        id: "typed-guide-quoting-cart",
        state: %{items: %{"tea" => 3}}
      )

    request = Typed.PriceQuote.new!(%{items: agent.state.items})

    assert {:ok, accepted, [%Typed.RequestQuote{request: ^request}]} =
             Typed.QuotingCart.cmd(agent, request)

    assert accepted.state.quotes == 1
  end
end
