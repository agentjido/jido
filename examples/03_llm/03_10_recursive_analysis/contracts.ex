defmodule Jido.Examples.RecursiveLanguageModel.Contracts do
  @moduledoc "Schemas for the local RLM simulation. Ranges use zero-based record offsets."

  def limits do
    %{
      max_depth: 16,
      max_calls: 4_095,
      max_steps: 8_190,
      max_bytes: 8_000_000,
      max_read_records: 64
    }
  end

  def range do
    Zoi.object(%{offset: Zoi.integer() |> Zoi.min(0), length: Zoi.integer() |> Zoi.min(0)},
      unrecognized_keys: :error
    )
  end

  def request do
    Zoi.object(
      %{
        corpus_id: Zoi.string() |> Zoi.min(1),
        query: Zoi.enum([:failed_jobs_by_service]),
        range: range() |> Zoi.nullable(),
        limits:
          Zoi.object(
            %{
              max_depth: Zoi.integer() |> Zoi.min(0) |> Zoi.max(64),
              max_calls: Zoi.integer() |> Zoi.min(1),
              max_steps: Zoi.integer() |> Zoi.min(1),
              max_bytes: Zoi.integer() |> Zoi.min(0),
              max_read_records: Zoi.integer() |> Zoi.min(1)
            },
            unrecognized_keys: :error
          )
      },
      unrecognized_keys: :error
    )
  end

  def counts, do: Zoi.map(Zoi.string() |> Zoi.min(1), Zoi.integer() |> Zoi.min(1))

  def call_node do
    Zoi.object(%{
      id: Zoi.integer() |> Zoi.min(1),
      parent_id: Zoi.integer() |> Zoi.min(0),
      depth: Zoi.integer() |> Zoi.min(0),
      range: range(),
      counts: counts()
    })
  end

  def usage do
    fields = [:calls, :steps, :bytes_read, :records_read, :max_depth, :peak_read_records]
    Zoi.object(Map.new(fields, &{&1, Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)}))
  end

  def record do
    Zoi.object(
      %{
        id: Zoi.string(),
        service: Zoi.string() |> Zoi.min(1),
        status: Zoi.enum([:ok, :failed]),
        message: Zoi.string()
      },
      unrecognized_keys: :error
    )
  end

  def decision do
    Zoi.union([
      Zoi.object(%{op: Zoi.literal(:read)}, unrecognized_keys: :error),
      Zoi.object(%{op: Zoi.literal(:recurse), ranges: Zoi.list(range())},
        unrecognized_keys: :error
      ),
      Zoi.object(%{op: Zoi.literal(:answer), counts: counts()}, unrecognized_keys: :error)
    ])
  end

  def clients do
    client = Zoi.tuple({Zoi.atom(), Zoi.any()})
    Zoi.object(%{model: client, store: client})
  end
end
