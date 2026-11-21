defmodule Jido.Agent.Extension do
  @moduledoc false
  alias Jido.Agent.{Callback, Route, Schema}
  alias Jido.Error
  alias Jido.Catalog
  alias Jido.Codec.Value

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
  @callback encode_authoring_data(map(), Catalog.source()) ::
              {:ok, term()} | {:error, term()}

  @doc "Decodes provider data from an Agent authoring document."
  @callback decode_authoring_data(term(), Catalog.source()) ::
              {:ok, term()} | {:error, term()}

  @optional_callbacks encode_authoring_data: 2, decode_authoring_data: 2, derive_routes: 1

  @doc "Defines one Agent authoring provider and its default callbacks."
  defmacro __using__(opts) do
    quote do
      @behaviour Jido.Agent.Extension
      use Spark.Dsl.Extension,
        sections: unquote(Keyword.get(opts, :sections, [])),
        imports: unquote(Keyword.get(opts, :imports, []))

      def id, do: unquote(Keyword.get(opts, :id, Atom.to_string(__CALLER__.module)))
      def vsn, do: unquote(Keyword.get(opts, :vsn, 1))

      @doc false
      def __jido_catalog_manifest__ do
        %{id: id(), vsn: vsn(), target: __MODULE__}
      end

      def lower(_dsl, config), do: {:ok, config}

      def normalize(data) do
        with :ok <- Jido.Agent.Schema.plain_map(data),
             :ok <- Jido.Agent.Schema.static(data),
             do: {:ok, data}
      end

      def verify(_data, _definition), do: :ok
      def derive_routes(_data), do: []
      def endpoint_kinds, do: []
      def endpoints(_data), do: []
      def verify_connection(_data, _connection), do: :ok

      def encode_authoring_data(data, registry),
        do: Jido.Codec.Value.encode(data, registry)

      def decode_authoring_data(data, registry),
        do: Jido.Codec.Value.decode(data, registry)

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
  @spec encode_authoring_data(module(), map(), Catalog.source()) ::
          {:ok, term()} | {:error, term()}
  def encode_authoring_data(provider, data, catalog) when is_struct(catalog, Catalog) or catalog == :current do
    authoring_data(provider, :encode_authoring_data, data, catalog, &Value.encode/2)
  end

  @doc false
  @spec decode_authoring_data(module(), term(), Catalog.source()) ::
          {:ok, term()} | {:error, term()}
  def decode_authoring_data(provider, data, catalog) when is_struct(catalog, Catalog) or catalog == :current do
    authoring_data(provider, :decode_authoring_data, data, catalog, &Value.decode/2)
  end

  @doc false
  def providers(providers) do
    with {:ok, providers} <- Schema.list(providers, &provider/1),
         :ok <- Schema.unique(providers, & &1),
         :ok <- unique_ids(providers),
         :ok <- namespaces(providers) do
      {:ok, providers}
    end
  end

  @doc false
  def unique_ids(providers) do
    with {:ok, ids} <- Schema.list(providers, &invoke(&1, :id, [], :id)),
         do: Schema.unique(ids, & &1)
  end

  @doc false
  def provider(module) when is_atom(module) and module not in [nil, true, false] do
    required_callbacks =
      __MODULE__.behaviour_info(:callbacks) -- __MODULE__.behaviour_info(:optional_callbacks)

    callbacks = [{:sections, 0}, {:__jido_catalog_manifest__, 0} | required_callbacks]

    if match?({:module, _}, Code.ensure_compiled(module)) and
         Enum.all?(callbacks, fn {f, a} -> function_exported?(module, f, a) end) do
      with {:ok, _identity} <- identity(module),
           :ok <- plugin(module),
           do: {:ok, module}
    else
      Error.validation_result(
        :invalid_provider,
        [],
        "Provider #{inspect(module)} does not implement the Agent contribution contract",
        %{provider: module}
      )
    end
  end

  def provider(value),
    do: Error.validation_result(:invalid_provider, [], "Expected a provider module", %{provider: value})

  defp plugin(module) do
    with {:ok, manifest} <- invoke(module, :__jido_catalog_manifest__, [], :value),
         {:ok, %{id: id, vsn: vsn}} <- identity(module) do
      if Jido.Plugin in behaviours(module) and manifest === %{id: id, target: module, vsn: vsn} do
        :ok
      else
        Error.validation_result(
          :invalid_plugin,
          [],
          "Agent plugins must use Jido.Plugin",
          %{plugin: module}
        )
      end
    end
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  @doc false
  def normalize(entries) do
    with {:ok, entries} <- Schema.list(entries, &entry/1),
         {:ok, _} <- providers(Enum.map(entries, & &1.provider)),
         do: {:ok, entries}
  end

  defp entry(value) do
    with {:ok, value} <- Schema.fields(value, [:id, :provider, :vsn, :data]),
         {:ok, provider} <- provider(value[:provider]),
         :ok <- match_identity(value, provider),
         :ok <- Schema.plain_map(value[:data]),
         {:ok, data} <- invoke(provider, :normalize, [value.data], :data),
         :ok <- Schema.static(data),
         {:ok, identity} <- identity(provider) do
      {:ok, Map.put(identity, :data, data)}
    end
  end

  defp identity(provider) do
    with {:ok, id} <- invoke(provider, :id, [], :id),
         {:ok, vsn} <- invoke(provider, :vsn, [], :vsn),
         do: {:ok, %{id: id, provider: provider, vsn: vsn}}
  end

  defp match_identity(value, provider) do
    with {:ok, id} <- invoke(provider, :id, [], :id),
         true <- value[:id] === id,
         {:ok, vsn} <- invoke(provider, :vsn, [], :vsn),
         true <- value[:vsn] === vsn do
      :ok
    else
      false -> Error.validation_result(:provider_identity, [], "Provider ID or version does not match its contract")
      error -> error
    end
  end

  @doc false
  def lower(declarations, dsl) do
    with :ok <- Schema.plain_map(dsl),
         {:ok, declarations} <-
           Schema.list(declarations, fn declaration ->
             with {:ok, declaration} <- Schema.fields(declaration, [:provider, :config]),
                  {:ok, provider} <- provider(declaration[:provider]),
                  :ok <- Schema.plain_map(declaration[:config]) do
               {:ok, %{provider: provider, config: declaration.config}}
             end
           end) do
      Schema.list(declarations, fn %{provider: provider, config: config} ->
        with {:ok, data} <- invoke(provider, :lower, [dsl, config], :data),
             {:ok, identity} <- identity(provider) do
          {:ok, Map.put(identity, :data, data)}
        end
      end)
    end
  end

  @doc false
  def verify(entries, definition) do
    with {:ok, _} <-
           Schema.list(entries, fn entry ->
             with :ok <- invoke(entry.provider, :verify, [entry.data, definition], :check),
                  do: {:ok, entry}
           end),
         do: :ok
  end

  @doc false
  def route_contributions(entries) do
    with {:ok, groups} <-
           Schema.list(entries, fn entry ->
             with {:ok, routes} <- Error.prefix_result_path(derived_routes(entry), :routes) do
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

  defp derived_routes(%{provider: provider, data: data}) do
    if function_exported?(provider, :derive_routes, 1) do
      with {:ok, routes} <- invoke(provider, :derive_routes, [data], :list) do
        Schema.list(routes, fn route ->
          with :ok <- Schema.plain_map(route),
               :ok <- Error.prefix_result_path(Schema.exact(Map.get(route, :path)), :path),
               do: {:ok, route}
        end)
      end
    else
      {:ok, []}
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
    Schema.list(contributions, fn contribution ->
      with {:ok, route} <- Error.prefix_result_path(Route.normalize(contribution.route), route_path(contribution)),
           do: {:ok, %{contribution | route: route}}
    end)
  end

  defp remove_derived_routes(routes, contributions) do
    Enum.reduce_while(contributions, {:ok, routes}, fn contribution, {:ok, routes} ->
      case Enum.find_index(routes, &(&1 === contribution.route)) do
        nil ->
          {:halt,
           Error.validation_result(
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
  def endpoints(entries) do
    with {:ok, groups} <-
           Schema.list(entries, &invoke(&1.provider, :endpoints, [&1.data], :list)),
         do: {:ok, Enum.concat(groups)}
  end

  @doc false
  def verify_connection(entries, connection) do
    with {:ok, _} <-
           Schema.list(entries, fn entry ->
             with :ok <- invoke(entry.provider, :verify_connection, [entry.data, connection], :check),
                  do: {:ok, entry}
           end),
         do: :ok
  end

  defp namespaces(providers) do
    with {:ok, sections} <- Schema.list(providers, &invoke(&1, :sections, [], :sections)),
         {:ok, kinds} <- Schema.list(providers, &invoke(&1, :endpoint_kinds, [], :list)) do
      names = sections |> Enum.concat() |> Enum.map(& &1.name)
      unique_namespaces(names, Enum.concat(kinds))
    end
  end

  defp unique_namespaces(sections, kinds) do
    cond do
      Enum.any?(
        sections,
        &(&1 in ~w(agent state routes topology __state__ __routes__ __topology__)a)
      ) ->
        Error.validation_result(:namespace_conflict, [], "Provider cannot replace a core section")

      :agent in kinds ->
        Error.validation_result(:namespace_conflict, [], "Provider cannot replace agent endpoints")

      true ->
        with :ok <- Schema.unique(sections, & &1), do: Schema.unique(kinds, & &1)
    end
  end

  defp invoke(provider, callback, args, expected) do
    case Callback.capture(provider, callback, args) do
      {:ok, result} ->
        callback_result(result, expected, provider, callback)

      {:error, kind, reason} ->
        callback_error(provider, callback, kind, reason, Exception.format_banner(kind, reason))
    end
  end

  defp callback_result(:ok, :check, _provider, _callback), do: :ok

  defp callback_result({:ok, data}, :data, _provider, _callback)
       when is_map(data) and not is_struct(data),
       do: {:ok, data}

  defp callback_result({:error, _reason} = error, expected, _provider, _callback)
       when expected in [:data, :check],
       do: result(error)

  defp callback_result(id, :id, _provider, _callback) when is_binary(id) and byte_size(id) > 0,
    do: {:ok, id}

  defp callback_result(vsn, :vsn, _provider, _callback) when is_integer(vsn) and vsn > 0,
    do: {:ok, vsn}

  defp callback_result(value, :value, _provider, _callback), do: {:ok, value}

  defp callback_result(values, :list, provider, callback) when is_list(values) do
    if List.improper?(values),
      do: invalid_result(provider, callback, values),
      else: {:ok, values}
  end

  defp callback_result(sections, :sections, provider, callback) do
    with {:ok, sections} <- callback_result(sections, :list, provider, callback) do
      if Enum.all?(sections, &match?(%{name: name} when is_atom(name), &1)),
        do: {:ok, sections},
        else: invalid_result(provider, callback, sections)
    end
  end

  defp callback_result(result, _expected, provider, callback), do: invalid_result(provider, callback, result)

  defp invalid_result(provider, callback, result),
    do: callback_error(provider, callback, :return, result, "Invalid return value #{inspect(result)}")

  defp callback_error(provider, callback, kind, reason, cause) do
    code = if kind == :return, do: :invalid_provider_callback_result, else: :provider_callback_failed

    Error.validation_result(code, [], "Provider #{inspect(provider)} callback #{inspect(callback)}. #{cause}", %{
      provider: provider,
      callback: callback,
      failure_kind: kind,
      reason: reason
    })
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
        Error.validation_result(
          :provider_authoring_data,
          [],
          "Provider authoring callback returned an invalid value",
          %{provider: provider, callback: callback, value: other}
        )
    end
  rescue
    exception ->
      Error.validation_result(
        :provider_authoring_data,
        [],
        "Provider authoring callback failed",
        %{provider: provider, callback: callback, reason: Exception.message(exception)}
      )
  catch
    kind, reason ->
      Error.validation_result(
        :provider_authoring_data,
        [],
        "Provider authoring callback failed",
        %{provider: provider, callback: callback, failure_kind: kind, reason: inspect(reason)}
      )
  end

  defp result({:error, %Error.ValidationError{}} = error), do: error

  defp result({:error, reason}),
    do:
      Error.validation_result(:provider_error, [], "Provider rejected its data: #{inspect(reason)}", %{
        reason: reason
      })
end
