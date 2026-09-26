defmodule Jido.Persistence.Identity do
  @moduledoc false

  alias Jido.Agent.Ref

  @key_prefix "jido:agent:v1:"

  def resolve(instance, agent_id, opts) do
    case Keyword.get_lazy(opts, :namespace, fn -> Jido.namespace(instance) end) do
      nil ->
        {:error, :stable_namespace_required}

      namespace ->
        Ref.new(namespace: namespace, partition: Keyword.get(opts, :partition), id: agent_id)
    end
  end

  def agent_key(%Ref{} = ref) do
    ref = Ref.new!(ref)

    encoded =
      {ref.namespace, ref.partition, ref.id}
      |> :erlang.term_to_binary()
      |> Base.url_encode64(padding: false)

    @key_prefix <> encoded
  end
end
