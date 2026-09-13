defmodule Jido.Examples.Topology.PluginContribution do
  @moduledoc "A Topology whose Agent Plugin contributes its Bus connection."
  use Jido.Topology, name: "plugin_contribution"

  topology do
    agents do
      agent :worker, Jido.Examples.Topology.InboxWorker
    end
  end
end

defmodule Jido.Examples.Topology.InvalidPluginContribution do
  @moduledoc "A Topology that rejects an invalid Plugin contribution during planning."
  use Jido.Topology, name: "invalid_plugin_contribution"

  topology do
    agents do
      agent :worker, Jido.Examples.Topology.InvalidInboxWorker
    end
  end
end
