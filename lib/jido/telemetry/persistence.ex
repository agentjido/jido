defmodule Jido.Telemetry.Persistence do
  @moduledoc false

  alias Jido.Telemetry.Semantic

  @prefix [:jido, :persistence, :operation]

  @doc false
  def observe(operation, source, agent_module, agent_id, opts, fun)
      when operation in [:load, :compare_and_swap, :delete] and is_function(fun, 0) do
    Semantic.with_span(
      @prefix,
      metadata(operation, source, agent_module, agent_id, opts),
      start_measurements(opts),
      fun,
      &result_measurements(&1, operation, opts)
    )
  end

  defp metadata(operation, source, agent_module, agent_id, opts) do
    opts = safe_options(opts)
    instance = Keyword.get(opts, :instance, instance(source))
    partition = Keyword.get(opts, :partition)

    %{
      operation: operation,
      agent_namespace: Keyword.get(opts, :namespace) || namespace(instance),
      agent_partition: if(is_binary(partition), do: partition),
      agent_id: agent_id,
      agent_module: agent_module,
      jido_instance: instance,
      partition: partition,
      adapter_module: adapter_module(source),
      persistence_reason: Keyword.get(opts, :reason, :manual)
    }
  end

  defp start_measurements(opts) do
    opts = safe_options(opts)

    %{}
    |> maybe_put_revision(:expected_revision, Keyword.get(opts, :expected_revision))
  end

  defp result_measurements({:ok, _agent, revision}, :load, _opts),
    do: %{revision_after: revision}

  defp result_measurements(:ok, :compare_and_swap, opts) do
    opts = safe_options(opts)
    maybe_put_revision(%{}, :revision_after, Keyword.get(opts, :revision, 0))
  end

  defp result_measurements(_result, _operation, _opts), do: %{}

  defp safe_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: opts, else: []
  end

  defp safe_options(_opts), do: []

  defp instance(source) when is_atom(source) and not is_nil(source) do
    cond do
      function_exported?(source, :__jido_persistence__, 0) ->
        source

      is_pid(Process.whereis(source)) and is_pid(Process.whereis(Jido.runtime_store_name(source))) ->
        source

      true ->
        nil
    end
  rescue
    _error -> nil
  end

  defp instance(_source), do: nil

  defp namespace(instance) when is_atom(instance) and not is_nil(instance) do
    Jido.namespace(instance)
  catch
    _, _ -> nil
  end

  defp namespace(_instance), do: nil

  defp adapter_module({adapter, _opts}) when is_atom(adapter), do: adapter

  defp adapter_module(source) when is_atom(source) and not is_nil(source) do
    if function_exported?(source, :get, 2), do: source
  end

  defp adapter_module(_source), do: nil

  defp maybe_put_revision(map, key, value) when is_integer(value) and value >= 0,
    do: Map.put(map, key, value)

  defp maybe_put_revision(map, _key, _value), do: map
end
