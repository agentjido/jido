Code.require_file("json_agent.ex", __DIR__)

alias Jido.AI.Reasoning.ReAct
alias Jido.Examples.AI.JSONAgent

{:ok, definition} = JSONAgent.import()

[%{handler: %{kind: :flow, target: root_flow}}] = definition.routes
true = root_flow == ReAct

IO.puts("Loaded Agent from JSON: #{definition.name}")
IO.puts("Root reasoning Flow: #{inspect(root_flow)}")

agent = Jido.Agent.instantiate!(definition, id: "json-simple-agent")

signal =
  JSONAgent.request_signal!(definition, %{
    input: "Use add for 2 plus 3 and multiply for 4 times 5. Report both results."
  })

{:ok, preflight} = Jido.AI.Reasoning.preflight(definition.module, signal.data)
IO.inspect(Enum.map(preflight.tools, & &1.name()), label: "Prepared tools")
IO.inspect(agent.state, label: "Initial Agent state")
