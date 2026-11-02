defmodule Jido.Signal.Dispatch.Adapter do
  @moduledoc """
  Defines the contract for a custom Signal dispatch adapter.

  Dispatch parses options with the adapter Zoi schema before it calls
  `deliver/2`:

      defmodule MyApp.CustomAdapter do
        @behaviour Jido.Signal.Dispatch.Adapter

        @impl true
        def options_schema do
          Zoi.keyword(
            [url: Zoi.string() |> Zoi.required()],
            unrecognized_keys: :error
          )
        end

        @impl true
        def deliver(signal, opts) do
          MyApp.Client.send(signal, Keyword.fetch!(opts, :url))
        end
      end
  """

  @doc "Returns the Zoi schema that Dispatch uses to parse adapter options."
  @callback options_schema() :: Zoi.schema()

  @doc "Delivers a Signal with options that conform to `options_schema/0`."
  @callback deliver(Jido.Signal.t(), keyword()) :: :ok | {:error, term()}
end
