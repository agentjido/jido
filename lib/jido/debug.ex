defmodule Jido.Debug do
  @moduledoc false

  @type level :: :off | :on | :verbose
  @type instance :: atom()

  @on_overrides %{semantic_log_mode: :interesting}
  @verbose_overrides %{semantic_log_mode: :all}

  @spec enable(instance(), level()) :: :ok
  def enable(instance, level \\ :on)

  def enable(instance, :off) do
    disable(instance)
  end

  def enable(instance, level) when level in [:on, :verbose] do
    :persistent_term.put(
      {:jido_debug, instance},
      %{level: level, overrides: build_overrides(level)}
    )

    :ok
  end

  @spec disable(instance()) :: :ok
  def disable(instance) do
    :persistent_term.erase({:jido_debug, instance})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec level(instance()) :: level()
  def level(instance), do: status(instance).level

  @spec enabled?(instance()) :: boolean()
  def enabled?(instance) do
    level(instance) != :off
  end

  @spec override(instance(), atom()) :: term() | nil
  def override(instance, key), do: Map.get(status(instance).overrides, key)

  @doc false
  @spec configure(instance(), term()) :: :ok
  def configure(instance, debug) do
    case debug do
      true -> enable(instance, :on)
      :verbose -> enable(instance, :verbose)
      _ -> disable(instance)
    end
  end

  @spec reset(instance()) :: :ok
  def reset(instance) do
    disable(instance)
  end

  @spec status(instance()) :: map()
  def status(instance) do
    case :persistent_term.get({:jido_debug, instance}, nil) do
      %{level: level, overrides: overrides} = state
      when level in [:on, :verbose] and is_map(overrides) ->
        state

      _invalid ->
        %{level: :off, overrides: %{}}
    end
  end

  defp build_overrides(:on), do: @on_overrides
  defp build_overrides(:verbose), do: @verbose_overrides
end
