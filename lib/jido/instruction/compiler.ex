defmodule Jido.Instruction.Compiler do
  @moduledoc false

  @validate_params_doc """
  Validates the input parameters for the Action.

  Runs `on_before_validate_params/1` when the Action implements it, then applies
  the input schema. Returns `{:ok, validated_params}` or `{:error, reason}`.
  Direct, nested, and wrapped schemas use their declared Joi unknown-key policy.
  """

  @validate_output_doc """
  Validates the output result for the Action.

  Returns `{:ok, validated_output}` or
  `{:error, %Jido.Error.ValidationError{}}`. Direct, nested, and wrapped
  schemas use their declared Joi unknown-key policy. An explicit
  `Jido.Action.Output` envelope is validated as an envelope.
  """

  @doc false
  defmacro __using__(opts) do
    kind = Keyword.fetch!(opts, :kind)
    opts_ast = Keyword.fetch!(opts, :config)

    label = if kind == :action, do: "Action", else: "Flow"
    validate_params_doc = String.replace(@validate_params_doc, "Action", label)

    validate_output_doc =
      if kind == :action, do: @validate_output_doc, else: "Validates a Flow output value."

    quote location: :keep do
      @behaviour Jido.Action

      @__jido_codec_config__ unquote(opts_ast)
      @__jido_codec_contract__ Jido.Instruction.Compiler.compile_contract(
                                 unquote(kind),
                                 @__jido_codec_config__
                               )

      @doc unquote("Returns the name of the #{label}.")
      @spec name() :: String.t()
      def name, do: @__jido_codec_config__[:name]

      @doc unquote("Returns the description of the #{label}.")
      @spec description() :: String.t() | nil
      def description, do: @__jido_codec_config__[:description]

      @doc unquote("Returns the input schema of the #{label}.")
      @spec schema() :: Jido.Action.schema()
      def schema, do: @__jido_codec_config__[:schema]

      @doc unquote("Returns the output schema of the #{label}.")
      @spec output_schema() :: Jido.Action.schema()
      def output_schema, do: @__jido_codec_config__[:output_schema]

      @doc unquote("""
           Returns the compile-time #{label} authoring contract as JSON-safe data.

           Raises `ArgumentError` when a declared Joi schema has no JSON Schema
           representation. Validation and execution remain available in that case.
           """)
      @spec authoring_contract() :: map()
      def authoring_contract,
        do: Jido.Instruction.Compiler.contract!(@__jido_codec_contract__)

      @doc unquote(validate_params_doc)
      @impl Jido.Action
      @spec validate_params(term()) ::
              {:ok, map()} | {:error, term()}
      def validate_params(params), do: Jido.Action.validate_params_for(params, __MODULE__)

      @doc unquote(validate_output_doc)
      @impl Jido.Action
      @spec validate_output(map() | Jido.Action.Output.t()) ::
              {:ok, map() | Jido.Action.Output.t()}
              | {:error, Jido.Error.ValidationError.t()}
      def validate_output(output), do: Jido.Action.validate_output_for(output, __MODULE__)

      @doc false
      @spec __jido_codec_kind__() :: Jido.Instruction.kind()
      def __jido_codec_kind__, do: unquote(kind)

      @doc false
      @spec __jido_catalog_manifest__() :: [map()]
      def __jido_catalog_manifest__ do
        [
          %{id: @__jido_codec_config__[:id], vsn: @__jido_codec_config__[:vsn], target: __MODULE__},
          %{name: :schema, target: schema()},
          %{name: :output_schema, target: output_schema()}
        ]
      end
    end
  end

  @doc false
  @spec compile_contract(Jido.Instruction.kind(), map()) ::
          {:ok, map()} | {:error, String.t()}
  def compile_contract(kind, opts) do
    contract =
      %{
        "id" => Map.fetch!(opts, :id),
        "vsn" => Map.fetch!(opts, :vsn),
        "kind" => Atom.to_string(kind),
        "name" => Map.fetch!(opts, :name),
        "description" => Map.get(opts, :description),
        "input_schema" => compile_json_schema(opts.schema, :schema),
        "output_schema" => compile_json_schema(opts.output_schema, :output_schema)
      }
      |> strict_json_encode!()
      |> JSON.decode!()

    {:ok, contract}
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  @doc false
  @spec contract!({:ok, map()} | {:error, String.t()}) :: map() | no_return()
  def contract!({:ok, contract}), do: contract
  def contract!({:error, message}), do: raise(ArgumentError, message)

  defp compile_json_schema(schema, option) do
    Jido.Joi.to_json_schema(schema)
  rescue
    exception ->
      raise ArgumentError,
            "#{inspect(option)} does not have a JSON-safe JSON Schema representation: " <>
              Exception.message(exception)
  end

  defp strict_json_encode!(value) do
    ensure_unique_json_keys!(value)
    JSON.encode!(value)
  end

  defp ensure_unique_json_keys!(value) when is_list(value) do
    Enum.each(value, &ensure_unique_json_keys!/1)
  end

  defp ensure_unique_json_keys!(value) when is_map(value) and not is_struct(value) do
    names = Enum.map(Map.keys(value), &to_string/1)

    if length(names) != MapSet.size(MapSet.new(names)),
      do: raise(ArgumentError, "JSON object contains colliding keys")

    Enum.each(Map.values(value), &ensure_unique_json_keys!/1)
  end

  defp ensure_unique_json_keys!(_value), do: :ok
end
