defmodule JidoTest.Persistence.Profiles do
  @moduledoc false

  @profiles %{
    ets: %{
      adapter: Jido.Persistence.ETS,
      tier: :local,
      status: :active,
      description: "In-memory ETS"
    },
    file: %{
      adapter: Jido.Persistence.File,
      tier: :local,
      status: :active,
      description: "Single-BEAM files"
    },
    mnesia: %{
      adapter: Jido.Persistence.Mnesia,
      tier: :local,
      status: :active,
      description: "Application-owned Mnesia table"
    },
    ecto_sqlite: %{
      adapter: Jido.Persistence.Ecto,
      tier: :local,
      status: :active,
      description: "SQLite through Ecto"
    },
    ecto_postgres: %{
      adapter: Jido.Persistence.Ecto,
      tier: :service,
      status: :active,
      description: "PostgreSQL through Ecto"
    },
    redis: %{
      adapter: Jido.Persistence.Redis,
      tier: :service,
      status: :active,
      description: "Redis"
    },
    s3_minio: %{
      adapter: Jido.Persistence.S3,
      tier: :service,
      status: :active,
      description: "S3-compatible object storage"
    },
    bedrock: %{
      adapter: Jido.Persistence.Bedrock,
      tier: :service,
      status: :paused,
      reason: "Bedrock service tests are paused pending bedrock-kv/bedrock#319",
      description: "Bedrock KV"
    }
  }

  def all, do: @profiles
  def fetch!(name), do: Map.fetch!(@profiles, name)

  def active(tier) do
    for {name, %{tier: ^tier, status: :active}} <- @profiles, do: name
  end

  def adapter_modules do
    @profiles
    |> Map.values()
    |> Enum.map(& &1.adapter)
    |> MapSet.new()
  end

  def active_adapter_modules do
    @profiles
    |> Map.values()
    |> Enum.filter(&(&1.status == :active))
    |> Enum.map(& &1.adapter)
    |> MapSet.new()
  end

  def discovered_adapter_modules do
    :jido
    |> Application.spec(:modules)
    |> Enum.filter(&public_persistence_module?/1)
    |> Enum.filter(&persistence_adapter?/1)
    |> MapSet.new()
  end

  defp public_persistence_module?(module) do
    case module |> Atom.to_string() |> String.split(".") do
      ["Elixir", "Jido", "Persistence", _name] -> true
      _other -> false
    end
  end

  defp persistence_adapter?(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        Jido.Persistence.Adapter in List.wrap(module.module_info(:attributes)[:behaviour])

      {:error, _reason} ->
        false
    end
  end
end
