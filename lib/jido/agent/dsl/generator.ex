defmodule Jido.Agent.DSL.Generator do
  @moduledoc false

  def function(name, path, source) do
    quote do
      @doc """
      Builds a `#{unquote(path)}` Signal from a plain input map.

      Returns `{:ok, signal}` or `{:error, reason}`. Envelope options include
      `:source`, `:id`, and `:subject`. Unknown or duplicate options are errors.
      Options cannot replace Signal type or data.

      Omitted input fields remain absent. Route defaults supply absent fields
      during execution. Explicit `nil`, `false`, and zero override defaults.
      The Action or Flow validates input during command execution.
      This function does not execute a command. Use `Jido.Agent.cmd/3` for
      direct execution or `Jido.AgentServer.call/3` for a live Server.
      """
      @spec unquote(name)(map(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, term()}
      def unquote(name)(input, envelope_opts \\ []),
        do:
          Jido.Agent.Interface.signal(
            %{path: unquote(path), source: unquote(source)},
            input,
            envelope_opts
          )
    end
  end
end
