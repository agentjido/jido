defmodule JidoTest.RemoteAPIFixtures do
  @moduledoc false
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.RemoteCounter

  def record(:call, server, value, timeout) do
    RemoteCounter.record(server, value, timeout: timeout)
  catch
    :exit, {:timeout, _call} -> :timeout
  end

  def record(:request, server, value, timeout) do
    signal = RemoteCounter.record_signal!(value)
    request = Server.send_request(server, signal, timeout)
    Server.receive_response(request, timeout)
  end
end
