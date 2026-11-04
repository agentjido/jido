# Example tests

The public [example tree](../../examples/README.md) and this test tree use the
same flat chapter and lesson names. The catalog in
[`catalog.yml`](catalog.yml) pairs each source lesson with its test.

Every paired test must:

- use the `:example` tag;
- load its primary source in `setup_all` with
  `JidoTest.Examples.Loader.require_source!/1`;
- make exact assertions about the documented result;
- run without provider keys or external services.

This pattern prevents default `mix test` from loading example source:

```elixir
Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.SampleTest do
  use ExUnit.Case, async: false
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!(
      "02_flow_authoring/02_01_sample/sample.ex"
    )
    :ok
  end
end
```

Run the catalog or the full offline suite with a fixed seed:

```sh
mix test test/examples/catalog_test.exs --include example --seed 0
mix test.examples
```
