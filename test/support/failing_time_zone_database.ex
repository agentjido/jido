defmodule JidoTest.Support.FailingTimeZoneDatabase do
  @moduledoc false
  @behaviour Calendar.TimeZoneDatabase

  @impl true
  def time_zone_period_from_utc_iso_days(_iso_days, _time_zone) do
    {:error, :time_zone_not_found}
  end

  @impl true
  def time_zone_periods_from_wall_datetime(_datetime, _time_zone) do
    {:error, :time_zone_not_found}
  end
end
