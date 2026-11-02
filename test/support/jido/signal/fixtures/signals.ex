defmodule JidoSignalTest.Fixtures.Signals do
  @moduledoc false

  alias Jido.Signal

  def signal(type, data \\ %{}) do
    Signal.new!(type, data, source: "/test")
  end

  defmodule DocExampleSignal do
    @moduledoc false

    use Jido.Signal,
      type: "doc.example",
      schema: Zoi.object(%{user_id: Zoi.string(), message: Zoi.string()})
  end

  defmodule UserCreated do
    @moduledoc false

    use Jido.Signal,
      type: "user.created",
      default_source: "/accounts"
  end
end
