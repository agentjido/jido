defmodule JidoSignalTest.Fixtures.Diagnostics do
  @moduledoc false
  @struct_name Module.concat(__MODULE__, String.duplicate("S", 180))
  @error_name Module.concat(__MODULE__, String.duplicate("E", 180))

  defmodule @struct_name do
    @moduledoc false
    defstruct [:value]
  end

  defmodule @error_name do
    @moduledoc false
    defexception [:message, :value]
  end

  def values do
    [struct(@struct_name, value: "safe"), struct(@error_name, message: "safe", value: "safe")]
  end
end
