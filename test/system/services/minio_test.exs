Code.require_file("support/minio.exs", __DIR__)

defmodule JidoTest.System.Services.MinIOTest do
  use JidoTest.Case, async: false

  @moduletag :service
  @moduletag timeout: 120_000

  unless JidoTest.System.Services.MinIO.configured?() do
    @moduletag skip:
                 "set JIDO_SYSTEM_MINIO_URL and dedicated JIDO_SYSTEM_MINIO_ACCESS_KEY and JIDO_SYSTEM_MINIO_SECRET_KEY values"
  end

  use JidoTest.Persistence.Contracts.Store

  setup_all do
    {:ok, store: JidoTest.System.Services.MinIO.start_s3!(&on_exit/1)}
  end
end
