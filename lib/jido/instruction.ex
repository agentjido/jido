defmodule Jido.Instruction do
  @moduledoc """
  Defines the invocation value for one Action or Flow target.

  A resolved Instruction identifies the target kind and keeps the exact target,
  parameters, context, and descriptive metadata:

      %Jido.Instruction{
        kind: :action,
        target: MyApp.Actions.SendEmail,
        params: %{to: "user@example.com"},
        context: %{tenant_id: "tenant_123"},
        metadata: %{request_id: "req_123"}
      }

  An Action target is a module that implements `Jido.Action`. A Flow target is
  a module authored with `Jido.Flow`, a module that implements its behaviour,
  or a runtime `Jido.Flow` value. Generated Action and Flow modules share the
  Action behaviour and retain an explicit target kind.
  Resolution checks the currently loaded module on every execution. A stored
  `kind` value does not remain authoritative after code reload.

  `resolve/3` accepts a target or an existing Instruction. Use `new!/1`
  when construction must raise on invalid call data. `normalize!/3` is an
  internal raising helper, not a separate authoring API.
  Existing Instructions are flattened. Their parameters and context are merged
  with shallow, right-biased call data. Metadata remains an annotation and has
  no meaning to the target or to Exec.

  Bound Instructions can be direct Exec targets or Invoke continuation
  targets.
  Public constructors accept map parameters. Flow can resolve any portable
  value before Action input validation, so an internal bound call can hold a
  non-map value long enough for the target validator to return its normal
  input error.

  `template/3` creates an inert module reference with a declared target kind.
  It does not load or inspect the module. `bind/4` turns a template into a
  resolved Instruction after it checks the current module kind and executable
  callbacks. Canonical Flow components use small call records. Exec creates
  Instructions at the execution boundary. Bound runtime context stays outside
  portable Flow data.

  Use `:target` for every target kind. The removed `:action`, `:flow`, and
  `:opts` inputs return construction errors. Pass execution options directly to
  `Jido.Exec`.

  Constructor maps are not a stored or JSON representation. Module atoms and
  runtime Flow values do not have one general JSON form.
  """

  alias Jido.Action.Error
  alias Jido.Flow

  @removed_fields [:id, :action, :flow, :opts]

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind:
                Zoi.enum([:action, :flow], description: "Resolved target kind")
                |> Zoi.optional(),
              target: Zoi.any(description: "Action or Flow target") |> Zoi.optional(),
              params: Zoi.any(description: "Resolved target parameters") |> Zoi.default(%{}),
              context: Zoi.map(description: "Execution context") |> Zoi.default(%{}),
              metadata: Zoi.map(description: "Instruction metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @typedoc "The resolved target kind."
  @type kind :: :action | :flow
  @typedoc "An Action module, Flow module, or runtime Flow value."
  @type target :: module() | Flow.t()
  @typedoc "A resolved call value for one Action or Flow target."
  @type t :: unquote(Zoi.type_spec(@schema))
  @typedoc "An inert module target with a declared kind and no bound call data."
  @type template_t :: %__MODULE__{
          kind: kind(),
          target: module(),
          params: map(),
          context: map(),
          metadata: metadata()
        }
  @typedoc "Resolved input parameters before target validation."
  @type params :: term()
  @typedoc "Caller-supplied execution context."
  @type context :: map()
  @typedoc "Caller metadata with no execution meaning."
  @type metadata :: map()

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Creates an inert Instruction template for a module target.

  This function does not load or inspect `target`. The declared `kind` is
  checked when `bind/4` prepares the template for execution.

  A template has empty parameters and context. Metadata is portable authoring
  data and must be a map.
  """
  @spec template(kind(), module(), metadata()) :: template_t()
  def template(kind, target, metadata \\ %{}) do
    unless kind in [:action, :flow] do
      raise ArgumentError, "expected Instruction template kind to be :action or :flow"
    end

    unless is_atom(target) and not is_nil(target) do
      raise ArgumentError, "expected Instruction template target to be a module atom"
    end

    unless is_map(metadata) do
      raise ArgumentError, "expected Instruction template metadata to be a map"
    end

    %__MODULE__{
      kind: kind,
      target: target,
      params: %{},
      context: %{},
      metadata: metadata
    }
  end

  @doc """
  Binds concrete call data to an inert Instruction template.

  Parameters remain raw until target input validation. Context and runtime
  metadata must be maps. Runtime metadata replaces equal keys in template
  metadata. Binding loads and classifies the target, confirms its declared
  kind, and validates its executable callbacks.
  """
  @spec bind(template_t() | term(), params(), map(), map()) ::
          {:ok, t()} | {:error, Exception.t()}
  def bind(template, params, context, metadata \\ %{}) do
    with :ok <- validate_template(template),
         {:ok, context} <- require_map_field(context, :context),
         {:ok, metadata} <- require_map_field(metadata, :metadata),
         {:ok, actual_kind} <- classify(template.target),
         :ok <- validate_declared_kind(template.kind, actual_kind) do
      instruction = %__MODULE__{
        kind: actual_kind,
        target: template.target,
        params: params,
        context: context,
        metadata: Map.merge(template.metadata, metadata)
      }

      case validate_resolved(instruction) do
        :ok -> {:ok, instruction}
        {:error, _error} = error -> error
      end
    end
  end

  @doc """
  Resolves a target or Instruction and applies call-site data.

  Call-site parameters and context replace equal keys from a bound Instruction.
  Resolution refreshes `kind` from the current target module.
  """
  @spec resolve(target() | t() | term(), map() | keyword() | nil, map() | keyword() | nil) ::
          {:ok, t()} | {:error, Exception.t()}
  def resolve(target_or_instruction, params \\ %{}, context \\ %{}) do
    with {:ok, params} <- normalize_map_field(params, :params),
         {:ok, context} <- normalize_map_field(context, :context),
         {:ok, instruction} <- flatten(target_or_instruction),
         {:ok, kind} <- classify(instruction.target) do
      {:ok,
       %__MODULE__{
         kind: kind,
         target: instruction.target,
         params: Map.merge(instruction.params, params),
         context: Map.merge(instruction.context, context),
         metadata: instruction.metadata
       }}
    end
  end

  @doc false
  @spec normalize!(target() | t(), map() | keyword() | nil, map() | keyword() | nil) :: t()
  def normalize!(target_or_instruction, params \\ %{}, context \\ %{}) do
    params = normalize_map!(params, :params)
    context = normalize_map!(context, :context)

    case resolve(target_or_instruction, params, context) do
      {:ok, instruction} ->
        instruction

      {:error, error} when is_exception(error) ->
        raise error

      {:error, error} ->
        raise Error.validation_error("Invalid instruction configuration", %{reason: error})
    end
  end

  @doc """
  Validates the current target contract.

  This function resolves the target again before it checks callbacks. It does
  not trust a `kind` value retained across a module reload.
  """
  @spec validate(t() | target() | term()) :: :ok | {:error, Exception.t()}
  def validate(target_or_instruction) do
    with {:ok, instruction} <- resolve(target_or_instruction) do
      validate_resolved(instruction)
    end
  end

  @doc false
  @spec validate_resolved(t()) :: :ok | {:error, Exception.t()}
  def validate_resolved(%__MODULE__{kind: :flow, target: %Flow{}}), do: :ok

  def validate_resolved(%__MODULE__{kind: kind, target: module})
      when kind in [:action, :flow] and is_atom(module) and not is_nil(module) do
    callback = if kind == :action, do: {:run, 2}, else: {:flow, 0}
    validate_module_callbacks(module, [callback, {:validate_params, 1}, {:validate_output, 1}])
  end

  def validate_resolved(%__MODULE__{} = instruction) do
    {:error,
     Error.validation_error("invalid Instruction target", %{
       instruction: instruction,
       reason: :invalid_target
     })}
  end

  @doc """
  Creates an Instruction from a map or keyword list.

  `:target` identifies an Action module, Flow module, runtime Flow value, or an
  existing Instruction. An existing Instruction is flattened. Outer parameters,
  context, and metadata replace equal inner keys.
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      attrs |> Map.new() |> new()
    else
      invalid_attributes()
    end
  end

  def new(%{} = attrs) do
    with :ok <- reject_removed_fields(attrs),
         {:ok, target} <- fetch_target(attrs),
         {:ok, params} <- normalize_map_field(Map.get(attrs, :params, %{}), :params),
         {:ok, context} <- normalize_map_field(Map.get(attrs, :context, %{}), :context),
         {:ok, metadata} <- normalize_map_field(Map.get(attrs, :metadata, %{}), :metadata),
         {:ok, instruction} <- flatten(target),
         {:ok, kind} <- classify(instruction.target),
         :ok <- validate_declared_kind(Map.get(attrs, :kind), kind) do
      {:ok,
       %__MODULE__{
         kind: kind,
         target: instruction.target,
         params: Map.merge(instruction.params, params),
         context: Map.merge(instruction.context, context),
         metadata: Map.merge(instruction.metadata, metadata)
       }}
    end
  end

  def new(_attrs), do: invalid_attributes()

  @doc "Creates an Instruction or raises on failure."
  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, instruction} ->
        instruction

      {:error, error} when is_exception(error) ->
        raise error

      {:error, error} ->
        raise Error.validation_error("Invalid instruction configuration", %{reason: error})
    end
  end

  defp flatten(%__MODULE__{} = instruction) do
    with {:ok, params} <- normalize_map_field(instruction.params, :params),
         {:ok, context} <- normalize_map_field(instruction.context, :context),
         {:ok, metadata} <- normalize_map_field(instruction.metadata, :metadata) do
      case instruction.target do
        %__MODULE__{} = inner ->
          with {:ok, inner} <- flatten(inner) do
            {:ok,
             %__MODULE__{
               kind: nil,
               target: inner.target,
               params: Map.merge(inner.params, params),
               context: Map.merge(inner.context, context),
               metadata: Map.merge(inner.metadata, metadata)
             }}
          end

        target ->
          {:ok,
           %__MODULE__{
             kind: instruction.kind,
             target: target,
             params: params,
             context: context,
             metadata: metadata
           }}
      end
    end
  end

  defp flatten(target) do
    {:ok, %__MODULE__{kind: nil, target: target, params: %{}, context: %{}, metadata: %{}}}
  end

  @doc false
  @spec target_kind(target() | term()) :: {:ok, kind()} | {:error, Exception.t()}
  def target_kind(target), do: classify(target)

  @doc false
  @spec validate_template(term()) :: :ok | {:error, Exception.t()}
  def validate_template(
        %__MODULE__{
          kind: kind,
          target: target,
          params: params,
          context: context,
          metadata: metadata
        } = template
      ) do
    cond do
      kind not in [:action, :flow] ->
        invalid_template(template, :invalid_kind)

      not (is_atom(target) and not is_nil(target)) ->
        invalid_template(template, :invalid_target)

      not (is_map(params) and map_size(params) == 0) ->
        invalid_template(template, :bound_params)

      not (is_map(context) and map_size(context) == 0) ->
        invalid_template(template, :bound_context)

      not is_map(metadata) ->
        invalid_template(template, :invalid_metadata)

      true ->
        :ok
    end
  end

  def validate_template(template), do: invalid_template(template, :invalid_template)

  defp classify(%Flow{}), do: {:ok, :flow}

  defp classify(module) when is_atom(module) and not is_nil(module) do
    case Code.ensure_compiled(module) do
      {:module, ^module} -> classify_loaded_module(module)
      {:error, reason} -> unknown_target(module, reason)
    end
  end

  defp classify(target), do: unknown_target(target, nil)

  defp classify_loaded_module(module) do
    behaviours =
      module.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    case {Jido.Action in behaviours, Jido.Flow in behaviours} do
      {true, false} -> {:ok, authored_kind(module)}
      {false, true} -> {:ok, :flow}
      {true, true} -> ambiguous_target(module)
      {false, false} -> unknown_target(module, :missing_behaviour)
    end
  end

  defp authored_kind(module) do
    if function_exported?(module, :__jido_authoring_kind__, 0) and
         module.__jido_authoring_kind__() == :flow do
      :flow
    else
      :action
    end
  end

  defp validate_declared_kind(nil, _actual), do: :ok
  defp validate_declared_kind(kind, kind), do: :ok

  defp validate_declared_kind(declared, actual) do
    {:error,
     Error.config_error("Instruction target kind does not match the current module", %{
       declared: declared,
       actual: actual,
       reason: :target_kind_changed
     })}
  end

  defp validate_module_callbacks(module, callbacks) do
    Code.ensure_loaded(module)

    Enum.reduce_while(callbacks, :ok, fn {callback, arity}, :ok ->
      if function_exported?(module, callback, arity) do
        {:cont, :ok}
      else
        {:halt, invalid_target_contract(module, "missing #{callback}/#{arity}")}
      end
    end)
  end

  defp fetch_target(%{target: target}), do: {:ok, target}

  defp fetch_target(_attrs) do
    {:error,
     Error.validation_error("Invalid instruction configuration", %{
       field: :target,
       reason: :missing
     })}
  end

  defp reject_removed_fields(attrs) do
    fields = Enum.filter(@removed_fields, &Map.has_key?(attrs, &1))

    case fields do
      [] ->
        :ok

      fields ->
        {:error,
         Error.validation_error("Removed Instruction fields are not supported", %{
           fields: fields,
           reason: :removed_instruction_fields
         })}
    end
  end

  defp normalize_map!(value, field) do
    case normalize_map_field(value, field) do
      {:ok, map} -> map
      {:error, _error} -> raise ArgumentError, normalize_map_message(value, field)
    end
  end

  defp normalize_map_field(nil, _field), do: {:ok, %{}}
  defp normalize_map_field(value, _field) when is_map(value), do: {:ok, value}

  defp normalize_map_field(value, field) when is_list(value) do
    if Keyword.keyword?(value), do: {:ok, Map.new(value)}, else: invalid_map_field(field, value)
  end

  defp normalize_map_field(value, field), do: invalid_map_field(field, value)

  defp require_map_field(value, _field) when is_map(value), do: {:ok, value}

  defp require_map_field(value, field) do
    {:error,
     Error.validation_error("Instruction binding #{field} must be a map", %{
       field: field,
       value: value,
       reason: :invalid_binding_data
     })}
  end

  defp invalid_map_field(field, value) do
    label = Atom.to_string(field)

    {:error,
     Error.validation_error(
       "Invalid #{label} format. #{String.capitalize(label)} must be a map or keyword list.",
       %{field => value, expected_format: "%{key: value} or [key: value]"}
     )}
  end

  defp normalize_map_message(value, _field) when is_list(value),
    do: "expected a map or keyword list, got: #{inspect(value)}"

  defp normalize_map_message(value, field),
    do: "expected #{field} to be a map or keyword list, got: #{inspect(value)}"

  defp invalid_attributes do
    {:error,
     Error.validation_error("Invalid instruction configuration", %{
       reason: :invalid_attributes
     })}
  end

  defp invalid_target_contract(target, reason) do
    {:error,
     Error.validation_error("module is not a valid Instruction target", %{
       target: target,
       reason: reason
     })}
  end

  defp invalid_template(template, reason) do
    {:error,
     Error.validation_error("Invalid Instruction template", %{
       template: template,
       reason: reason
     })}
  end

  defp ambiguous_target(module) do
    {:error,
     Error.config_error("Instruction target implements both Jido.Action and Jido.Flow", %{
       target: module,
       reason: :ambiguous_behaviour
     })}
  end

  defp unknown_target(target, nil) do
    {:error, Error.config_error("unknown Instruction target: #{inspect(target)}", %{target: target})}
  end

  defp unknown_target(target, reason) do
    {:error,
     Error.config_error("unknown Instruction target: #{inspect(target)}", %{
       target: target,
       reason: reason
     })}
  end
end
