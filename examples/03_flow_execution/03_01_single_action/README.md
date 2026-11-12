# Single Action

`Jido.Exec` lowers an Action to a canonical one-step Flow. The compiled Runic
workflow contains one input node, one `Jido.Exec.Node.Action` named `action`,
and one output node. Running the Action with 3 and 2 returns `%{value: 5}`.

See [the ExUnit proof](single_action_test.exs).
