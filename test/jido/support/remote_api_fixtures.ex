defmodule JidoTest.RemoteAPIFixtures do
  @moduledoc false
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.RemoteCounter

  def record(:call, server, value, timeout) do
    {:ok, route_signal_1} = RemoteCounter.record_signal(%{value: value})
    Jido.AgentServer.call(server, route_signal_1, timeout: timeout)
  catch
    :exit, {:timeout, _call} -> :timeout
  end

  def record(:request, server, value, timeout) do
    {:ok, signal} = RemoteCounter.record_signal(%{value: value})
    request = Server.send_request(server, signal, timeout)
    Server.receive_response(request, timeout)
  end
end
