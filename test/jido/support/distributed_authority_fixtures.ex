defmodule JidoTest.DistributedAuthorityFixtures.SharedETS do
  @moduledoc false
  @behaviour Jido.Persistence.Adapter

  def start_store do
    Supervisor.start_child(Jido.Supervisor, %{
      id: make_ref(),
      restart: :temporary,
      start: {Elixir.Agent, :start_link, [fn -> :store_owner end]}
    })
  end

  for {function, arity} <- [get: 2, put: 3, compare_and_swap: 4, delete: 2] do
    args = Macro.generate_arguments(arity - 1, __MODULE__)

    def unquote(function)(unquote_splicing(args), opts) do
      store = Keyword.fetch!(opts, :store)
      adapter_opts = Keyword.drop(opts, [:store])

      Elixir.Agent.get(store, fn _owner ->
        apply(Jido.Persistence.ETS, unquote(function), [unquote_splicing(args), adapter_opts])
      end)
    catch
      :exit, reason -> {:error, {:shared_store_unavailable, reason}}
    end
  end
end
