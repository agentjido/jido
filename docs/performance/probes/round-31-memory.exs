# Diagnostic only. Build inputs before the resource observer starts.
# Use the same script path in both worktrees. No timing claim comes from this run.
Code.require_file("../../../bench/support/suite.exs", __DIR__)
alias JidoCoreBench.{Suite, Measure}
{:ok, supervisor} = Jido.start_link(name: JidoCoreBench)

try do
  cases =
    for workload <- Suite.workloads("scale"),
        String.starts_with?(workload.id, "codec/encode/") do
      prepared = workload.setup.(%{})
      fixed = %{workload | setup: fn _ -> prepared end}

      result = %{
        id: workload.id,
        resources: Measure.resources(fixed, 5),
        retained: Measure.retained(fixed)
      }

      Suite.ensure_idle!()
      result
    end

  File.write!(hd(System.argv()), JSON.encode!(%{metadata: Suite.metadata(), cases: cases}))
after
  Supervisor.stop(supervisor)
end
