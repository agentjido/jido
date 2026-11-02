defmodule Jido.Signal.Router.RouteTest do
  use JidoSignalTest.Case, async: true

  alias Jido.Signal.Router
  alias Jido.Signal.Router.Route
  alias JidoSignalTest.Fixtures.Signals.UserCreated

  defmodule WildcardType do
    use Jido.Signal, type: "user.*", default_source: "/test"
  end

  describe "normalize/1" do
    test "accepts Route values and all tuple forms" do
      match = fn _signal -> true end
      route = %Route{path: "route.value", target: :route}

      assert {:ok, [^route]} = Router.normalize(route)

      assert {:ok, [%Route{path: "simple", target: :simple}]} =
               Router.normalize({"simple", :simple})

      assert {:ok, [%Route{path: "priority", target: :priority, priority: 10}]} =
               Router.normalize({"priority", :priority, 10})

      assert {:ok, [%Route{path: "matched", match: ^match, target: :matched}]} =
               Router.normalize({"matched", match, :matched})

      assert {:ok,
              [%Route{path: "matched.priority", match: ^match, target: :matched, priority: 20}]} =
               Router.normalize({"matched.priority", match, :matched, 20})
    end

    test "accepts any target term" do
      targets = [noop: [key: "value"], pid: [target: self()]]

      assert {:ok, [%Route{target: ^targets}]} =
               Router.normalize({"target.list", targets})

      assert {:ok, [%Route{target: {:custom, %{value: 1}}}]} =
               Router.normalize({"target.custom", {:custom, %{value: 1}}})
    end

    test "validates paths while it normalizes" do
      assert {:error, error} = Router.normalize({"invalid..path", :target})
      assert error.message == "Path cannot contain consecutive dots"
    end

    test "returns a structured error for an invalid specification" do
      assert {:error, error} = Router.normalize({:invalid, "format"})
      assert error.message == "Invalid route specification format"
    end

    test "accepts a Jido.Signal module as the path" do
      match = fn _signal -> true end

      assert {:ok, [%Route{path: "user.created", target: :created}]} =
               Router.normalize({UserCreated, :created})

      assert {:ok, [%Route{path: "user.created", target: :created, priority: 10}]} =
               Router.normalize({UserCreated, :created, 10})

      assert {:ok, [%Route{path: "user.created", match: ^match, target: :created}]} =
               Router.normalize({UserCreated, match, :created})

      assert {:ok, [%Route{path: "user.created", target: :created}]} =
               Router.normalize(%Route{path: UserCreated, target: :created})
    end

    test "accepts an MFA match predicate" do
      match = {__MODULE__, :always, []}

      assert {:ok, [%Route{path: "matched", match: ^match, target: :matched}]} =
               Router.normalize({"matched", match, :matched})

      assert {:ok,
              [%Route{path: "matched.priority", match: ^match, target: :matched, priority: 20}]} =
               Router.normalize({"matched.priority", match, :matched, 20})
    end

    test "rejects a loaded module that is not a Jido.Signal definition" do
      assert {:error, error} = Router.normalize({String, :target})
      assert error.message == "Expected a route path string or a Jido.Signal module"
      assert error.field == "path"
      assert error.value == String
    end
  end

  describe "path/1" do
    test "returns strings and Signal module types" do
      assert {:ok, "user.created"} = Router.path("user.created")
      assert {:ok, "user.created"} = Router.path(UserCreated)
    end

    test "rejects values that are not a path or Signal module" do
      assert {:error, error} = Router.path(String)
      assert error.message == "Expected a route path string or a Jido.Signal module"

      assert {:error, error} = Router.path(%{})
      assert error.message == "Expected a route path string or a Jido.Signal module"
    end

    test "rejects a wildcard type from a Signal module" do
      assert {:error, error} = Router.path(WildcardType)
      assert error.message == "Signal module type must be an exact route path"
      assert error.value == WildcardType
      assert error.details.type == "user.*"

      assert {:error, error} = Router.new({WildcardType, :target})
      assert error.message == "Signal module type must be an exact route path"
    end
  end

  describe "validate/1" do
    test "uses the Route Zoi schema" do
      route = %Route{path: "test.path", target: :target, priority: 10}

      assert {:ok, ^route} = Zoi.parse(Route.schema(), route)
      assert {:ok, ^route} = Router.validate(route)
      assert {:ok, [^route]} = Router.validate([route])
    end

    test "does not execute Route.match during validation" do
      test_pid = self()

      match = fn _signal ->
        send(test_pid, :match_called)
        true
      end

      route = %Route{path: "test.path", target: :target, match: match}

      assert {:ok, ^route} = Router.validate(route)
      refute_received :match_called
    end

    test "returns the path validation messages" do
      assert {:error, error} =
               Router.validate(%Route{path: "invalid..path", target: :target})

      assert error.message == "Path cannot contain consecutive dots"

      assert {:error, error} =
               Router.validate(%Route{path: "invalid**path", target: :target})

      assert error.message == "Path cannot contain '**' sequence"

      assert {:error, error} =
               Router.validate(%Route{path: "invalid@path", target: :target})

      assert error.message == "Path contains invalid characters"
    end

    test "returns priority and match validation messages" do
      assert {:error, error} =
               Router.validate(%Route{path: "test", target: :target, priority: 101})

      assert error.message == "Priority value exceeds maximum allowed"

      assert {:error, error} =
               Router.validate(%Route{path: "test", target: :target, match: "invalid"})

      assert error.message == "Match must be a unary function or a {module, function, args} MFA"
    end

    test "rejects adjacent multi wildcards at each position" do
      for path <- ["**.**", "**.**.tail", "head.**.**", "head.**.**.tail"] do
        assert {:error, error} = Router.normalize({path, :target})
        assert error.message == "Path cannot contain multiple wildcards"
      end

      assert {:ok, [_route]} = Router.normalize({"**.middle.**", :target})
    end

    test "returns a structured error for invalid input" do
      assert {:error, error} = Router.validate(:invalid)
      assert error.message == "Expected Route struct or list of Route structs"
    end

    test "validates each Route field boundary" do
      assert {:error, "Path must be a string"} = Route.validate_path(:invalid, [])
      assert :ok = Route.validate_priority(nil, [])
      assert :ok = Route.validate_priority(0, [])

      assert {:error, "Priority value below minimum allowed"} =
               Route.validate_priority(-101, [])

      assert {:error, "Priority must be an integer"} = Route.validate_priority("high", [])
      assert :ok = Route.validate_match(nil, [])
      assert :ok = Route.validate_match(fn _signal -> true end, [])
      assert :ok = Route.validate_match({__MODULE__, :always, []}, [])
    end
  end

  def always(_signal), do: true
end
