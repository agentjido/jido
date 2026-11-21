Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("chat_application.ex", __DIR__)
Code.require_file("chat_live.ex", __DIR__)

ExUnit.start()

defmodule Jido.Examples.Patterns.LiveChat.PlaygroundCheck do
  use ExUnit.Case, async: false
  use PhoenixPlayground.Test, live: Jido.Examples.Patterns.LiveChat.Live

  import Phoenix.LiveViewTest

  alias Jido.Examples.Patterns.LiveChat.Live

  setup_all do
    Enum.each(Live.child_specs(), &start_supervised!/1)
    :ok
  end

  test "normal exchange, ordered stream, reconnect, and model failure" do
    {:ok, view, _html} = live(build_conn(), "/?conversation_id=live-check")

    view
    |> element("#chat-form")
    |> render_submit(%{"message" => %{"text" => "Hello LiveView"}})

    html = await_html(view, ~s(id="operation-state" class="state state-committed"))
    assert html =~ "Offline reply: Hello LiveView"
    assert ordered_sequences?(html)

    {:ok, _replacement_view, reconnect_html} =
      live(build_conn(), "/?conversation_id=live-check")

    assert reconnect_html =~ "Hello LiveView"
    assert reconnect_html =~ "Offline reply: Hello LiveView"

    {:ok, failed_view, _html} = live(build_conn(), "/?conversation_id=live-check-failure")

    failed_view
    |> element("#chat-form")
    |> render_submit(%{"message" => %{"text" => "Fail", "fail" => "true"}})

    failed_html = await_html(failed_view, ~s(id="operation-state" class="state state-failed"))
    assert failed_html =~ "jido.ai.model.stream.failed"
    refute failed_html =~ "message-assistant"
  end

  defp await_html(view, expected) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    do_await_html(view, expected, deadline)
  end

  defp do_await_html(view, expected, deadline) do
    html = render(view)

    cond do
      html =~ expected ->
        html

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("timed out while waiting for #{inspect(expected)}")

      true ->
        receive do
        after
          10 -> do_await_html(view, expected, deadline)
        end
    end
  end

  defp ordered_sequences?(html) do
    positions =
      0..4
      |> Enum.map(fn sequence ->
        case :binary.match(html, ~s(data-sequence="#{sequence}")) do
          {position, _length} -> position
          :nomatch -> -1
        end
      end)

    positions == Enum.sort(positions) and Enum.all?(positions, &(&1 >= 0))
  end
end
