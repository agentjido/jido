defmodule JidoTest.Property.Authoring do
  @moduledoc false

  # Each attempt reserves a unique module namespace. The caller stops any live
  # resources before its callback returns. Compiler exit is the verify barrier.
  def with_compiled(source, callback, options \\ []) when is_binary(source) do
    modules = Keyword.fetch!(options, :modules)
    timeout = Keyword.get(options, :timeout, 10_000)

    unless is_list(modules) and not List.improper?(modules) and modules != [] and
             Enum.all?(modules, &(is_atom(&1) and not is_nil(&1))),
           do: raise(ArgumentError, "fixture modules must name unique reserved namespaces")

    unless is_integer(timeout) and timeout > 0,
      do: raise(ArgumentError, "fixture compilation requires a positive timeout")

    if Enum.any?(:code.all_loaded(), fn {module, _} -> reserved?(module, modules) end),
      do: raise(ArgumentError, "fixture namespace already contains loaded code")

    owner = self()

    try do
      {pid, ref} =
        spawn_monitor(fn ->
          result =
            Code.with_diagnostics([log: false], fn ->
              Code.compile_string(source, "property_fixture.ex")
            end)

          send(owner, {self(), :compiled, result})
        end)

      result =
        receive do
          {:DOWN, ^ref, :process, ^pid, :normal} ->
            receive do
              {^pid, :compiled, result} -> result
            after
              0 -> raise "compiler exited without a fixture result"
            end

          {:DOWN, ^ref, :process, ^pid, {error, stack}} when is_exception(error) ->
            reraise error, stack

          {:DOWN, ^ref, :process, ^pid, reason} ->
            raise "fixture compiler exited: #{inspect(reason)}"
        after
          timeout ->
            Process.exit(pid, :kill)

            receive do
              {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
            end

            raise "fixture compilation exceeded its budget"
        end

      {compiled, diagnostics} = result
      if diagnostics != [], do: raise("fixture compilation diagnostics: #{inspect(diagnostics)}")
      callback.(Enum.map(compiled, &elem(&1, 0)))
    after
      # Include generated nested inline Action modules and partially compiled
      # modules after an after_verify failure, without touching other tests.
      for {module, _file} <- :code.all_loaded(), reserved?(module, modules) do
        :code.purge(module)
        :code.delete(module)
        :code.purge(module)
      end
    end
  end

  defp reserved?(module, namespaces) do
    name = Atom.to_string(module)

    owned_name? =
      Enum.any?(namespaces, fn namespace ->
        prefix = Atom.to_string(namespace)
        name == prefix or String.starts_with?(name, prefix <> ".")
      end)

    owned_name? or
      (String.starts_with?(name, "Elixir.Jido.Action.Generated.Inline.") and
         function_exported?(module, :__jido_inline_action__, 0) and
         case module.__jido_inline_action__() do
           {owner, _identity} -> reserved?(owner, namespaces)
           _ -> false
         end)
  end
end
