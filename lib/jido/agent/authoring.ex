defmodule Jido.Agent.Authoring do
  @moduledoc false

  alias Jido.Error
  alias Jido.Signal.Router

  def attrs(value) when is_map(value) and not is_struct(value), do: {:ok, value}

  def attrs(value) when is_list(value) do
    if Keyword.keyword?(value) and
         length(Keyword.keys(value)) == length(Enum.uniq(Keyword.keys(value))),
       do: {:ok, Map.new(value)},
       else: error("Expected unique keyword options", %{value: value})
  end

  def attrs(value), do: error("Expected a map or keyword list", %{value: value})

  def options(value) do
    with {:ok, attrs} <- attrs(value),
         do: {:ok, if(is_list(value), do: value, else: Enum.sort(attrs))}
  end

  def route(path, target, opts \\ []) do
    with {:ok, opts} <- attrs(opts),
         :ok <- keys(opts, [:defaults, :priority, :match]),
         :ok <- defaults(opts) do
      target = if Map.has_key?(opts, :defaults), do: {target, opts.defaults}, else: target

      case Router.normalize(%Router.Route{
             path: path,
             target: target,
             priority: Map.get(opts, :priority, 0),
             match: Map.get(opts, :match)
           }) do
        {:ok, [route]} -> {:ok, route}
        error -> error
      end
    end
  end

  def routes(routes) when is_list(routes) do
    traverse(routes, fn
      {path, target, opts} when is_list(opts) ->
        route(path, target, opts)

      %{path: path, target: target} = spec when not is_struct(spec) ->
        with :ok <- keys(spec, [:path, :target, :defaults, :priority, :match]),
             do: route(path, target, Map.drop(spec, [:path, :target]))

      other when is_list(other) ->
        error("Expected one route specification")

      other ->
        case Router.normalize(other) do
          {:ok, [route]} -> {:ok, route}
          {:ok, _routes} -> error("Expected one route specification")
          {:error, _error} = error -> error
        end
    end)
  end

  def routes(value), do: error("Agent routes must be a list", %{value: value})

  def keys(map, allowed) do
    case Map.keys(map) -- allowed do
      [] -> :ok
      unknown -> error("Unknown authoring fields", %{keys: unknown})
    end
  end

  def traverse(values, fun), do: traverse(values, fun, [])

  defp traverse([], _fun, acc), do: {:ok, Enum.reverse(acc)}

  defp traverse([value | tail], fun, acc) do
    case fun.(value) do
      {:ok, result} -> traverse(tail, fun, [result | acc])
      {:error, _error} = error -> error
    end
  end

  defp traverse(_tail, _fun, _acc), do: error("Expected a proper list")

  def error(message, details \\ %{}),
    do: {:error, Error.validation_error(message, kind: :config, details: details)}

  defp defaults(%{defaults: value}) when not is_map(value) or is_struct(value),
    do: error("Route defaults must be a plain map")

  defp defaults(_opts), do: :ok
end
