defmodule Jido.Agent.Authoring do
  @moduledoc false

  alias Jido.Error
  alias Jido.Signal.Router

  def attrs(value) do
    case to_attrs(value, :reject) do
      {:ok, attrs} -> {:ok, attrs}
      :error when is_list(value) -> error("Expected unique keyword options", %{value: value})
      :error -> error("Expected a map or keyword list", %{value: value})
    end
  end

  # Public boundaries keep their own duplicate policy and error context.
  def to_attrs(value, duplicates \\ :last)
  def to_attrs(value, _duplicates) when is_map(value) and not is_struct(value), do: {:ok, value}

  def to_attrs(value, duplicates) when is_list(value) do
    if Keyword.keyword?(value) and
         (duplicates == :last or Enum.uniq(Keyword.keys(value)) == Keyword.keys(value)),
       do: {:ok, Map.new(value)},
       else: :error
  end

  def to_attrs(_value, _duplicates), do: :error

  def split_target({target, defaults}) when is_map(defaults), do: {target, defaults}
  def split_target(target), do: {target, nil}

  def options(value) do
    with {:ok, attrs} <- attrs(value),
         do: {:ok, if(is_list(value), do: value, else: Enum.sort(attrs))}
  end

  def route(path, target, opts \\ []) do
    with {:ok, opts} <- attrs(opts),
         :ok <- keys(opts, [:defaults, :priority, :match]),
         :ok <- defaults(opts) do
      target = if Map.has_key?(opts, :defaults), do: {target, opts.defaults}, else: target

      normalize_one_route(%Router.Route{
        path: path,
        target: target,
        priority: Map.get(opts, :priority, 0),
        match: Map.get(opts, :match)
      })
    end
  end

  def routes(routes) when is_list(routes) do
    traverse_indexed(routes, fn
      {path, target, opts} when is_list(opts) ->
        route(path, target, opts)

      %{path: path, target: target} = spec when not is_struct(spec) ->
        with :ok <- keys(spec, [:path, :target, :defaults, :priority, :match]),
             do: route(path, target, Map.drop(spec, [:path, :target]))

      other when is_list(other) ->
        error("Expected one route specification")

      other ->
        normalize_one_route(other)
    end)
  end

  def routes(value), do: error("Agent routes must be a list", %{value: value})

  defp normalize_one_route(spec) do
    case Router.normalize(spec) do
      {:ok, [route]} -> with :ok <- defaults(route.target), do: {:ok, route}
      {:ok, _routes} -> error("Expected one route specification")
      {:error, _error} = error -> error
    end
  end

  def keys(map, allowed) do
    case Map.keys(map) -- allowed do
      [] -> :ok
      unknown -> error("Unknown authoring fields", %{keys: unknown})
    end
  end

  def traverse(values, fun), do: traverse(values, fn value, _index -> fun.(value) end, 0, [])

  def traverse_indexed(values, fun),
    do: traverse(values, fn value, index -> at(fun.(value), index) end, 0, [])

  defp traverse([], _fun, _index, acc), do: {:ok, Enum.reverse(acc)}

  defp traverse([value | tail], fun, index, acc) do
    case fun.(value, index) do
      {:ok, result} -> traverse(tail, fun, index + 1, [result | acc])
      {:error, _error} = error -> error
    end
  end

  defp traverse(_tail, _fun, _index, _acc), do: error("Expected a proper list")

  def check_each(values, fun) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case fun.(value) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  def at({:error, %{details: details} = error}, path) do
    details = details || %{}
    path = List.wrap(path) ++ Map.get(details, :source_path, [])
    {:error, %{error | details: Map.put(details, :source_path, path)}}
  end

  def at(result, _path), do: result

  def unwrap!({:ok, value}), do: value
  def unwrap!({:error, error}), do: raise(error)

  def error(message, details \\ %{}),
    do: {:error, Error.validation_error(message, kind: :config, details: details)}

  def location(env, %{__spark_metadata__: %{anno: anno}}) when not is_nil(anno),
    do: %{env | line: :erl_anno.line(anno)}

  def location(env, _entity), do: env

  defp defaults({_target, value}) when is_map(value), do: defaults(%{defaults: value})

  defp defaults(%{defaults: value}) when not is_map(value) or is_struct(value),
    do: error("Route defaults must be a plain map")

  defp defaults(_opts), do: :ok
end
