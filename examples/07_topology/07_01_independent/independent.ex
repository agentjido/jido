defmodule Jido.Examples.Topology.Independent do
  @moduledoc "Two named members keep separate state under one owning Agent."
  use Jido.Agent, name: "topology_independent"

  topology do
    agent :left, Jido.Examples.Topology.Independent.Cell do
      initial_state %{label: "left"}
    end

    agent :right, Jido.Examples.Topology.Independent.Cell do
      initial_state %{label: "right"}
    end
  end

  @doc "Stable references for a stored topology with Plugin-bearing members."
  def registry do
    Jido.Authoring.Registry.new!(%{
      {"agents/independent", 1} => {:agent, __MODULE__},
      {"agents/cell", 1} => {:agent, Jido.Examples.Topology.Independent.Cell},
      {"schemas/owner", 1} => {:schema, definition().schema},
      {"atoms/left", 1} => {:atom, :left},
      {"atoms/right", 1} => {:atom, :right},
      {"atoms/label", 1} => {:atom, :label}
    })
  end
end
