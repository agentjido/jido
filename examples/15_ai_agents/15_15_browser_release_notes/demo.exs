Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("release_notes.ex", __DIR__)
Code.require_file("support/offline_browser.ex", __DIR__)
Code.require_file("support/scripted_client.ex", __DIR__)

alias Jido.Examples.AI.BrowserReleaseNotes
alias Jido.Examples.AI.BrowserReleaseNotes.{OfflineBrowser, ScriptedClient}

Application.put_env(:jido, :browser, OfflineBrowser.host_config())

Enum.each(OfflineBrowser.pages(), fn {label, url} ->
  case BrowserReleaseNotes.read(url, ScriptedClient) do
    {:ok, %{status: :completed, output: output}} -> IO.puts("#{label} — #{output}")
    error -> raise "Release note demo failed: #{inspect(error)}"
  end
end)
