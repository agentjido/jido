Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("release_notes.ex", __DIR__)
Code.require_file("support/offline_browser.ex", __DIR__)
Code.require_file("support/scripted_client.ex", __DIR__)

defmodule Jido.Examples.AI.BrowserReleaseNotesTest do
  use ExUnit.Case, async: false

  alias Jido.Examples.AI.BrowserReleaseNotes
  alias Jido.Examples.AI.BrowserReleaseNotes.{OfflineBrowser, ScriptedClient}

  @moduletag :integration

  defmodule TransportProbe do
    @behaviour Jido.AI.Browser

    @impl true
    def resolve(host) do
      send(__MODULE__, {:resolve_host, host})
      OfflineBrowser.resolve(host)
    end

    @impl true
    def get(uri, address, headers, deadline, max_bytes) do
      send(__MODULE__, {:page_transport, URI.to_string(uri)})
      OfflineBrowser.get(uri, address, headers, deadline, max_bytes)
    end
  end

  setup do
    previous = Application.fetch_env(:jido, :browser)
    Process.register(self(), TransportProbe)
    Application.put_env(:jido, :browser, Keyword.put(OfflineBrowser.host_config(), :page_transport, TransportProbe))

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:jido, :browser, value)
        :error -> Application.delete_env(:jido, :browser)
      end
    end)

    :ok
  end

  test "reads the allowed page through the tool and cites the source" do
    [{_, url}, _] = OfflineBrowser.pages()
    assert {:ok, %{status: :completed, output: output}} = BrowserReleaseNotes.read(url, ScriptedClient)
    assert output == "Jido v3 can run a child Flow inside Iterate. Source: #{url}"
    assert_received {:resolve_host, "docs.example"}
    assert_received {:page_transport, ^url}
    refute_received {:page_transport, _}
  end

  test "the host rejects a preview within the Agent scope before the page transport runs" do
    [_, {_, url}] = OfflineBrowser.pages()

    assert {:ok, %{status: :completed, output: "The browser tool could not read this page."}} =
             BrowserReleaseNotes.read(url, ScriptedClient)

    refute_received {:resolve_host, _}
    refute_received {:page_transport, _}
  end
end
