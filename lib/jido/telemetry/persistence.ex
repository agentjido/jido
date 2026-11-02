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
      adapter_module: adapter_module(source),
      persistence_reason: Keyword.get(opts, :reason, :manual)
    }
  end

  defp start_measurements(opts) do
    opts = safe_options(opts)
    %{expected_revision: Keyword.get(opts, :expected_revision)}
  end

  defp result_measurements({:ok, _agent, revision}, :load, _opts),
    do: %{revision_after: revision}

  defp result_measurements(:ok, :compare_and_swap, opts) do
    opts = safe_options(opts)
    %{revision_after: Keyword.get(opts, :revision, 0)}
  end

  defp result_measurements(_result, _operation, _opts), do: %{}

  defp safe_options(opts) do
    if Keyword.keyword?(opts), do: opts, else: []
  end

  defp instance(source) do
    if function_exported?(source, :__jido_persistence__, 0) or
         (is_pid(Process.whereis(source)) and
            is_pid(Process.whereis(Jido.runtime_store_name(source)))) do
      source
    end
  rescue
    _error -> nil
  end

  defp namespace(nil), do: nil

  defp namespace(instance) do
    Jido.namespace(instance)
  catch
    _, _ -> nil
  end

  defp adapter_module({adapter, _opts}), do: adapter

  defp adapter_module(source) do
    if function_exported?(source, :get, 2), do: source
  rescue
    _error -> nil
  end
end
