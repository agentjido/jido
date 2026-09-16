defmodule Jido.Plugin.Dispatch.Agent do
  @moduledoc "Declares the Signal delivery Directive owned by Dispatch."
  use Jido.Agent.Plugin

  alias Jido.Plugin.Dispatch.Send

  @impl true
  def directives(_opts), do: [Send]
end
