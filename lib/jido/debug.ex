defmodule Jido.Debug do
  @moduledoc """
  Per-instance debug mode for Jido agents.

  Provides a single entrypoint to control observability verbosity
  at runtime, scoped to a specific Jido instance.

  ## Debug Levels

  - `:off` - No debug overrides, uses configured defaults
  - `:on` - Developer-friendly verbosity (debug logging, keys_only args, minimal debug events)
  - `:verbose` - Maximum detail (trace logging, full args, all debug events)

  ## Usage

      # Via instance module
      MyApp.Jido.debug(:on)
      MyApp.Jido.debug(:verbose)
      MyApp.Jido.debug(:off)
      MyApp.Jido.debug()          # => :off

      # Via top-level Jido module (applies to Jido.Default)
      Jido.debug(:on)
  """

  @type level :: :off | :on | :verbose
  @type instance :: atom()

  @on_overrides %{
    telemetry_log_level: :debug,
    telemetry_log_args: :keys_only,
    observe_log_level: :debug,
    observe_debug_events: :minimal
  }

  @verbose_overrides %{
    telemetry_log_level: :trace,
    telemetry_log_args: :full,
    observe_log_level: :debug,
    observe_debug_events: :all
  }

  @spec enable(instance(), level(), keyword()) :: :ok
  def enable(instance, level \\ :on, opts \\ [])

  def enable(instance, :off, _opts) do
    disable(instance)
  end

  def enable(instance, level, opts) when level in [:on, :verbose] do
    overrides = build_overrides(level)

    overrides =
      if Keyword.get(opts, :redact) == false do
        Map.put(overrides, :redact_sensitive, false)
      else
        overrides
      end

    :persistent_term.put({:jido_debug, instance}, %{level: level, overrides: overrides})
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
  def level(instance) do
    case :persistent_term.get({:jido_debug, instance}, nil) do
      nil -> :off
      %{level: level} -> level
    end
  end

  @spec enabled?(instance()) :: boolean()
  def enabled?(instance) do
    level(instance) != :off
  end

  @spec override(instance(), atom()) :: term() | nil
  def override(instance, key) do
    case :persistent_term.get({:jido_debug, instance}, nil) do
      nil -> nil
      %{overrides: overrides} -> Map.get(overrides, key)
    end
  end

  @spec maybe_enable_from_config(atom(), instance()) :: :ok
  def maybe_enable_from_config(otp_app, instance) do
    config = Application.get_env(otp_app, instance, [])

    case Keyword.get(config, :debug) do
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
      nil -> %{level: :off, overrides: %{}}
      state -> state
    end
  end

  defp build_overrides(:on), do: @on_overrides
  defp build_overrides(:verbose), do: @verbose_overrides
end
