defmodule Jido.Test.Flow.Authoring.Boundaries.Bomb do
  use Jido.Action, name: "authoring_bomb"
  def run(_, _), do: raise("authoring validation ran Action work")
end

defmodule Jido.Test.Flow.Authoring.Boundaries.Inert do
  use Jido.Flow, name: "authoring_inert"

  flow do
    step "bomb",
      action: Jido.Test.Flow.Authoring.Boundaries.Bomb,
      params: %{value: input(:value)}

    output %{value: result("bomb", :value)}
  end
end
