defmodule Jido.Plugin.Codec do
  @moduledoc """
  Encodes one current Agent Plugin declaration through a trusted authoring
  Registry. The document stores the Plugin module and its options, never its
  instance state or runtime. Agent Codec uses this same format and Registry.
  """
  alias Jido.Agent.Authoring
  alias Jido.Codec.{Data, Registry}

  @type document :: %{required(String.t()) => term()}

  @doc "Encodes a Plugin with a generated temporary Registry."
  @spec encode(Jido.Plugin.declaration()) ::
          {:ok, document(), Registry.t()} | {:error, term()}
  def encode(plugin) do
    with {:ok, [plugin]} <- Jido.Plugin.canonical_declarations([plugin]),
         {:ok, registry} <- derive_registry(plugin),
         {:ok, document} <- encode_normalized(plugin, registry),
         do: {:ok, document, registry}
  end

  @doc "Encodes a Plugin module and options."
  @spec encode(Jido.Plugin.declaration(), Registry.t() | map()) ::
          {:ok, document()} | {:error, term()}
  def encode(plugin, registry) do
    with {:ok, [{module, options}]} <- Jido.Plugin.canonical_declarations([plugin]),
         {:ok, registry} <- Registry.new(registry),
         do: encode_normalized({module, options}, registry)
  end

  defp encode_normalized({module, options}, registry) do
    with {:ok, module_id} <- Registry.identifier(registry, :plugin, module),
         {:ok, options} <- Data.encode(options, registry) do
      document = %{
        "type" => "jido.plugin",
        "version" => 1,
        "module" => module_id,
        "options" => options
      }

      with :ok <- Data.check_document(document), do: {:ok, document}
    end
  end

  @doc "Decodes a Plugin declaration without starting its runtime."
  @spec decode(document(), Registry.t() | map()) ::
          {:ok, {module(), keyword()}} | {:error, term()}
  def decode(document, registry) do
    with :ok <- Data.check_document(document),
         :ok <- document_header(document),
         {:ok, registry} <- Registry.new(registry),
         {:ok, module} <- Registry.resolve(registry, document["module"], :plugin),
         {:ok, options} <- Data.decode(document["options"], registry),
         {:ok, [plugin]} <- Jido.Plugin.canonical_declarations([{module, options}]) do
      {:ok, plugin}
    end
  end

  defp document_header(document) do
    with :ok <- Data.object(document, ~w(type version module options)),
         do: document_version(document)
  end

  defp document_version(%{"type" => "jido.plugin", "version" => 1}), do: :ok

  defp document_version(_document),
    do: Authoring.error("Unknown authoring document type or version")

  defp derive_registry({module, options}) do
    Registry.derive([{:plugin, module} | Data.registry_entries(options)])
  end
end
