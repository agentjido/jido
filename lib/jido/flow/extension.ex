defmodule Jido.Flow.Extension do
  @moduledoc """
  Defines compile-time macro extensions for the Flow module DSL.

  An extension adds authoring macros to `flow do`. Each macro must expand to
  normal Flow declarations. It does not add a component type, change the
  canonical `%Jido.Flow{}` value, or add runtime behavior.

      defmodule MyApp.Flows.Helpers do
        use Jido.Flow.Extension

        defmacro notify(name, address) do
          quote do
            step unquote(name),
              action: MyApp.Actions.Notify,
              params: %{address: unquote(address)}
          end
        end
      end

      defmodule MyApp.Flows.Welcome do
        use Jido.Flow,
          name: "welcome",
          extensions: [MyApp.Flows.Helpers]

        flow do
          notify "welcome", input(:address)
          output result("welcome")
        end
      end

  Extension macros run during normal Flow compilation. The expanded core
  declarations keep the usual validation, source mapping, inline Action, and
  execution rules. Extension modules must be available at compile time.

  Only the module DSL loads extensions. Map-based definitions and direct construction use
  normal Elixir functions that create canonical Flow data. Codec documents
  contain data only and never load or run an extension. Keep the public API of
  an extension module limited to macros. Put data definition helpers in another module.
  """

  @doc false
  @callback __jido_flow_extension__() :: true

  @doc "Installs the Flow extension contract and imports this module into configured Flows."
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(options) do
    unless options == [] do
      raise ArgumentError, "Jido.Flow.Extension does not accept options"
    end

    extension = __CALLER__.module

    quote do
      @behaviour Jido.Flow.Extension
      use Spark.Dsl.Extension, imports: [unquote(extension)]

      @doc false
      @impl Jido.Flow.Extension
      @spec __jido_flow_extension__() :: true
      def __jido_flow_extension__, do: true
    end
  end
end
