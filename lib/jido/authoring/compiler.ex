defmodule Jido.Authoring.Compiler do
  @moduledoc false

  @validate_params_doc """
  Validates the input parameters for the Action.

  Runs `on_before_validate_params/1` when the Action implements it, then applies
  the input schema. Returns `{:ok, validated_params}` or `{:error, reason}`. A
  direct object or struct schema preserves unknown root keys. Nested and
  wrapped schemas use their Zoi unknown-key policy.
  """

  @validate_output_doc """
  Validates the output result for the Action.

  Returns `{:ok, validated_output}` or
  `{:error, %Jido.Action.Error.InvalidInputError{}}`. A direct object or struct
  schema preserves unknown root keys. Nested and wrapped schemas use their Zoi
  unknown-key policy. An explicit
  `Jido.Action.Output` envelope is validated as an envelope.
  """

  @doc false
  defmacro __using__(opts) do
    kind = Keyword.fetch!(opts, :kind)
    opts_ast = Keyword.fetch!(opts, :config)
    behaviour = if kind == :action, do: Jido.Action, else: Jido.Flow

    label = if kind == :action, do: "Action", else: "Flow"
    validate_params_doc = String.replace(@validate_params_doc, "Action", label)

    validate_output_doc =
      if kind == :action, do: @validate_output_doc, else: "Validates a Flow output value."

    quote location: :keep do
      @behaviour unquote(behaviour)

      @__jido_authoring_config__ unquote(opts_ast)
      @__jido_authoring_contract__ Jido.Authoring.Compiler.compile_contract(
                                     unquote(kind),
                                     @__jido_authoring_config__
                                   )

      @doc unquote("Returns the name of the #{label}.")
      @spec name() :: String.t()
      def name, do: @__jido_authoring_config__[:name]

      @doc unquote("Returns the description of the #{label}.")
      @spec description() :: String.t() | nil
      def description, do: @__jido_authoring_config__[:description]

      @doc unquote("Returns the input schema of the #{label}.")
      @spec schema() :: Jido.Action.schema()
      def schema, do: @__jido_authoring_config__[:schema]

      @doc unquote("Returns the output schema of the #{label}.")
      @spec output_schema() :: Jido.Action.schema()
      def output_schema, do: @__jido_authoring_config__[:output_schema]

      @doc unquote("""
           Returns the compile-time #{label} authoring contract as JSON-safe data.

           Raises `ArgumentError` when a declared Zoi schema has no JSON Schema
           representation. Validation and execution remain available in that case.
           """)
      @spec authoring_contract() :: map()
      def authoring_contract,
        do: Jido.Authoring.Compiler.contract!(@__jido_authoring_contract__)

      @doc unquote(validate_params_doc)
      @impl unquote(behaviour)
      @spec validate_params(term()) ::
              {:ok, map()} | {:error, term()}
      def validate_params(params), do: Jido.Action.validate_params_for(params, __MODULE__)

      @doc unquote(validate_output_doc)
      @impl unquote(behaviour)
      @spec validate_output(map() | Jido.Action.Output.t()) ::
              {:ok, map() | Jido.Action.Output.t()}
              | {:error, Jido.Action.Error.InvalidInputError.t()}
      def validate_output(output), do: Jido.Action.validate_output_for(output, __MODULE__)

      @doc false
      @spec __jido_kind__() :: :action | :flow
      def __jido_kind__, do: unquote(kind)

      @doc false
      @spec __jido_authoring__() :: Jido.Authoring.Manifest.t()
      def __jido_authoring__ do
        %{
          id: @__jido_authoring_config__[:id],
          kind: __jido_kind__(),
          vsn: @__jido_authoring_config__[:vsn],
          target: __MODULE__,
          name: name(),
          description: description()
        }
      end
    end
  end

  @doc false
  @spec compile_contract(:action | :flow, map()) ::
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
      |> Jason.encode!(maps: :strict)
      |> Jason.decode!()

    {:ok, contract}
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  @doc false
  @spec contract!({:ok, map()} | {:error, String.t()}) :: map() | no_return()
  def contract!({:ok, contract}), do: contract
  def contract!({:error, message}), do: raise(ArgumentError, message)

  defp compile_json_schema([], _option), do: nil

  defp compile_json_schema(schema, option) do
    Zoi.to_json_schema(schema)
  rescue
    exception ->
      raise ArgumentError,
            "#{inspect(option)} does not have a JSON-safe JSON Schema representation: " <>
              Exception.message(exception)
  end
end
