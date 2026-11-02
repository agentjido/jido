defmodule Jido.Instruction do
  @moduledoc """
  Defines one Action or Flow invocation.

  An Instruction contains only the target and its call data:

      %Jido.Instruction{
        target: MyApp.SendEmail,
        params: %{to: "user@example.com"},
        context: %{tenant_id: "tenant_123"},
        metadata: %{correlation_id: "req_123"}
      }

  Compact single-call forms can be normalized when the complete struct syntax
  is not useful:

      Jido.Instruction.normalize(MyApp.SendEmail)
      Jido.Instruction.normalize({MyApp.SendEmail, %{to: "user@example.com"}})
      Jido.Instruction.normalize({MyApp.SendEmail, %{}, %{tenant_id: "tenant_123"}})

  Normalization accepts one Instruction only. It does not flatten lists or
  add execution policy.

  `params` and `context` are passed to the target. `metadata` contains
  caller-supplied invocation annotations for execution infrastructure. It is
  not passed to an Action callback.

  Instruction does not load a Flow definition, inspect executable callbacks,
  merge nested Instructions, or resolve stored references. The execution
  boundary owns executable validation. `Jido.Discovery` and
  `Jido.Authoring.Registry` own stored target resolution.

  Target type is derived when it is needed. Generated Action and Flow modules
  expose the internal `__jido_kind__/0` marker. Runtime Flow values expose the
  same marker through their struct module. The derived type is not retained in
  the Instruction.
  """

  @typedoc "An Action module, Flow module, or runtime Flow value."
  @type target :: module() | struct()
  @typedoc "The derived executable target type."
  @type target_kind :: :action | :flow
  @typedoc "Action or Flow input parameters."
  @type params :: map()
  @typedoc "Caller-supplied execution context."
  @type context :: map()
  @typedoc "Caller-supplied invocation annotations used by execution infrastructure."
  @type metadata :: map()
  @typedoc "Map-shaped call data accepted by compact Instruction forms."
  @type call_data :: map() | keyword() | nil
  @typedoc "One complete Action or Flow invocation."
  @type t :: %__MODULE__{
          target: target(),
          params: params(),
          context: context(),
          metadata: metadata()
        }
  @typedoc "A compact or complete single Instruction value."
  @type input ::
          target()
          | {target(), call_data()}
          | {target(), call_data(), call_data()}
          | {target(), call_data(), call_data(), call_data()}
          | t()

  @enforce_keys [:target]
  defstruct target: nil, params: %{}, context: %{}, metadata: %{}

  # Atom literals keep this foundational module out of the Action and Flow
  # compile graph while still supporting hand-written behaviour modules.
  @action_behaviour :"Elixir.Jido.Action"
  @flow_behaviour :"Elixir.Jido.Flow"

  defmodule Error do
    @moduledoc "An invalid Instruction or Instruction target."

    defexception message: "Invalid Instruction", details: %{}

    @type t :: %__MODULE__{message: String.t(), details: map()}
  end

  @doc "Creates an Instruction from named call data."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs), do: attrs |> Map.new() |> new(), else: invalid_attributes()
  end

  def new(%{} = attrs) when not is_struct(attrs) do
    with :ok <- validate_fields(attrs),
         {:ok, target} <- fetch_target(attrs),
         :ok <- validate_target_shape(target),
         {:ok, params} <- normalize_map(Map.get(attrs, :params, %{}), :params),
         {:ok, context} <- normalize_map(Map.get(attrs, :context, %{}), :context),
         {:ok, metadata} <- normalize_map(Map.get(attrs, :metadata, %{}), :metadata) do
      {:ok,
       %__MODULE__{
         target: target,
         params: params,
         context: context,
         metadata: metadata
       }}
    end
  end

  def new(_attrs), do: invalid_attributes()

  @doc """
  Normalizes one compact or complete Instruction value.

  Accepted compact values are a direct target, `{target, params}`,
  `{target, params, context}`, and
  `{target, params, context, metadata}`. Call data accepts the same maps,
  keyword lists, and `nil` values as `new/1`.

  This function accepts one Instruction only. A list is not an Instruction
  sequence and is rejected.
  """
  @spec normalize(input()) :: {:ok, t()} | {:error, Error.t()}
  def normalize(%__MODULE__{} = instruction),
    do: instruction |> Map.from_struct() |> new()

  def normalize({target, params}),
    do: new(target: target, params: params)

  def normalize({target, params, context}),
    do: new(target: target, params: params, context: context)

  def normalize({target, params, context, metadata}),
    do: new(target: target, params: params, context: context, metadata: metadata)

  def normalize(target) when is_atom(target) or is_struct(target),
    do: new(target: target)

  def normalize(input) do
    error("Instruction input must contain one target and its call data", %{
      input: input,
      reason: :input
    })
  end

  @doc "Normalizes one compact or complete Instruction value or raises its validation error."
  @spec normalize!(input()) :: t() | no_return()
  def normalize!(input) do
    case normalize(input) do
      {:ok, instruction} -> instruction
      {:error, error} -> raise error
    end
  end

  @doc "Creates an Instruction or raises its validation error."
  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, instruction} -> instruction
      {:error, error} -> raise error
    end
  end

  @doc "Returns the target type derived from an Instruction or target."
  @spec target_kind(t() | target() | term()) ::
          {:ok, target_kind()} | {:error, Error.t()}
  def target_kind(%__MODULE__{target: target}), do: target_kind(target)

  def target_kind(%{__struct__: module} = target) when is_atom(module),
    do: ensure_module_kind(module, target)

  def target_kind(module) when is_atom(module) and module not in [nil, true, false] do
    ensure_module_kind(module, module)
  end

  def target_kind(target), do: target_error(target, :invalid_target)

  defp ensure_module_kind(module, target) do
    case Code.ensure_compiled(module) do
      {:module, ^module} -> module_kind(module, target)
      {:error, reason} -> target_error(target, reason)
    end
  end

  defp module_kind(module, target) do
    if function_exported?(module, :__jido_kind__, 0) do
      call_kind(module, target)
    else
      behaviour_kind(module, target)
    end
  end

  defp behaviour_kind(module, target) do
    behaviours =
      module.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    case {@action_behaviour in behaviours, @flow_behaviour in behaviours} do
      {true, false} -> {:ok, :action}
      {false, true} -> {:ok, :flow}
      {true, true} -> target_error(target, :ambiguous_behaviour)
      {false, false} -> target_error(target, :missing_kind)
    end
  end

  defp call_kind(module, target) do
    case module.__jido_kind__() do
      kind when kind in [:action, :flow] -> {:ok, kind}
      kind -> target_error(target, {:invalid_kind, kind})
    end
  rescue
    error -> target_error(target, {:kind_failure, :error, error})
  catch
    kind, reason -> target_error(target, {:kind_failure, kind, reason})
  end

  defp validate_fields(attrs) do
    case Map.keys(attrs) -- [:target, :params, :context, :metadata] do
      [] -> :ok
      fields -> error("Instruction contains unknown fields", %{fields: Enum.sort(fields)})
    end
  end

  defp fetch_target(%{target: target}), do: {:ok, target}
  defp fetch_target(_attrs), do: error("Instruction target is required", %{field: :target})

  defp validate_target_shape(%__MODULE__{} = target),
    do: error("Instruction target cannot be another Instruction", %{target: target})

  defp validate_target_shape(target)
       when is_atom(target) and target not in [nil, true, false],
       do: :ok

  defp validate_target_shape(target) when is_struct(target), do: :ok

  defp validate_target_shape(target),
    do: error("Instruction target must be a module or struct", %{target: target})

  defp normalize_map(nil, _field), do: {:ok, %{}}
  defp normalize_map(value, _field) when is_map(value), do: {:ok, value}

  defp normalize_map(value, field) when is_list(value) do
    if Keyword.keyword?(value),
      do: {:ok, Map.new(value)},
      else: error("Instruction #{field} must be a map or keyword list", %{field: field})
  end

  defp normalize_map(_value, field),
    do: error("Instruction #{field} must be a map or keyword list", %{field: field})

  defp invalid_attributes,
    do: error("Instruction attributes must be a map or keyword list", %{reason: :attributes})

  defp target_error(target, reason),
    do: error("Instruction target is not an Action or Flow", %{target: target, reason: reason})

  defp error(message, details), do: {:error, Error.exception(message: message, details: details)}
end
