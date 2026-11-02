defmodule Jido.Authoring.RegistryProviderTest do
  use ExUnit.Case, async: false

  alias Jido.Authoring
  alias Jido.Authoring.Registry

  defmodule Definition do
    @moduledoc false
    defstruct [:name]
  end

  defmodule Codec do
    @moduledoc false

    def __jido_authoring_codec__ do
      %{type: "test.registry-provider", vsn: 1, encoder: Definition}
    end

    def encode_document(%Definition{name: name}, registry) do
      with {:ok, name} <- Jido.Authoring.Value.encode(name, registry) do
        {:ok, %{"type" => "test.registry-provider", "vsn" => 1, "name" => name}}
      end
    end

    def decode_document(%{"name" => name}, registry) do
      with {:ok, name} <- Jido.Authoring.Value.decode(name, registry) do
        {:ok, %Definition{name: name}}
      end
    end
  end

  defmodule Vocabulary do
    @moduledoc false

    def __jido_authoring__ do
      %{id: "atoms/example", kind: :atom, vsn: 1, target: :example}
    end
  end

  setup do
    previous = Application.fetch_env(:jido, Authoring)
    registry = :persistent_term.get({Jido.Discovery, :registry}, :not_initialized)

    on_exit(fn ->
      case previous do
        {:ok, config} -> Application.put_env(:jido, Authoring, config)
        :error -> Application.delete_env(:jido, Authoring)
      end

      if registry == :not_initialized,
        do: :persistent_term.erase({Jido.Discovery, :registry}),
        else: :persistent_term.put({Jido.Discovery, :registry}, registry)
    end)

    :ok
  end

  test "uses the configured registry provider" do
    registry = Registry.new!(%{{"atoms/example", 1} => {:atom, :example}})
    Application.put_env(:jido, Authoring, registry_provider: registry)

    definition = %Definition{name: :example}

    assert {:ok,
            %{
              "type" => "test.registry-provider",
              "vsn" => 1,
              "name" => %{"$type" => "atom", "id" => "atoms/example", "vsn" => 1}
            } = document} = Authoring.encode(definition, codec: Codec)

    assert {:ok, ^definition} = Authoring.decode(document, codec: Codec)
  end

  test "uses Discovery as the default registry provider" do
    Application.delete_env(:jido, Authoring)
    assert :ok = Jido.Discovery.refresh(applications: [], modules: [Vocabulary])

    definition = %Definition{name: :example}

    assert {:ok, document} = Authoring.encode(definition, codec: Codec)
    assert {:ok, ^definition} = Authoring.decode(document, codec: Codec)
  end
end
