defmodule Jido.Authoring.Options do
  @moduledoc false

  @doc false
  @spec validate!(term(), Macro.Env.t(), String.t(), String.t(), [atom()] | nil) ::
          :ok | no_return()
  def validate!(options, caller, message, label, allowed \\ nil) do
    unless Keyword.keyword?(options), do: error!(caller, message)

    _seen =
      Enum.reduce(options, MapSet.new(), fn {key, _value}, seen ->
        allowed_key!(key, allowed, caller, label, "")
        if MapSet.member?(seen, key), do: error!(caller, "duplicate #{label}: #{inspect(key)}")
        MapSet.put(seen, key)
      end)

    :ok
  end

  @doc false
  @spec allowed!(keyword(), [atom()], Macro.Env.t(), String.t(), String.t()) ::
          :ok | no_return()
  def allowed!(options, allowed, caller, label, suffix \\ "") do
    Enum.each(options, fn {key, _value} -> allowed_key!(key, allowed, caller, label, suffix) end)
  end

  @doc false
  @spec error!(Macro.Env.t(), String.t()) :: no_return()
  def error!(caller, description),
    do: raise(CompileError, file: caller.file, line: caller.line, description: description)

  defp allowed_key!(_key, nil, _caller, _label, _suffix), do: :ok

  defp allowed_key!(key, allowed, caller, label, suffix) do
    unless key in allowed, do: error!(caller, "unsupported #{label}: #{inspect(key)}#{suffix}")
  end
end
