defmodule Jido.Persistence.Snapshot do
  @moduledoc false
  alias Jido.Agent
  alias Jido.Agent.{Data, Error}
  alias Jido.PortableTerm

  @format 1
  @keys [:format, :agent, :references, :state_format]

  @doc false
  def dump(agent, context, convert_state, state_mode \\ :auto) do
    with {:ok, agent} <- Agent.validate(agent),
         :ok <- Data.nonempty(agent.id),
         {:ok, frozen} <- freeze(agent),
         {:ok, state, format} <- dump_state(frozen, context, convert_state, state_mode),
         {:ok, references} <- fingerprints(code_modules(frozen, format)),
         snapshot = %{
           format: @format,
           agent: %{frozen | state: state},
           references: references,
           state_format: format
         },
         :ok <- portable(snapshot) do
      {:ok, snapshot}
    end
  end

  @doc false
  def load(snapshot, context, convert_state) do
    with :ok <- envelope(snapshot),
         :ok <- required_references(snapshot),
         :ok <- verify_references(snapshot.references),
         true <-
           MapSet.new(code_modules(snapshot.agent, snapshot.state_format)) ==
             MapSet.new(Map.keys(snapshot.references)),
         {:ok, state} <- load_state(snapshot, context, convert_state),
         {:ok, agent} <- Agent.validate(%{snapshot.agent | state: state}) do
      {:ok, agent}
    else
      false ->
        Error.fail(
          :snapshot_references,
          [:references],
          "Snapshot reference manifest is incomplete"
        )

      error ->
        error
    end
  rescue
    error -> Error.fail(:invalid_snapshot, [], "Snapshot references are invalid", %{cause: error})
  end

  @doc false
  def envelope(%{format: format}) when format != @format do
    Error.fail(
      :unsupported_snapshot_format,
      [:format],
      "Agent snapshot format is not supported",
      %{format: format, supported_formats: [@format]}
    )
  end

  def envelope(snapshot) do
    with {:ok, _} <- Data.fields(snapshot, @keys),
         true <- Map.keys(snapshot) |> Enum.sort() == Enum.sort(@keys),
         true <- snapshot.format == @format,
         %Agent{} <- snapshot.agent,
         :ok <- Data.nonempty(snapshot.agent.id),
         true <- snapshot.state_format in [:default, :custom],
         :ok <- Data.plain_map(snapshot.references),
         true <-
           Enum.all?(snapshot.references, fn {module, digest} ->
             is_atom(module) and is_binary(digest) and byte_size(digest) == 16
           end),
         :ok <- portable(snapshot) do
      :ok
    else
      {:error, _} = error -> error
      _ -> Error.fail(:invalid_snapshot, [], "Invalid Agent snapshot")
    end
  end

  @doc false
  def freeze(%Agent{} = agent) do
    with {:ok, agents} <-
           Data.list(agent.topology.agents, fn member ->
             with {:ok, definition} <- Agent.Validation.resolve(member.definition),
                  {:ok, definition} <- freeze(definition),
                  do: {:ok, %{member | definition: definition}}
           end),
         do: {:ok, %{agent | topology: %{agent.topology | agents: agents}}}
  end

  defp dump_state(agent, context, convert, state_mode) do
    if state_mode == :auto and callback?(agent.module, :checkpoint) do
      case Agent.Callback.invoke(agent.module, :checkpoint, [agent, context]) do
        {:ok, payload} ->
          with :ok <- Data.plain_map(payload), do: {:ok, payload, :custom}

        {:error, _} = error ->
          error

        result ->
          Error.fail(
            :invalid_snapshot_state,
            [:agent, :state],
            "Checkpoint callback must return {:ok, Map} or {:error, reason}",
            %{result: result}
          )
      end
    else
      with {:ok, state} <- convert.(agent, agent.state), do: {:ok, state, :default}
    end
  end

  defp load_state(%{state_format: :default, agent: agent}, _context, convert),
    do: convert.(agent, agent.state)

  defp load_state(%{agent: saved}, context, _convert) do
    with true <- callback?(saved.module, :restore),
         {:ok, %Agent{id: id, state: state}} <-
           Agent.Callback.invoke(saved.module, :restore, [saved.state, context]),
         true <- id == saved.id do
      {:ok, state}
    else
      {:error, _} = error ->
        error

      _ ->
        Error.fail(
          :invalid_snapshot_state,
          [:agent, :state],
          "Custom restore must retain the saved identity"
        )
    end
  end

  defp callback?(module, callback),
    do: Code.ensure_loaded?(module) and function_exported?(module, callback, 2)

  defp code_modules(agent, state_format \\ :default) do
    handlers =
      Enum.flat_map(agent.routes, fn
        %{handler: %{kind: :transform, target: {module, _, _}}} ->
          [module]

        %{handler: %{kind: kind, target: module}} when kind in [:action, :flow] ->
          executable_modules(module, kind, [])

        _ ->
          []
      end)

    providers =
      Enum.flat_map(agent.extensions, fn entry ->
        case entry.provider.runtime_support() do
          :none -> [entry.provider]
          module -> [entry.provider, module]
        end
      end)

    custom = if state_format == :custom, do: [agent.module], else: []
    nested = Enum.flat_map(agent.topology.agents, &code_modules(&1.definition))
    Enum.uniq(handlers ++ providers ++ custom ++ nested ++ schema_modules(agent.schema))
  end

  # Check saved declarations before any code-dependent state converter runs.
  defp required_references(snapshot) do
    required = MapSet.new(saved_modules(snapshot.agent))

    if MapSet.subset?(required, MapSet.new(Map.keys(snapshot.references))),
      do: :ok,
      else:
        Error.fail(
          :snapshot_references,
          [:references],
          "Snapshot reference manifest is incomplete"
        )
  end

  defp saved_modules(agent) do
    handlers =
      Enum.flat_map(agent.routes, fn
        %{handler: %{kind: :transform, target: {module, _, _}}} -> [module]
        %{handler: %{kind: kind, target: module}} when kind in [:action, :flow] -> [module]
        _ -> []
      end)

    providers = Enum.map(agent.extensions, & &1.provider)
    nested = Enum.flat_map(agent.topology.agents, &saved_modules(&1.definition))
    handlers ++ providers ++ nested ++ schema_modules(agent.schema)
  end

  # Flow calls and executable schema refinements are declared code references.
  # Arbitrary imports inside a function remain part of the retained code release.
  defp executable_modules(module, kind, seen) do
    if module in seen do
      []
    else
      schemas =
        Enum.flat_map([:schema, :output_schema], fn function ->
          if function_exported?(module, function, 0),
            do: schema_modules(apply(module, function, [])),
            else: []
        end)

      calls =
        if kind == :flow and function_exported?(module, :flow, 0),
          do: flow_modules(module.flow(), [module | seen]),
          else: []

      [module | schemas ++ calls]
    end
  end

  defp flow_modules(flow, seen) do
    calls =
      Enum.flat_map(flow.components, fn {_, component} ->
        Enum.flat_map(Jido.Flow.Definition.calls(component), fn {_, call, _} ->
          executable_modules(call.target, call.kind, seen)
        end)
      end)

    calls ++ schema_modules(flow)
  end

  defp schema_modules(%Zoi.Types.Meta{effects: effects}),
    do: for({:refine, {module, _, _}} <- effects, do: module)

  defp schema_modules(value) when is_map(value),
    do: value |> Map.to_list() |> Enum.flat_map(fn {_, item} -> schema_modules(item) end)

  defp schema_modules(value) when is_list(value), do: Enum.flat_map(value, &schema_modules/1)

  defp schema_modules(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.flat_map(&schema_modules/1)

  defp schema_modules(_), do: []

  defp fingerprints(modules) do
    with {:ok, values} <-
           Data.list(modules, fn module ->
             with {:ok, digest} <- fingerprint(module), do: {:ok, {module, digest}}
           end),
         do: {:ok, Map.new(values)}
  end

  defp fingerprint(module) do
    if Code.ensure_loaded?(module),
      do: {:ok, module.module_info(:md5)},
      else:
        Error.fail(:unavailable_reference, [:references], "Snapshot code is unavailable", %{
          module: module
        })
  end

  defp verify_references(references) do
    with {:ok, _} <-
           Data.list(Map.to_list(references), fn {module, expected} ->
             with {:ok, actual} <- fingerprint(module) do
               if actual == expected,
                 do: {:ok, module},
                 else:
                   Error.fail(
                     :changed_reference,
                     [:references],
                     "Snapshot code changed; use an explicit upgrade Action",
                     %{module: module}
                   )
             end
           end),
         do: :ok
  end

  defp portable(value) do
    case PortableTerm.validate(value, [:snapshot]) do
      :ok ->
        :ok

      {:error, path} ->
        Error.fail(:non_portable_term, path, "Snapshot contains a non-portable value")
    end
  end

  @doc false
  def upgrade(snapshot, action, context, restore) do
    with :ok <- envelope(snapshot),
         {:ok, %{kind: :action}} <- Jido.Instruction.resolve(action),
         {:ok, output} <-
           upgrade_result(Jido.Exec.run(action, %{snapshot: snapshot}, context, [])),
         :ok <- envelope(output),
         true <-
           {output.agent.id, output.agent.module} == {snapshot.agent.id, snapshot.agent.module},
         {:ok, candidate} <- restore.(output) do
      {:ok, candidate}
    else
      false ->
        Error.fail(
          :upgrade_identity,
          [:agent],
          "Upgrade must preserve Agent id and origin module"
        )

      {:error, _} = error ->
        error

      _ ->
        Error.fail(
          :invalid_upgrade,
          [],
          "Upgrade requires an Action and a complete snapshot result"
        )
    end
  end

  defp upgrade_result({:ok, %{snapshot: snapshot} = output}) when map_size(output) == 1,
    do: {:ok, snapshot}

  defp upgrade_result({:error, _} = error), do: error

  defp upgrade_result(_),
    do:
      Error.fail(
        :invalid_upgrade_result,
        [],
        "Upgrade must return one snapshot and no Directives"
      )
end
