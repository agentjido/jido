defmodule JidoTest.Authoring.Agents.Fixtures.Rename do
  use Jido.Action, name: "corpus_rename", schema: Zoi.object(%{name: Zoi.string()})
  def run(%{name: name}, %{agent_state: state}), do: {:ok, %{state | name: name}}
end

defmodule JidoTest.Authoring.Agents.Fixtures.SetConfig do
  use Jido.Action,
    name: "corpus_config",
    schema:
      Zoi.object(%{
        enabled: Zoi.boolean(),
        amount: Zoi.integer(),
        note: Zoi.string() |> Zoi.nullable()
      })

  def run(input, _context), do: {:ok, input}
end

defmodule JidoTest.Authoring.Agents.Fixtures.RenameNested do
  use Jido.Action, name: "corpus_nested", schema: Zoi.object(%{name: Zoi.string()})

  def run(%{name: name}, %{agent_state: state}),
    do: {:ok, %{state | profile: %{state.profile | name: name}}}
end

defmodule JidoTest.Authoring.Agents.Fixtures.ReplaceItems do
  use Jido.Action, name: "corpus_items", schema: Zoi.object(%{items: Zoi.array(Zoi.string())})
  def run(%{items: items}, %{agent_state: state}), do: {:ok, %{state | items: items}}
end

defmodule JidoTest.Authoring.Agents.Fixtures.SetValue do
  # Broad Action input deliberately leaves candidate validation to the Agent.
  use Jido.Action, name: "corpus_value", schema: Zoi.object(%{value: Zoi.any()})
  def run(%{value: value}, %{agent_state: state}), do: {:ok, %{state | value: value}}
end

defmodule JidoTest.Authoring.Agents.Fixtures.Noop do
  use Jido.Action, name: "corpus_noop"
  def run(_input, %{agent_state: state}), do: {:ok, state}
end

defmodule JidoTest.Authoring.Agents.Fixtures.Choose do
  use Jido.Action,
    name: "corpus_choose",
    schema: Zoi.object(%{label: Zoi.string(), n: Zoi.integer() |> Zoi.optional()})

  def run(%{label: label}, %{agent_state: state}), do: {:ok, %{state | selected: label}}
end

defmodule JidoTest.Authoring.Agents.Fixtures.Matchers do
  def positive?(%{data: %{n: n}}), do: is_integer(n) and n > 0
  def positive?(_signal), do: false
end

defmodule JidoTest.Authoring.Agents.Fixtures.SetTotal do
  use Jido.Action, name: "corpus_total", schema: Zoi.object(%{value: Zoi.integer()})
  def run(%{value: value}, _context), do: {:ok, %{total: value}}
end

defmodule JidoTest.Authoring.Agents.Fixtures.SetText do
  use Jido.Action, name: "corpus_text", schema: Zoi.object(%{text: Zoi.string()})
  def run(%{text: text}, %{agent_state: state}), do: {:ok, %{state | text: text}}
end

defmodule JidoTest.Authoring.Agents.Fixtures.FirstFacet do
  use Jido.Agent.Plugin
  def state_spec(_opts), do: {:first, Zoi.integer() |> Zoi.default(0)}
  def reduce(reduction, _opts), do: {:ok, reduction.state.value + 1}
end

defmodule JidoTest.Authoring.Agents.Fixtures.FirstPlugin do
  use Jido.Plugin, agent: JidoTest.Authoring.Agents.Fixtures.FirstFacet
end

defmodule JidoTest.Authoring.Agents.Fixtures.SecondFacet do
  use Jido.Agent.Plugin
  def state_spec(_opts), do: {:second, Zoi.integer() |> Zoi.default(0)}
  def reduce(reduction, _opts), do: {:ok, reduction.state.first}
end

defmodule JidoTest.Authoring.Agents.Fixtures.SecondPlugin do
  use Jido.Plugin, agent: JidoTest.Authoring.Agents.Fixtures.SecondFacet
end

defmodule JidoTest.Authoring.Agents.Fixtures.ViaExtension do
  use Spark.Dsl.Extension
  def route_target_options, do: [:via]

  def lower_agent(config, entities) do
    routes =
      Enum.map(config.routes, fn
        %{target: %Jido.Agent.Extension.RouteTarget{option: :via, value: target}} = route ->
          %{route | target: target}

        route ->
          route
      end)

    {:ok, %{config | routes: routes, metadata: %{extension: "route"}}, entities}
  end
end
