# Contract probe only. This supplies no timing evidence.
defmodule JidoCoreDescriptorProbe do
  @behaviour Jido.Action

  def __jido_authoring_kind__ do
    calls = Process.get(__MODULE__, 0) + 1
    Process.put(__MODULE__, calls)

    if calls == 1,
      do: :action,
      else: :flow
  end

  @impl true
  def validate_params(value), do: {:ok, value}
  @impl true
  def validate_output(value), do: {:ok, value}
  @impl true
  def run(_params, context), do: {:ok, context.agent_state}
end

alias JidoCoreDescriptorProbe, as: Probe

try do
  {:error, %Jido.Error.ValidationError{message: "Invalid Agent route executable"}} =
    Jido.Agent.new(
      name: "descriptor_probe",
      routes: [{"probe.first", Probe}, {"probe.second", Probe}]
    )

  2 = Process.get(Probe)

  IO.puts(
    "Round 29: the second route validates its Instruction target and returns a structured error"
  )
after
  Process.delete(Probe)
end
