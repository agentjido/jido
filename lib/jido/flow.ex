defmodule Jido.Flow do
  @moduledoc """
  Defines one canonical composed Action program.

  A Flow contains named forms, explicit control dependencies, one output
  expression, and derived scheduling data. A Step is the form for one
  Instruction. The closed Flow form set contains Map, Reduce, Choice, Parallel,
  Iterate, Invoke, and Wait. A
  Flow graph contains only named forms. Dynamic items, branches, iterations,
  retries, and waits belong to execution state. The graph and semantic
  identity are derived from canonical source data. Codecs do not store them.

  A module that uses `Jido.Flow` exposes one ready-to-run Flow through
  `flow/0`.
  """

  alias Jido.Action.Output
  alias Jido.Flow.{Config, Error, Form, Graph, Limits, Value}
  alias Jido.Flow.Identity.Hash
  alias Jido.Validation

  @fields [:name, :description, :schema, :output_schema, :forms, :needs, :output]
  @config_fields [:name, :description, :schema, :output_schema]

  @typedoc "A stable source location for module DSL diagnostics."
  @type source_location :: %{optional(:file) => String.t(), optional(:line) => pos_integer()}
  @typedoc "Source locations keyed by canonical authoring path."
  @type source_map :: %{optional([term()]) => source_location()}
  @typedoc "Direct incoming dependencies for one named form."
  @type dependency_info :: %{data: [String.t()], control: [String.t()]}
  @typedoc "One canonical Flow form."
  @type form ::
          Jido.Flow.Call.t()
          | Jido.Flow.Form.Map.t()
          | Jido.Flow.Form.Reduce.t()
          | Jido.Flow.Form.Choice.t()
          | Jido.Flow.Form.Parallel.t()
          | Jido.Flow.Form.Iterate.t()
          | Jido.Flow.Form.Invoke.t()
          | Jido.Flow.Form.Wait.t()
  @typedoc "The deterministic semantic identity of one Flow."
  @type identity :: %{algorithm: :sha256, digest: String.t(), uuid: String.t()}
  @typedoc "One canonical Flow definition."
  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          schema: Jido.Action.schema(),
          output_schema: Jido.Action.schema(),
          forms: %{required(String.t()) => form()},
          needs: %{optional(String.t()) => [String.t()]},
          output: Value.t(),
          graph: Graph.t(),
          identity: identity()
        }

  @enforce_keys [:name, :forms, :output, :graph, :identity]
  defstruct name: nil,
            description: nil,
            schema: [],
            output_schema: [],
            forms: %{},
            needs: %{},
            output: nil,
            graph: nil,
            identity: nil

  @doc false
  @spec __jido_kind__() :: :flow
  def __jido_kind__, do: :flow

  @doc "Returns the canonical Flow owned by a Flow module."
  @callback flow() :: t()

  @doc "Validates Flow input parameters without running work."
  @callback validate_params(term()) :: {:ok, map()} | {:error, term()}

  @doc "Validates a normal Flow output or explicit output envelope."
  @callback validate_output(map() | Jido.Action.Output.t()) ::
              {:ok, map() | Jido.Action.Output.t()} | {:error, term()}

  @doc false
  @spec validate_params_for(term(), module()) :: {:ok, map()} | {:error, term()}
  def validate_params_for(params, module) do
    validate_map(
      module.schema(),
      params,
      %{context: "Flow", module: module},
      "Flow validation must return a map"
    )
  end

  @doc false
  @spec validate_output_for(map() | Output.t(), module()) ::
          {:ok, map() | Output.t()} | {:error, term()}
  def validate_output_for(%Output{} = output, module) do
    case Output.validate(output) do
      {:ok, output} ->
        {:ok, output}

      {:error, error} ->
        {:error,
         Error.validation_error(Exception.message(error), %{
           context: "Flow output",
           module: module
         })}
    end
  end

  def validate_output_for(output, module) do
    validate_map(
      module.output_schema(),
      output,
      %{context: "Flow output", module: module},
      "Flow output validation must return a map"
    )
  end

  defmacro __using__(opts_ast) do
    quote do
      use Jido.Flow.DSL.ModuleCompiler, unquote(opts_ast)
    end
  end

  @doc "Builds and validates one canonical Flow from map data."
  @spec new(map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs) when is_map(attrs) and not is_struct(attrs), do: build(attrs)

  def new(value), do: invalid_subject(value)

  @doc "Builds one canonical Flow or raises its validation error."
  @spec new!(map()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, flow} -> flow
      {:error, error} -> raise error
    end
  end

  @doc "Validates the exact canonical Flow structure without running work."
  @spec validate(t()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(%__MODULE__{} = flow) do
    case flow |> source_attrs() |> build() do
      {:ok, ^flow} ->
        {:ok, flow}

      {:ok, canonical} ->
        {:error,
         Error.validation_error("Flow is not canonical", %{
           reason: :non_canonical,
           canonical: canonical
         })}

      error ->
        error
    end
  end

  def validate(value), do: invalid_subject(value)

  @doc "Returns direct data and control dependencies for each named form."
  @spec dependencies(t()) :: {:ok, %{String.t() => dependency_info()}} | {:error, Exception.t()}
  def dependencies(%__MODULE__{graph: %Graph{dependencies: dependencies}}),
    do: {:ok, dependencies}

  def dependencies(value), do: invalid_subject(value)

  @doc "Returns a map view of the canonical Flow."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = flow) do
    %{
      name: flow.name,
      description: flow.description,
      schema: flow.schema,
      output_schema: flow.output_schema,
      forms: flow.forms,
      needs: flow.needs,
      output: Value.to_map(flow.output)
    }
  end

  @doc "Returns stable inspection data for a canonical Flow."
  @spec explain(t()) :: {:ok, map()} | {:error, Exception.t()}
  def explain(%__MODULE__{} = flow) do
    {:ok,
     flow
     |> to_map()
     |> Map.merge(%{
       kind: :flow,
       dependencies: flow.graph.dependencies,
       identity: flow.identity
     })}
  end

  def explain(value), do: invalid_subject(value)

  @doc "Returns the deterministic SHA-256 and UUIDv8 identity for a Flow."
  @spec semantic_identity(t()) :: {:ok, identity()} | {:error, Exception.t()}
  def semantic_identity(%__MODULE__{identity: identity}), do: {:ok, identity}

  def semantic_identity(value), do: invalid_subject(value)

  defp validate_map(schema, value, details, message) do
    case Validation.open_validate(schema, value, details) do
      {:ok, validated} when is_map(validated) ->
        {:ok, validated}

      {:ok, validated} ->
        {:error, Error.validation_error(message, Map.put(details, :value, validated))}

      {:error, %Validation.Error{} = error} ->
        {:error, Error.validation_error(error.message, error.details)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build(attrs) do
    with :ok <- validate_fields(attrs),
         {:ok, config} <- validate_config(attrs),
         {:ok, forms} <- normalize_forms(Map.get(attrs, :forms)),
         {:ok, needs} <- normalize_needs(Map.get(attrs, :needs, %{})),
         {:ok, output} <- normalize_output(attrs),
         {:ok, graph} <- Graph.build(forms, needs),
         :ok <- validate_output_refs(output, forms) do
      flow =
        struct!(
          __MODULE__,
          Map.merge(config, %{
            forms: forms,
            needs: needs,
            output: output,
            graph: graph,
            identity: nil
          })
        )

      identity = flow |> Form.identity_data() |> Hash.identity()
      flow = %{flow | identity: identity}

      {:ok, flow}
    end
  end

  defp validate_fields(attrs) do
    case Map.keys(attrs) -- @fields do
      [] ->
        :ok

      fields ->
        {:error,
         Error.validation_error("Flow contains unknown fields", %{
           reason: :unknown_fields,
           fields: Enum.sort(fields)
         })}
    end
  end

  defp validate_config(attrs) do
    attrs
    |> Map.take(@config_fields)
    |> Config.validate()
  end

  defp normalize_forms(nil),
    do: {:error, Error.validation_error("Flow forms are required", %{reason: :forms_required})}

  defp normalize_forms(forms) when is_map(forms) and not is_struct(forms) do
    with :ok <- Limits.collection(forms, :forms),
         :ok <- require_forms(forms) do
      forms
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce_while({:ok, %{}}, fn {raw_id, raw_form}, {:ok, result} ->
        with {:ok, id} <- normalize_name(raw_id, [:forms, raw_id]),
             :ok <- unique_name(result, id, [:forms, raw_id]),
             {:ok, form} <- normalize_form(raw_form, id) do
          {:cont, {:ok, Map.put(result, id, form)}}
        else
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  defp normalize_forms(value),
    do:
      {:error,
       Error.validation_error("Flow forms must be a map", %{reason: :forms, value: value})}

  defp require_forms(forms) when map_size(forms) > 0, do: :ok

  defp require_forms(_forms),
    do:
      {:error,
       Error.validation_error("Flow must contain at least one form", %{reason: :empty_forms})}

  defp normalize_form(value, id) do
    case Form.normalize(value) do
      {:ok, form} -> {:ok, form}
      {:error, error} -> {:error, Error.prefix_path(error, [:forms, id])}
    end
  end

  defp normalize_needs(needs) when is_map(needs) and not is_struct(needs) do
    needs
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, %{}}, fn {raw_id, raw_sources}, {:ok, result} ->
      with {:ok, id} <- normalize_name(raw_id, [:needs, raw_id]),
           :ok <- unique_name(result, id, [:needs, raw_id]),
           {:ok, sources} <- normalize_need_sources(raw_sources, id) do
        result = if sources == [], do: result, else: Map.put(result, id, sources)
        {:cont, {:ok, result}}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp normalize_needs(value),
    do:
      {:error,
       Error.validation_error("Flow needs must be a map", %{reason: :needs, value: value})}

  defp normalize_need_sources(sources, id) when is_list(sources) do
    if List.improper?(sources) do
      {:error,
       Error.validation_error("Flow form needs must be a proper list", %{
         reason: :needs,
         path: [:needs, id]
       })}
    else
      sources
      |> Enum.reduce_while({:ok, []}, fn source, {:ok, result} ->
        case normalize_name(source, [:needs, id]) do
          {:ok, source} -> {:cont, {:ok, [source | result]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
      |> case do
        {:ok, result} -> {:ok, result |> Enum.uniq() |> Enum.sort()}
        error -> error
      end
    end
  end

  defp normalize_need_sources(value, id) do
    {:error,
     Error.validation_error("Flow form needs must be a list", %{
       reason: :needs,
       path: [:needs, id],
       value: value
     })}
  end

  defp normalize_output(attrs) do
    case Map.fetch(attrs, :output) do
      {:ok, nil} ->
        {:error,
         Error.validation_error("Flow output is required", %{
           reason: :output_required,
           path: [:output]
         })}

      {:ok, output} ->
        case Value.prepare(output) do
          {:ok, output} -> {:ok, output}
          {:error, error} -> {:error, Error.prefix_path(error, [:output])}
        end

      :error ->
        {:error,
         Error.validation_error("Flow output is required", %{
           reason: :output_required,
           path: [:output]
         })}
    end
  end

  defp validate_output_refs(output, forms) do
    ids = MapSet.new(Map.keys(forms))

    case Enum.find(Value.result_refs(output), &(not MapSet.member?(ids, &1))) do
      nil ->
        :ok

      id ->
        {:error,
         Error.validation_error("Flow output references an unknown form", %{
           reason: :unknown_output_reference,
           step: id,
           path: [:output]
         })}
    end
  end

  defp normalize_name(name, path) when is_atom(name) and name not in [nil, true, false],
    do: normalize_name(Atom.to_string(name), path)

  defp normalize_name(name, path) when is_binary(name) do
    case Config.validate_name(name, subject: "Flow form") do
      :ok -> {:ok, name}
      {:error, message} -> {:error, Error.validation_error(message, %{path: path})}
    end
  end

  defp normalize_name(name, path),
    do:
      {:error,
       Error.validation_error("Flow form name must be a string or atom", %{
         path: path,
         value: name
       })}

  defp unique_name(values, id, path) do
    if Map.has_key?(values, id) do
      {:error,
       Error.validation_error("Flow contains a duplicate normalized form name", %{
         reason: :duplicate_form,
         form: id,
         path: path
       })}
    else
      :ok
    end
  end

  defp source_attrs(%__MODULE__{} = flow) do
    flow
    |> Map.from_struct()
    |> Map.take(@fields)
  end

  defp invalid_subject(value),
    do: {:error, Error.validation_error("expected a Jido.Flow", %{value: value})}
end
