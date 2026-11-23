defmodule Jido.Examples.DistributedAgents.SqliteRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :jido, adapter: Ecto.Adapters.SQLite3
end

defmodule Jido.Examples.DistributedAgents.PostgresRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :jido, adapter: Ecto.Adapters.Postgres
end
