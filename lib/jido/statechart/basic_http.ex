defmodule Jido.Statechart.BasicHTTP do
  @moduledoc "Basic HTTP Event I/O for an Agent with an HTTP access URI."

  alias Jido.{AgentServer, Signal}
  alias Jido.Statechart.SCXML

  @type_uri "http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor"
  @form "application/x-www-form-urlencoded"
  @timeout 1_000

  @doc false
  @spec type() :: String.t()
  def type, do: @type_uri

  @doc "Submits an HTTP POST body to a chart's Agent. Form values can contain JSON."
  @spec receive_post(AgentServer.server(), binary(), String.t()) :: :ok | {:error, term()}
  def receive_post(server, body, content_type \\ @form) when is_binary(body) do
    {event, data} =
      case String.split(String.downcase(content_type), ";", parts: 2) do
        [@form | _] -> decode_form(body)
        _ -> {nil, %{body: body}}
      end

    with {:ok, signal} <- Signal.new(event || "POST", data, source: "/statechart/http"),
         {:ok, signal} <- Signal.put_context(signal, "scxmlhttpmethod", "POST"),
         {:ok, signal} <- put_event_name(signal, event) do
      AgentServer.cast(server, signal)
    end
  rescue
    ArgumentError -> {:error, :invalid_form}
  end

  defp put_event_name(signal, nil), do: {:ok, signal}
  defp put_event_name(signal, name), do: Signal.put_context(signal, "scxmlhttpname", name)

  defp decode_form(body) do
    params = Enum.to_list(URI.query_decoder(body))
    {_, name} = List.keyfind(params, "_scxmleventname", 0, {nil, nil})

    values =
      for {key, value} <- params, key != "_scxmleventname" do
        case JSON.decode(value) do
          {:ok, decoded} -> {key, decoded}
          {:error, _reason} -> {key, value}
        end
      end

    {name, SCXML.param_data(values) || %{}}
  end

  @doc false
  @spec post(String.t(), %{name: String.t() | nil, data: map() | binary()}) :: :ok | {:error, term()}
  def post(target, %{name: event, data: data}) do
    {type, body} = request_body(event, data)

    case Req.post(target,
           headers: [{"content-type", type}],
           body: body,
           finch: [
             conn_opts: [transport_opts: [timeout: @timeout]],
             pool_timeout: @timeout,
             receive_timeout: @timeout,
             request_timeout: @timeout
           ],
           redirect: false,
           retry: false,
           raw: true
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, _reason} = error -> error
    end
  end

  defp request_body(_event, data) when is_binary(data), do: {"text/plain", data}

  defp request_body(event, data) do
    params =
      Enum.map(data, fn
        {"_scxmleventname", value} when is_binary(value) -> {"_scxmleventname", value}
        {key, value} -> {key, form_value(value)}
      end)

    params = if event, do: [{"_scxmleventname", event} | params], else: params
    {@form, URI.encode_query(params)}
  end

  defp form_value(value) when is_binary(value) do
    case JSON.decode(value) do
      {:ok, _decoded} -> JSON.encode!(value)
      {:error, _reason} -> value
    end
  end

  defp form_value(value), do: JSON.encode!(value)
end
