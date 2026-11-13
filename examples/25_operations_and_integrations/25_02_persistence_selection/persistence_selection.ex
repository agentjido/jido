defmodule Jido.Examples.Operations.PersistenceSelection do
  @moduledoc "Resolves explicit and instance-owned persistence profiles."

  @doc "Validates an explicit persistence profile declaration."
  def explicit(config), do: Jido.Persistence.resolve_config(config, nil)

  @doc "Reads the persistence declaration owned by one live Jido instance."
  def inherited(instance), do: Jido.Persistence.resolve_config(:inherit, instance)
end
