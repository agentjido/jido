defmodule JidoTest.Authoring.Agents.Fixtures.Invalid.RemovedDefine do
  use Jido.Agent, name: "invalid_removed_define"

  agent do
  end

  routes do
    signal_source "/invalid"

    route "items.replace", JidoTest.Authoring.Agents.Fixtures.ReplaceItems do
      define(:replace)
    end
  end
end
