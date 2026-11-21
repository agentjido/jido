defmodule Jido.Test.Signal.Fixtures.Signals do
  @moduledoc false

  alias Jido.Signal

  def signal(type, data \\ %{}) do
    Signal.new!(type, data, source: "/test")
  end

  defmodule DocExampleSignal do
    @moduledoc false

    use Jido.Signal,
      type: "doc.example",
      schema: Jido.Joi.object(%{user_id: Jido.Joi.string(), message: Jido.Joi.string()})
  end

  defmodule UserCreated do
    @moduledoc false

    use Jido.Signal,
      type: "user.created",
      default_source: "/accounts"
  end
end
