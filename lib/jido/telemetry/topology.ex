defmodule Jido.Telemetry.Topology do
  @moduledoc false

  alias Jido.Telemetry.Semantic

  @prefix [:jido, :topology, :operation]

  @doc false
  def start(operation, state) when operation in [:activate, :repair, :update, :place, :cleanup] do
    Semantic.start(@prefix, metadata(operation, state), component_measurements(state))
  end

  @doc false
  def finish(span, status, state) when status in [:ok, :error] do
    Semantic.finish(span, %{status: status}, component_measurements(state))
  end

  defp metadata(operation, state) do
    %{
      topology_id: state.instance.id,
      topology_operation: operation,
      jido_instance: state.jido
    }
  end

  defp component_measurements(state) do
    %{
      component_count:
        map_size(state.instance.plan.agents) + map_size(state.instance.plan.resources),
      ready_count: map_size(state.ready),
      failed_count: map_size(state.errors)
    }
  end
end
