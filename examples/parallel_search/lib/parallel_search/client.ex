defmodule ParallelSearch.Client do
  @moduledoc "Anonymous Streamable HTTP connection for the Parallel Search example."

  @url "https://search.parallel.ai/mcp"
  @user_agent "jido-parallel-search-example/0.1.0"

  @doc "Returns the endpoint and transport options; no credentials are loaded."
  @spec options() :: keyword()
  def options do
    [
      transport: :http,
      url: @url,
      headers: [{"user-agent", @user_agent}],
      protocol_mode: :legacy_only,
      protocol_version: "2025-03-26",
      handshake_timeout: 30_000,
      health_check_interval: 0,
      reconnect: false
    ]
  end

  @doc "Starts a connection. The caller owns it and must stop it after use."
  @spec start_link() :: GenServer.on_start()
  def start_link, do: ExMCP.Client.start_link(options())
end
