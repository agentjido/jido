defmodule Jido.Action.Compiler do
  @moduledoc false

  @doc false
  defmacro __using__(opts) do
    config = Keyword.fetch!(opts, :config)

    quote location: :keep do
      @behaviour Jido.Action
      @__jido_authoring_config__ unquote(config)
      @__jido_authoring_contract__ Jido.Authoring.Compiler.compile_contract(
                                     :action,
                                     @__jido_authoring_config__
                                   )

      @doc "Returns the name of the Action."
      @spec name() :: String.t()
      def name, do: @__jido_authoring_config__[:name]

      @doc "Returns the description of the Action."
      @spec description() :: String.t() | nil
      def description, do: @__jido_authoring_config__[:description]

      @doc "Returns the input schema of the Action."
      @spec schema() :: Jido.Action.schema()
      def schema, do: @__jido_authoring_config__[:schema]

      @doc "Returns the output schema of the Action."
      @spec output_schema() :: Jido.Action.schema()
      def output_schema, do: @__jido_authoring_config__[:output_schema]

      @doc "Returns the compile-time Action authoring contract as JSON-safe data."
      @spec authoring_contract() :: map()
      def authoring_contract,
        do: Jido.Authoring.Compiler.contract!(@__jido_authoring_contract__)

      @doc "Validates input parameters for the Action."
      @impl Jido.Action
      @spec validate_params(term()) :: {:ok, map()} | {:error, term()}
      def validate_params(params), do: Jido.Action.validate_params_for(params, __MODULE__)

      @doc "Validates an Action output value."
      @impl Jido.Action
      @spec validate_output(map() | Jido.Action.Output.t()) ::
              {:ok, map() | Jido.Action.Output.t()}
              | {:error, Jido.Action.Error.InvalidInputError.t()}
      def validate_output(output), do: Jido.Action.validate_output_for(output, __MODULE__)

      @doc false
      @spec __jido_kind__() :: :action
      def __jido_kind__, do: :action

      @doc false
      @spec __jido_authoring__() :: Jido.Authoring.Manifest.t()
      def __jido_authoring__ do
        %{
          id: @__jido_authoring_config__[:id],
          kind: :action,
          vsn: @__jido_authoring_config__[:vsn],
          target: __MODULE__,
          name: name(),
          description: description()
        }
      end
    end
  end
end
