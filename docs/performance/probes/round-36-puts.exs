# Resource diagnostic only: assert each write without retaining a result list.
Code.require_file("../../../bench/support/suite.exs", __DIR__)
alias JidoCoreBench.{Fixtures, Measure, Suite}
alias Jido.Persistence.ETS, as: Store
{:ok, supervisor} = Jido.start_link(name: JidoCoreBench)

try do
  cases =
    for count <- [100, 1_000, 10_000] do
      options = [table: :jido_persistence]
      key = "core-put-probe-#{count}"
      :ok = Store.put(key, <<0, 255>>, options)

      workload =
        Fixtures.checked(
          "puts/#{count}",
          fn _ -> key end,
          fn key ->
            Enum.each(1..count, fn _ -> :ok = Store.put(key, <<0, 255>>, options) end)
          end,
          &Fixtures.equal!(&1, :ok)
        )

      try do
        resources = Measure.resources(workload, 5)
        Fixtures.equal!(Store.get(key, options), {:ok, <<0, 255>>})
        %{id: workload.id, resources: resources}
      after
        Store.delete(key, options)
      end
    end

  File.write!(hd(System.argv()), JSON.encode!(%{metadata: Suite.metadata(), cases: cases}))
after
  Supervisor.stop(supervisor)
end
