# Example tests

The example test tree mirrors the supported source categories in
[`examples/`](../../examples/README.md). The catalog contract is in
[`catalog.yml`](catalog.yml).

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
    JidoTest.Examples.Loader.require_source!("flow/compilation/sample/sample.ex")
    :ok
  end
end
```

Run the catalog or the full offline suite with a fixed seed:

```sh
mix test test/examples/catalog_test.exs --include example --seed 0
mix test.examples
```
