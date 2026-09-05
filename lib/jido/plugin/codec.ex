defmodule Jido.Plugin.Codec do
  @moduledoc """
  Encodes one current Agent Plugin declaration through a trusted authoring
  Registry. The document stores the Plugin module and its options, never its
  instance state or runtime. Agent Codec uses this same format and Registry.
  """
  alias Jido.Agent.Codec
  alias Jido.Agent.Codec.{Data, Registry}

  @doc "Encodes a Plugin with a generated temporary Registry."
  def encode(plugin) do
    with {:ok, [plugin]} <- Jido.Plugin.canonical_declarations([plugin]),
         {:ok, registry} <- Codec.Deriver.plugin(plugin),
         {:ok, document} <- encode(plugin, registry),
         do: {:ok, document, registry}
  end

  @doc "Encodes a Plugin module and options."
  def encode(plugin, registry) do
    with {:ok, [{module, options}]} <- Jido.Plugin.canonical_declarations([plugin]),
         {:ok, registry} <- Registry.new(registry),
         {:ok, module_id} <- Registry.identifier(registry, :plugin, module),
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
  def decode(document, registry) do
    with :ok <- Data.check_document(document),
         :ok <- Codec.object(document, ~w(type version module options)),
         :ok <- Codec.version(document, "jido.plugin"),
         {:ok, registry} <- Registry.new(registry),
         {:ok, module} <- Registry.resolve(registry, document["module"], :plugin),
         {:ok, options} <- Data.decode(document["options"], registry),
         {:ok, [plugin]} <- Jido.Plugin.canonical_declarations([{module, options}]) do
      {:ok, plugin}
    end
  end
end
