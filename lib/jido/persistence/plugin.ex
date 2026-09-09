defmodule Jido.Persistence.Plugin do
  @moduledoc """
  Pure Persistence-owned facet of a `Jido.Plugin` package.

  This facet converts only its paired Plugin-owned state value. It receives no
  adapter, record key, revision check, complete Agent state, process, or commit
  result. `Jido.Persistence` owns when the conversion runs.
  """

  alias Jido.Persistence.Plugin.{Context, Spec}
  alias Jido.Plugin.Error, as: PluginError

  @doc "Defines a Persistence-owned Plugin facet."
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Jido.Persistence.Plugin

      @doc false
      def __jido_plugin_facet__, do: :persistence
    end
  end

  @callback dump(owned_state :: term(), context :: Context.t(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback load(stored_value :: term(), context :: Context.t(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}

  @doc false
  @spec dump(Jido.Plugin.Spec.t(), term(), Context.t()) :: {:ok, term()} | {:error, term()}
  def dump(%{persistence: %Spec{} = spec}, value, %Context{direction: :dump} = context) do
    with {:ok, context} <- Context.validate(context),
         :ok <- validate_context(context, spec, :dump),
         result <-
           PluginError.safe_apply(
             spec.package,
             spec.module,
             :dump,
             [value, context, spec.options],
             "Persistence Plugin dump/3 failed"
           ),
         {:ok, dumped} <- callback_value(result, spec, :dump),
         :ok <- portable(dumped, spec, :dump) do
      {:ok, dumped}
    end
  end

  @doc false
  @spec load(Jido.Plugin.Spec.t(), term(), Context.t()) :: {:ok, term()} | {:error, term()}
  def load(
        %{agent: %{state_schema: state_schema}, persistence: %Spec{} = spec},
        value,
        %Context{direction: :load} = context
      ) do
    with {:ok, context} <- Context.validate(context),
         :ok <- validate_context(context, spec, :load),
         result <-
           PluginError.safe_apply(
             spec.package,
             spec.module,
             :load,
             [value, context, spec.options],
             "Persistence Plugin load/3 failed"
           ),
         {:ok, loaded} <- callback_value(result, spec, :load),
         :ok <- portable(loaded, spec, :load),
         {:ok, validated} <- validate_state(loaded, state_schema, spec) do
      {:ok, validated}
    end
  end

  @doc false
  @spec context(Jido.Plugin.Spec.t(), :dump | :load, pos_integer(), term()) :: Context.t()
  def context(%{persistence: %Spec{} = spec}, direction, record_format, reason)
      when direction in [:dump, :load] and is_integer(record_format) and record_format > 0 do
    %Context{
      plugin: spec.package,
      plugin_vsn: spec.vsn,
      record_format: record_format,
      direction: direction,
      reason: reason
    }
  end

  defp callback_value({:ok, value}, _spec, _callback), do: {:ok, value}
  defp callback_value({:error, _reason} = error, _spec, _callback), do: error

  defp callback_value(result, spec, callback) do
    PluginError.invalid_callback(
      "Persistence Plugin callback returned an invalid result",
      spec.package,
      spec.module,
      %{callback: callback, result: result}
    )
  end

  defp portable(value, spec, callback) do
    case Jido.PortableTerm.validate(value, [:plugin_state, spec.package]) do
      :ok ->
        :ok

      {:error, path} ->
        PluginError.invalid_callback(
          "Persistence Plugin returned a non-portable value",
          spec.package,
          spec.module,
          %{callback: callback, code: :non_portable_term, path: path}
        )
    end
  end

  defp validate_state(value, schema, spec) do
    case Zoi.parse(schema, value) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, errors} ->
        PluginError.invalid_callback(
          "Persistence Plugin loaded invalid owned state",
          spec.package,
          spec.module,
          %{errors: errors}
        )
    end
  end

  defp validate_context(
         %Context{plugin: package, plugin_vsn: vsn, direction: direction},
         %Spec{package: package, vsn: vsn},
         direction
       ),
       do: :ok

  defp validate_context(context, spec, direction) do
    PluginError.validation("Persistence Plugin context does not match its owner", %{
      plugin: spec.package,
      facet: spec.module,
      direction: direction,
      context: context
    })
  end
end
