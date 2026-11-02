defmodule Jido.Signal.Dispatch.Adapter do
  alias Jido.Joi

  @moduledoc """
  Defines the contract for a custom Signal dispatch adapter.

  Dispatch parses options with the adapter Joi schema before it calls
  `deliver/2`:

      defmodule MyApp.CustomAdapter do
        @behaviour Jido.Signal.Dispatch.Adapter

        @impl true
        def options_schema do
          Joi.keyword(
            [url: Joi.string() |> Joi.required()],
            unrecognized_keys: :error
          )
        end

        @impl true
        def deliver(signal, opts) do
          MyApp.Client.send(signal, Keyword.fetch!(opts, :url))
        end
      end
  """

  @doc "Returns the Joi schema that Dispatch uses to parse adapter options."
  @callback options_schema() :: Joi.schema()

  @doc "Delivers a Signal with options that conform to `options_schema/0`."
  @callback deliver(Jido.Signal.t(), keyword()) :: :ok | {:error, term()}
end
