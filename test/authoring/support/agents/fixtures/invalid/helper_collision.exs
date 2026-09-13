defmodule JidoTest.Authoring.Agents.Fixtures.Invalid.HelperCollision do
  use Jido.Agent, name: "invalid_helper_collision"
  def replace_signal(items), do: items

  agent do
  end

  routes do
    signal_source "/invalid"

    route "items.replace", JidoTest.Authoring.Agents.Fixtures.ReplaceItems do
      define :replace, args: [:items]
    end
  end
end
