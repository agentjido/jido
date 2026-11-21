Code.require_file("support.exs", __DIR__)

defmodule Jido.Persistence.External.MinIOTest do
  use Jido.Test.Case, async: false

  @moduletag :service
  @moduletag timeout: 120_000

  unless Jido.Test.External.MinIO.configured?() do
    @moduletag skip:
                 "set JIDO_SYSTEM_MINIO_URL and dedicated JIDO_SYSTEM_MINIO_ACCESS_KEY and JIDO_SYSTEM_MINIO_SECRET_KEY values"
  end

  use Jido.Test.Persistence.Contracts.Store

  setup_all do
    {:ok, store: Jido.Test.External.MinIO.start_s3!(&on_exit/1)}
  end
end
