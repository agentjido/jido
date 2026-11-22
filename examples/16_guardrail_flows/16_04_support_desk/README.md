# Ticket Policy with Stock ReAct

The Support Desk Agent adds two Actions through `jido_react_guards/0`.
One checks the request scope before model work. The other checks the answer
against the Agent's committed ticket status. The model can tell the user to
use a ticket control. The application owns ticket state changes.

```sh
mix test.examples examples/16_guardrail_flows/16_04_support_desk
```

The example checks two specific claim phrases and accepts text replies. A
production input classifier and ticket policy belong to the application.
See `Jido.AI.Reasoning.ReAct.Guards` for the approved streaming event.
For admission before the model Turn, a tool loop, and ticket controls, see
[Support Desk](../../24_application_patterns/24_09_support_desk/README.md).
