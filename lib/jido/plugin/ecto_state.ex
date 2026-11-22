if Code.ensure_loaded?(Ecto.Adapters.SQL) do
  defmodule Jido.Plugin.EctoState do
    @moduledoc """
    Uses one Ecto row as the authoritative state for a live Agent.

    Declare `ecto SchemaModule` in the Agent's state block. The schema must
    export `repo/0` and `changeset/2`. It needs one primary key, addressed by
    the Agent ID, and a non-null integer `:lock_version` field.

    Read the current row at
    `context.plugin_inputs[Jido.Plugin.EctoState].runtime.row`. Return an
    `update/1` Directive to propose a write. The Plugin saves the proposal
    with an optimistic lock before the Turn commits. The application creates
    the row and all writers must advance its lock version.
    To write the row, run the Agent with Jido persistence disabled.
    """

    use Jido.Plugin

    alias Ecto.Changeset
    alias Jido.Joi

    defmodule Update do
      @moduledoc "Proposes one Ecto row update in the current Turn."
      use Jido.Agent.Directive
      @enforce_keys [:attrs]
      defstruct [:attrs]

      @impl true
      def validate(%__MODULE__{attrs: attrs} = directive) when is_map(attrs) and not is_struct(attrs),
        do: {:ok, directive}

      def validate(_directive), do: {:error, :invalid_ecto_state_changes}
    end

    @doc "Returns a Directive that proposes changes to the admitted row."
    @spec update(map()) :: struct()
    def update(attrs) when is_map(attrs) and not is_struct(attrs), do: %Update{attrs: attrs}

    @impl Jido.Agent.Extension
    def normalize(%{schema: schema} = config) when is_atom(schema) and map_size(config) == 1 do
      with {:module, ^schema} <- Code.ensure_compiled(schema),
           true <- function_exported?(schema, :__schema__, 1),
           true <- is_binary(schema.__schema__(:source)),
           [key] when key != :lock_version <- schema.__schema__(:primary_key),
           :integer <- schema.__schema__(:type, :lock_version),
           {updatable, _read_only} <- schema.__schema__(:updatable_fields),
           true <- :lock_version in updatable,
           true <- function_exported?(schema, :repo, 0) and function_exported?(schema, :changeset, 2) do
        {:ok, config}
      else
        _ -> {:error, :invalid_ecto_state_schema}
      end
    end

    def normalize(_config), do: {:error, :invalid_ecto_state_schema}

    @impl Jido.Agent.Extension
    def verify(_config, definition) do
      if definition.schema == Joi.object(%{}) and definition.initial_state == %{},
        do: :ok,
        else: {:error, :ecto_state_schema_conflict}
    end

    @impl Jido.Plugin
    def state_spec(_opts), do: {:ecto_changes, Joi.map() |> Joi.nullable() |> Joi.default(nil)}

    @impl Jido.Plugin
    def directives(_opts), do: [Update]

    @impl Jido.Plugin
    def admit(_runtime, admission, opts) do
      schema = Keyword.fetch!(opts, :schema)
      repo = schema.repo()

      case repo.get(schema, admission.agent_id) do
        %{lock_version: version} = row when is_integer(version) -> {:ok, %{repo: repo, row: row}}
        nil -> {:error, :ecto_state_not_found}
        _row -> {:error, :invalid_ecto_state_lock_version}
      end
    end

    @impl Jido.Plugin
    def reduce(reduction, _opts) do
      case for(%Update{attrs: attrs} <- reduction.directives, do: attrs) do
        [] -> {:ok, nil}
        [attrs] -> {:ok, attrs}
        _ -> {:error, :multiple_ecto_state_updates}
      end
    end

    @impl Jido.Plugin
    def before_commit(_runtime, %{plugin_state: nil}, _opts), do: :ok

    def before_commit(_runtime, %{jido_persistence?: true}, _opts),
      do: {:error, :ecto_state_requires_memory_turn}

    def before_commit(_runtime, %{plugin_state: attrs, runtime_input: %{repo: repo, row: row}}, opts) do
      schema = Keyword.fetch!(opts, :schema)
      protected = [:lock_version | schema.__schema__(:primary_key)]
      {updatable, _read_only} = schema.__schema__(:updatable_fields)
      allowed = updatable -- protected

      with true <- Enum.all?(Map.keys(attrs), &(&1 in allowed)),
           %Changeset{data: ^row, changes: changes} = changeset <- schema.changeset(row, attrs),
           false <- Enum.any?(protected, &Map.has_key?(changes, &1)) do
        save(repo, Changeset.optimistic_lock(changeset, :lock_version))
      else
        _ -> {:error, :invalid_ecto_state_changes}
      end
    end

    def before_commit(_runtime, _commit, _opts), do: {:error, :ecto_state_not_admitted}

    defp save(repo, changeset) do
      case repo.update(changeset, force: true, stale_error_field: :lock_version) do
        {:ok, _row} ->
          :ok

        {:error, %Changeset{errors: errors}} ->
          if match?({_, [stale: true]}, Keyword.get(errors, :lock_version)),
            do: {:error, :stale_ecto_state},
            else: {:error, {:invalid_ecto_state_changes, errors}}
      end
    catch
      # A lost database response can leave the write outcome unknown.
      _kind, _reason -> {:error, :indeterminate}
    end
  end
end
