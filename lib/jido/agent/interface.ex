defmodule Jido.Agent.Interface do
  @moduledoc false

  alias Jido.Agent.Authoring

  @signal_keys [:source, :id, :subject, :time, :datacontenttype, :dataschema, :extensions]

  def signal(config, arguments) do
    with {:ok, data, opts} <- package(config, arguments, [:input, :signal]),
         {:ok, signal} <- build_signal(config, data, opts) do
      {:ok, signal}
    end
  end

  def signal!(config, arguments) do
    case signal(config, arguments) do
      {:ok, signal} -> signal
      {:error, error} -> raise error
    end
  end

  def call(config, server, arguments) do
    with {:ok, data, opts} <- package(config, arguments, [:input, :signal, :context, :timeout]),
         {:ok, signal} <- build_signal(config, data, opts) do
      Jido.AgentServer.call(server, signal, Keyword.take(opts, [:context, :timeout]))
    end
  end

  defp package(config, arguments, allowed) do
    {values, opts} = split_options(arguments, config.required)

    with true <- length(values) in config.required..length(config.fields),
         {:ok, options} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(options, allowed),
         {:ok, input} <- input(Map.get(options, :input, %{})),
         positional = Map.new(Enum.zip(config.fields, values)),
         :ok <- distinct(positional, input) do
      {:ok, Map.merge(input, positional), opts}
    else
      false -> Authoring.error("Invalid interface argument count")
      error -> error
    end
  end

  defp split_options(arguments, required) do
    if length(arguments) > required and Keyword.keyword?(List.last(arguments)) do
      {Enum.drop(arguments, -1), List.last(arguments)}
    else
      {arguments, []}
    end
  end

  defp input(value) when is_map(value) and not is_struct(value), do: {:ok, value}
  defp input(_value), do: Authoring.error("Interface input must be a plain map")

  defp distinct(positional, input) do
    case Enum.filter(Map.keys(positional), &Map.has_key?(input, &1)) do
      [] -> :ok
      keys -> Authoring.error("Input supplied both positionally and by name", %{keys: keys})
    end
  end

  defp build_signal(config, data, opts) do
    with {:ok, envelope} <- Authoring.attrs(Keyword.get(opts, :signal, [])),
         :ok <- Authoring.keys(envelope, @signal_keys) do
      Jido.Signal.new(
        config.path,
        data,
        Map.to_list(Map.put_new(envelope, :source, config.source))
      )
    end
  end
end
