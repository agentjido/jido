defmodule Jido.Telemetry.AgentServer do
  @moduledoc """
  Owns the semantic event contract for AgentServer runtime work.

  The contract separates the Turn result from later Directive effects. A Turn
  can commit before its effects finish. The Turn stop and settled events report
  the evaluation and commit result. The effects stop event reports the bounded
  post-commit result.
  """

  alias Jido.Telemetry.Semantic

  @turn_prefix [:jido, :agent_server, :turn]

  @span_metrics [
    {@turn_prefix, [:stop], [:status, :stage]}
  ]

  @point_metrics [
    {[:jido, :agent_server, :lifecycle, :start], []},
    {[:jido, :agent_server, :lifecycle, :stop], []},
    {[:jido, :agent_server, :commit], [:status]},
    {[:jido, :agent_server, :directives, :returned], []},
    {[:jido, :agent_server, :effects, :start], []},
    {[:jido, :agent_server, :effects, :stop], [:status, :stage]},
    {[:jido, :agent_server, :turn, :settled], [:status, :stage]}
  ]

  @doc "Returns the AgentServer span metric specifications."
  @spec span_metrics() :: [{[atom()], [atom()], [atom()]}]
  def span_metrics, do: @span_metrics

  @doc "Returns the AgentServer point metric specifications."
  @spec point_metrics() :: [{[atom()], [atom()]}]
  def point_metrics, do: @point_metrics

  @doc "Returns every semantic AgentServer event name."
  @spec event_names() :: [[atom()]]
  def event_names do
    span_events = for {prefix, endings, _tags} <- @span_metrics, ending <- endings, do: prefix ++ [ending]
    point_events = Enum.map(@point_metrics, &elem(&1, 0))
    Enum.uniq([@turn_prefix ++ [:start] | span_events] ++ point_events)
  end

  @doc false
  @spec lifecycle(:start | :stop, String.t()) :: :ok
  def lifecycle(stage, agent_id) when stage in [:start, :stop] do
    Semantic.point([:jido, :agent_server, :lifecycle, stage], %{agent_id: agent_id})
  end

  @doc false
  @spec start_turn(map()) :: Semantic.span()
  def start_turn(metadata), do: Semantic.start(@turn_prefix, metadata)

  @doc false
  @spec start_effects(map(), non_neg_integer()) :: :ok
  def start_effects(metadata, directive_count) do
    Semantic.point(
      [:jido, :agent_server, :effects, :start],
      metadata,
      %{directive_count: directive_count}
    )
  end

  @doc false
  @spec finish_effects(map(), atom(), atom(), non_neg_integer(), non_neg_integer()) :: :ok
  def finish_effects(metadata, status, stage, completed, count) do
    Semantic.point(
      [:jido, :agent_server, :effects, :stop],
      Map.merge(metadata, %{committed?: true, stage: stage, status: status(status)}),
      %{directive_completed: completed, directive_count: count}
    )
  end

  @doc false
  @spec settle_turn(Semantic.span(), map(), map(), boolean(), non_neg_integer()) :: :ok
  def settle_turn(span, metadata, measurements, committed?, directive_count) do
    metadata = Map.update(metadata, :status, :error, &status/1)

    if committed? do
      Semantic.point([:jido, :agent_server, :commit], Map.merge(span.metadata, metadata), measurements)

      Semantic.point(
        [:jido, :agent_server, :directives, :returned],
        span.metadata,
        %{directive_count: directive_count}
      )
    end

    Semantic.finish(span, metadata, measurements)
    Semantic.point([:jido, :agent_server, :turn, :settled], Map.merge(span.metadata, metadata), measurements)
  end

  @doc false
  @spec status(atom()) :: atom()
  def status(:succeeded), do: :ok
  def status(:failed), do: :error
  def status(status), do: status
end
