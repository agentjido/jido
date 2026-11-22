defmodule Jido.Examples.AI.BrowserReleaseNotes.OfflineBrowser do
  @moduledoc false

  @behaviour Jido.AI.Browser

  def pages do
    [
      {"Public release note", "https://docs.example/jido/releases/v3.html"},
      {"Internal preview", "https://docs.example/jido/preview/v3.html"}
    ]
  end

  def host_config do
    [
      allow: [%{"host" => "docs.example", "path_prefix" => "/jido/releases/"}],
      page_transport: __MODULE__
    ]
  end

  # This address models a public DNS answer. The fixture opens no socket.
  @fixture_address {93, 184, 216, 34}

  @impl true
  def resolve("docs.example"), do: {:ok, @fixture_address}
  def resolve(_host), do: {:error, :fixture_not_found}

  @impl true
  def get(%URI{host: "docs.example", path: "/jido/releases/v3.html"}, @fixture_address, _headers, _deadline, _max_bytes) do
    {:ok,
     %{
       status: 200,
       headers: [{"content-type", "text/html"}],
       body: "<main><p>Jido v3 can run a child Flow inside Iterate.</p></main>"
     }}
  end

  def get(_uri, _address, _headers, _deadline, _max_bytes), do: {:error, :fixture_not_found}
end
