# 01 Actions

These offline lessons teach one validated unit of work before Flow
composition.

1. [Input and Output Schemas](01_01_input_output_schemas/README.md) validates
   both Action boundaries with `Jido.Joi`.
2. [Action Context](01_02_action_context/README.md) keeps runtime services and
   execution data outside portable input.
3. [Errors and Output Validation](01_03_errors_and_output_validation/README.md)
   compares an Action error with an invalid successful output.
4. [Effects as Data](01_04_effects_as_data/README.md) returns deferred work
   without dispatching it.
5. [Inline Actions](01_05_inline_actions/README.md) gives one DSL owner a
   private implementation and a normal Action target.
6. [Testing Actions](01_06_testing_actions/README.md) checks success, defaults,
   and invalid input through the public execution boundary.

Run the chapter with:

```sh
mix test.examples examples/01_actions --warnings-as-errors
```

Expected result: all Action examples pass without a process, network access,
credentials, or external services.

One Action uses the same execution model as one Flow. `Jido.Exec` lowers the
Action to a canonical one-step Flow before it runs.
