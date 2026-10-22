defmodule Jido.Agent.Extension do
  @moduledoc """
  One contribution contract for Extensions and Plugins.

  `lower/2` reads Spark declarations and explicit Plugin config. `normalize/1`
  validates both Map and DSL data. `verify/2` checks references after core
  normalization. These callbacks must be deterministic and must not run work.
  `runtime_support/0` is descriptive; Agent does not activate it.
  """
  alias Jido.Agent.{Data, Error}

  @doc "Returns the stable authoring ID for this provider."
  @callback id() :: String.t()

  @doc "Returns the positive authoring version for this provider."
  @callback vsn() :: pos_integer()

  @doc "Lowers provider DSL and explicit Plugin configuration into provider data."
  @callback lower(map(), map()) :: {:ok, map()} | {:error, term()}

  @doc "Normalizes provider data from any authoring path."
  @callback normalize(map()) :: {:ok, map()} | {:error, term()}

  @doc "Checks provider data against the complete Agent definition."
  @callback verify(map(), map()) :: :ok | {:error, term()}

  @doc "Names the optional runtime Plugin adapter for this provider."
  @callback runtime_support() :: :none | module()

  @doc "Returns the logical endpoint kinds owned by this provider."
  @callback endpoint_kinds() :: [atom()]

  @doc "Returns the logical endpoints contributed by normalized provider data."
  @callback endpoints(map()) :: [map()]

  @doc "Returns modules that `use Jido.Agent` imports for this provider."
  @callback authoring_imports() :: [module()]

  @doc "Checks one logical connection that references provider endpoints."
  @callback verify_connection(map(), map()) :: :ok | {:error, term()}

  @doc "Defines one Agent authoring provider and its default callbacks."
  defmacro __using__(opts) do
    kind = Keyword.get(opts, :kind, :extension)

    quote do
      @behaviour Jido.Agent.Extension
      use Spark.Dsl.Extension, sections: unquote(Keyword.get(opts, :sections, []))
      def id, do: unquote(Keyword.fetch!(opts, :id))
      def vsn, do: unquote(Keyword.get(opts, :vsn, 1))

      @doc false
      def __jido_authoring__ do
        %{id: id(), kind: unquote(kind), vsn: vsn(), target: __MODULE__}
      end

      def lower(_dsl, config), do: {:ok, config}

      def normalize(data) do
        with :ok <- Jido.Agent.Data.plain_map(data),
             :ok <- Jido.Agent.Data.static(data),
             do: {:ok, data}
      end

      def verify(_data, _definition), do: :ok
      def runtime_support, do: :none
      def authoring_imports, do: []
      def endpoint_kinds, do: []
      def endpoints(_data), do: []
      def verify_connection(_data, _connection), do: :ok

      defoverridable lower: 2,
                     normalize: 1,
                     verify: 2,
                     runtime_support: 0,
                     authoring_imports: 0,
                     endpoint_kinds: 0,
                     endpoints: 1,
                     verify_connection: 2
    end
  end

  @doc false
  def providers(providers) do
    with {:ok, providers} <- Data.list(providers, &provider/1),
         :ok <- Data.unique(providers, & &1),
         :ok <- Data.unique(providers, & &1.id()),
         :ok <- namespaces(providers) do
      {:ok, providers}
    end
  end

  @doc false
  def provider(module) when is_atom(module) and module not in [nil, true, false] do
    callbacks = [{:sections, 0} | __MODULE__.behaviour_info(:callbacks)]

    if match?({:module, _}, Code.ensure_compiled(module)) and
         Enum.all?(callbacks, fn {f, a} -> function_exported?(module, f, a) end) do
      with :ok <- Data.nonempty(module.id()),
           :ok <- Data.positive(module.vsn()),
           do: {:ok, module}
    else
      Error.fail(
        :invalid_provider,
        [],
        "Provider #{inspect(module)} does not implement the Agent contribution contract",
        %{provider: module}
      )
    end
  end

  def provider(value),
    do: Error.fail(:invalid_provider, [], "Expected a provider module", %{provider: value})

  @doc false
  def normalize(entries) do
    with {:ok, entries} <- Data.list(entries, &entry/1),
         {:ok, _} <- providers(Enum.map(entries, & &1.provider)),
         do: {:ok, entries}
  end

  defp entry(value) do
    with {:ok, value} <- Data.fields(value, [:id, :provider, :vsn, :data]),
         {:ok, provider} <- provider(value[:provider]),
         :ok <- identity(value, provider),
         :ok <- Data.plain_map(value[:data]),
         {:ok, data} <- result(provider.normalize(value.data)),
         :ok <- Data.plain_map(data),
         :ok <- Data.static(data) do
      {:ok, %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: data}}
    end
  end

  defp identity(value, provider) do
    if value[:id] === provider.id() and value[:vsn] === provider.vsn(),
      do: :ok,
      else:
        Error.fail(:provider_identity, [], "Provider ID or version does not match its contract")
  end

  @doc false
  def lower(providers, dsl, plugins) do
    with :ok <- Data.plain_map(dsl),
         :ok <- Data.plain_map(plugins),
         {:ok, providers} <- providers(providers) do
      Data.list(providers, fn provider ->
        config = Map.get(plugins, provider, %{})

        with :ok <- Data.plain_map(config),
             {:ok, data} <- result(provider.lower(dsl, config)) do
          {:ok, %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: data}}
        end
      end)
    end
  end

  @doc false
  def verify(entries, definition) do
    with {:ok, _} <-
           Data.list(entries, fn entry ->
             with :ok <- result(entry.provider.verify(entry.data, definition)), do: {:ok, entry}
           end),
         do: :ok
  end

  @doc false
  def endpoints(entries), do: Enum.flat_map(entries, & &1.provider.endpoints(&1.data))

  @doc false
  def verify_connection(entries, connection) do
    with {:ok, _} <-
           Data.list(entries, fn entry ->
             with :ok <- result(entry.provider.verify_connection(entry.data, connection)),
                  do: {:ok, entry}
           end),
         do: :ok
  end

  defp namespaces(providers) do
    sections =
      Enum.flat_map(providers, fn provider -> Enum.map(provider.sections(), & &1.name) end)

    kinds = Enum.flat_map(providers, & &1.endpoint_kinds())

    cond do
      Enum.any?(
        sections,
        &(&1 in [:agent, :routes, :topology, :__agent__, :__routes__, :__topology__])
      ) ->
        Error.fail(:namespace_conflict, [], "Provider cannot replace a core section")

      :agent in kinds ->
        Error.fail(:namespace_conflict, [], "Provider cannot replace agent endpoints")

      true ->
        with :ok <- Data.unique(sections, & &1), do: Data.unique(kinds, & &1)
    end
  end

  defp result({:error, %Error{}} = error), do: error

  defp result({:error, reason}),
    do:
      Error.fail(:provider_error, [], "Provider rejected its data: #{inspect(reason)}", %{
        reason: reason
      })

  defp result(result), do: result
end
