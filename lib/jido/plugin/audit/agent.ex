defmodule Jido.Plugin.Audit.Agent do
  @moduledoc "Separate Agent facet for packages that reuse Audit state reduction."
  use Jido.Agent.Plugin

  defdelegate state_spec(opts), to: Jido.Plugin.Audit
  defdelegate directives(opts), to: Jido.Plugin.Audit
  defdelegate reduce(reduction, opts), to: Jido.Plugin.Audit
  defdelegate apply_records(state, records, opts), to: Jido.Plugin.Audit
end
