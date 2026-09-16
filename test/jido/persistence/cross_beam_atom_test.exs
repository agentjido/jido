defmodule JidoTest.Persistence.CrossBeamAtomTest do
  use JidoTest.PeerCase, async: false

  alias Jido.Examples.CheckpointPortabilityProbe, as: Probe
  alias Jido.Persistence
  alias Jido.Persistence.ETS

  test "a saved new atom fails safe load on a second BEAM, while a string loads", c do
    source = {ETS, table: :cross_beam_atom_checkpoint}
    {ETS, adapter_opts} = source
    assert peer_call(c.peer_b, Code, :ensure_loaded?, [Probe])

    name = "jido_unloaded_checkpoint_atom_#{System.unique_integer([:positive])}"
    atom = String.to_atom(name)
    atom_agent = Probe.new!(id: "unloaded-atom", state: %{payload: %{value: atom}})
    assert :ok = peer_call(c.peer_a, Persistence, :save_agent, [source, atom_agent, []])

    atom_key = Persistence.agent_key(nil, Probe, atom_agent.id)
    assert {:ok, atom_bytes} = peer_call(c.peer_a, ETS, :get, [atom_key, adapter_opts])
    assert :ok = peer_call(c.peer_b, ETS, :put, [atom_key, atom_bytes, adapter_opts])

    assert {:error, :invalid_persistence_record} =
             peer_call(c.peer_b, Persistence, :load_agent, [source, Probe, atom_agent.id, []])

    string_agent = Probe.new!(id: "stable-string", state: %{payload: %{value: name}})
    assert :ok = peer_call(c.peer_a, Persistence, :save_agent, [source, string_agent, []])

    string_key = Persistence.agent_key(nil, Probe, string_agent.id)
    assert {:ok, string_bytes} = peer_call(c.peer_a, ETS, :get, [string_key, adapter_opts])
    assert :ok = peer_call(c.peer_b, ETS, :put, [string_key, string_bytes, adapter_opts])

    assert {:ok, ^string_agent} =
             peer_call(c.peer_b, Persistence, :load_agent, [source, Probe, string_agent.id, []])
  end
end
