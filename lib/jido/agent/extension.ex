defmodule Jido.Agent.Extension do
  @moduledoc false
  alias Jido.Agent.{Data, Error, Route}
  alias Jido.Authoring.{Registry, Value}

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

  @doc "Returns the logical endpoint kinds owned by this provider."
  @callback endpoint_kinds() :: [atom()]

  @doc "Returns the logical endpoints contributed by normalized provider data."
  @callback endpoints(map()) :: [map()]

  @doc "Derives exact Agent routes from normalized provider data."
  @callback derive_routes(map()) :: [map()]

  @doc "Checks one logical connection that references provider endpoints."
  @callback verify_connection(map(), map()) :: :ok | {:error, term()}

  @doc "Encodes normalized provider data for an Agent authoring document."
  @callback encode_authoring_data(map(), Registry.t()) ::
              {:ok, term()} | {:error, term()}

  @doc "Decodes provider data from an Agent authoring document."
  @callback decode_authoring_data(term(), Registry.t()) ::
              {:ok, term()} | {:error, term()}

  @optional_callbacks encode_authoring_data: 2, decode_authoring_data: 2, derive_routes: 1

  @doc "Defines one Agent authoring provider and its default callbacks."
  defmacro __using__(opts) do
    quote do
      @behaviour Jido.Agent.Extension
      use Spark.Dsl.Extension,
        sections: unquote(Keyword.get(opts, :sections, [])),
        imports: unquote(Keyword.get(opts, :imports, []))

      def id, do: unquote(Keyword.fetch!(opts, :id))
      def vsn, do: unquote(Keyword.get(opts, :vsn, 1))

      @doc false
      def __jido_authoring__ do
        %{id: id(), kind: :plugin, vsn: vsn(), target: __MODULE__}
      end

      def lower(_dsl, config), do: {:ok, config}

      def normalize(data) do
        with :ok <- Jido.Agent.Data.plain_map(data),
             :ok <- Jido.Agent.Data.static(data),
             do: {:ok, data}
      end

      def verify(_data, _definition), do: :ok
      def derive_routes(_data), do: []
      def endpoint_kinds, do: []
      def endpoints(_data), do: []
      def verify_connection(_data, _connection), do: :ok

      def encode_authoring_data(data, registry),
        do: Jido.Authoring.Value.encode(data, registry)

      def decode_authoring_data(data, registry),
        do: Jido.Authoring.Value.decode(data, registry)

      defoverridable lower: 2,
                     normalize: 1,
                     verify: 2,
                     derive_routes: 1,
                     endpoint_kinds: 0,
                     endpoints: 1,
                     verify_connection: 2,
                     encode_authoring_data: 2,
                     decode_authoring_data: 2
    end
  end

  @doc false
  @spec encode_authoring_data(module(), map(), Registry.t()) ::
          {:ok, term()} | {:error, term()}
  def encode_authoring_data(provider, data, %Registry{} = registry) do
    authoring_data(provider, :encode_authoring_data, data, registry, &Value.encode/2)
  end

  @doc false
  @spec decode_authoring_data(module(), term(), Registry.t()) ::
          {:ok, term()} | {:error, term()}
  def decode_authoring_data(provider, data, %Registry{} = registry) do
    authoring_data(provider, :decode_authoring_data, data, registry, &Value.decode/2)
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
    required_callbacks =
      __MODULE__.behaviour_info(:callbacks) -- __MODULE__.behaviour_info(:optional_callbacks)

    callbacks = [{:sections, 0}, {:__jido_authoring__, 0} | required_callbacks]

    if match?({:module, _}, Code.ensure_compiled(module)) and
         Enum.all?(callbacks, fn {f, a} -> function_exported?(module, f, a) end) do
      with :ok <- Data.nonempty(module.id()),
           :ok <- Data.positive(module.vsn()),
           :ok <- plugin(module),
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

  defp plugin(module) do
    authoring = module.__jido_authoring__()
    expected = %{id: module.id(), kind: :plugin, target: module, vsn: module.vsn()}

    if Jido.Plugin in behaviours(module) and authoring === expected do
      :ok
    else
      Error.fail(
        :invalid_plugin,
        [],
        "Agent plugins must use Jido.Plugin",
        %{plugin: module}
      )
    end
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

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
  def lower(declarations, dsl) do
    with :ok <- Data.plain_map(dsl),
         {:ok, declarations} <-
           Data.list(declarations, fn declaration ->
             with {:ok, declaration} <- Data.fields(declaration, [:provider, :config]),
                  {:ok, provider} <- provider(declaration[:provider]),
                  :ok <- Data.plain_map(declaration[:config]) do
               {:ok, %{provider: provider, config: declaration.config}}
             end
           end) do
      Data.list(declarations, fn %{provider: provider, config: config} ->
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
  def route_contributions(entries) do
    with {:ok, groups} <-
           Data.list(entries, fn entry ->
             routes =
               if function_exported?(entry.provider, :derive_routes, 1),
                 do: entry.provider.derive_routes(entry.data),
                 else: []

             with {:ok, routes} <-
                    Error.at(
                      Data.list(routes, fn route ->
                        with :ok <- Data.plain_map(route),
                             :ok <- Error.at(Data.exact(Map.get(route, :path)), :path),
                             do: {:ok, route}
                      end),
                      :routes
                    ) do
               {:ok,
                routes
                |> Enum.with_index()
                |> Enum.map(fn {route, index} ->
                  %{provider: entry.provider, route: route, index: index}
                end)}
             end
           end) do
      {:ok,
       groups
       |> Enum.with_index()
       |> Enum.flat_map(fn {routes, plugin_index} ->
         Enum.map(routes, &Map.put(&1, :plugin_index, plugin_index))
       end)}
    end
  end

  @doc false
  def stored_routes(entries, routes) do
    with {:ok, contributions} <- route_contributions(entries),
         {:ok, contributions} <- normalize_derived_routes(contributions) do
      remove_derived_routes(routes, contributions)
    end
  end

  defp normalize_derived_routes(contributions) do
    Data.list(contributions, fn contribution ->
      with {:ok, route} <- Error.at(Route.normalize(contribution.route), route_path(contribution)),
           do: {:ok, %{contribution | route: route}}
    end)
  end

  defp remove_derived_routes(routes, contributions) do
    Enum.reduce_while(contributions, {:ok, routes}, fn contribution, {:ok, routes} ->
      case Enum.find_index(routes, &(&1 === contribution.route)) do
        nil ->
          {:halt,
           Error.fail(
             :missing_derived_route,
             route_path(contribution),
             "Agent definition is missing a route derived by a Plugin",
             %{path: contribution.route.path, provider: contribution.provider}
           )}

        index ->
          {:cont, {:ok, List.delete_at(routes, index)}}
      end
    end)
  end

  defp route_path(contribution) do
    [:plugins, contribution.plugin_index, :routes, contribution.index]
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
        &(&1 in ~w(agent state routes topology __state__ __routes__ __topology__)a)
      ) ->
        Error.fail(:namespace_conflict, [], "Provider cannot replace a core section")

      :agent in kinds ->
        Error.fail(:namespace_conflict, [], "Provider cannot replace agent endpoints")

      true ->
        with :ok <- Data.unique(sections, & &1), do: Data.unique(kinds, & &1)
    end
  end

  defp authoring_data(provider, callback, data, registry, fallback) do
    result =
      if function_exported?(provider, callback, 2),
        do: apply(provider, callback, [data, registry]),
        else: fallback.(data, registry)

    case result do
      {:ok, _value} = success ->
        success

      {:error, _error} = error ->
        error

      other ->
        Error.fail(
          :provider_authoring_data,
          [],
          "Provider authoring callback returned an invalid value",
          %{provider: provider, callback: callback, value: other}
        )
    end
  rescue
    exception ->
      Error.fail(
        :provider_authoring_data,
        [],
        "Provider authoring callback failed",
        %{provider: provider, callback: callback, reason: Exception.message(exception)}
      )
  catch
    kind, reason ->
      Error.fail(
        :provider_authoring_data,
        [],
        "Provider authoring callback failed",
        %{provider: provider, callback: callback, failure_kind: kind, reason: inspect(reason)}
      )
  end

  defp result({:error, %Error{}} = error), do: error

  defp result({:error, reason}),
    do:
      Error.fail(:provider_error, [], "Provider rejected its data: #{inspect(reason)}", %{
        reason: reason
      })

  defp result(result), do: result
end
