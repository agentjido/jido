defmodule JidoTest.Property.Config do
  @moduledoc false

  @families %{
    "jido_agent_server" => %{
      module_prefixes: ["JidoTest.Property.Runtime."],
      fuzz_ids: ["agent_server_lifecycle"],
      required_observations: %{
        "agent_server_lifecycle" => ~w(cleanup failure hibernate invalid_directive invalid_state restore success)
      }
    },
    "jido_expr" => %{
      module_prefixes: ["JidoTest.Property.ActionFlow.Expression."],
      fuzz_ids: ["expression_trees"],
      required_observations: %{}
    },
    "jido_signal" => %{
      module_prefixes: ["JidoTest.Property.Signal."],
      fuzz_ids: ~w(
          bus_histories bus_observations catalog_boundaries dispatch_sequences
          durable_store_faults envelope_wire memory_histories pid_lifecycles
          routing_model trace_ids wire_mutations
        ),
      required_observations: %{}
    }
  }

  def families, do: @families

  def family!(id), do: Map.fetch!(@families, id)

  def family_for_module(module) do
    name = inspect(module)

    Enum.find_value(@families, fn {id, config} ->
      if Enum.any?(config.module_prefixes, &String.starts_with?(name, &1)), do: id
    end)
  end

  def family_for_measurement(id) do
    Enum.find_value(@families, fn {family, config} ->
      if id in config.fuzz_ids, do: family
    end)
  end

  def corpus(family, id) do
    case family do
      "jido_signal" -> Path.wildcard(Path.expand("../corpus/signal/#{id}/*.json", __DIR__))
      _other -> []
    end
  end

  def report_path(root \\ Mix.Project.build_path()), do: Path.join(root, "property-report.json")

  def measurement_path(root, run_id, family, id, variant) do
    Path.join([root, "property-fuzz", run_id || "standalone", family, "#{id}-#{variant}.json"])
  end

  def counterexample_dir(root, family, id) do
    Path.join([root, "property-counterexamples", family, id])
  end
end
