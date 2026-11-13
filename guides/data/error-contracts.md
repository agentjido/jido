# Jido Error Contracts

Use this reference to create Jido errors, branch on them in code, and return them safely across a transport boundary. `Jido.Error` defines the shared error types.

Match on the struct, the public type, or the stable code. Do not match on a message, because message text can change.

## Error types

Jido has five error structs. Each one has a `:message`, a `:details` map, and the fields below. `Jido.Error.type/1` maps each one to a public type.

| Struct | Extra fields | Public type |
| --- | --- | --- |
| `Jido.Error.ValidationError` | `:kind`, `:subject`, `:code`, `:path` | `:validation_error`. With `kind: :action`, `:invalid_action`. With `kind: :config`, `:config_error`. With `code: :unmatched_input`, `:routing_error` |
| `Jido.Error.ExecutionError` | `:phase` | `:execution_error`. With `phase: :planning`, `:planning_error` |
| `Jido.Error.RoutingError` | `:target` | `:routing_error` |
| `Jido.Error.TimeoutError` | `:timeout` | `:timeout` |
| `Jido.Error.InternalError` | None | `:internal` |

## Create an error

Each constructor takes a message and options. Keys that a constructor does not reserve go into `:details`, and an explicit `:details` map wins over those keys.

```elixir
alias Jido.Error

%Error.ValidationError{kind: :input, subject: :email} =
  Error.validation_error("Invalid email", kind: :input, subject: :email)

%Error.ValidationError{kind: :action, subject: Billing.ChargeInvoice} =
  Error.validation_error("Unknown Action", kind: :action, subject: Billing.ChargeInvoice)

%Error.ValidationError{kind: :config, details: %{setting: :timeout}} =
  Error.config_error("Bad timeout", setting: :timeout)

%Error.ExecutionError{phase: :execution, details: %{invoice: "INV-7"}} =
  Error.execution_error("Charge failed", invoice: "INV-7")

%Error.ExecutionError{phase: :planning} = Error.execution_error("No plan", phase: :planning)

%Error.RoutingError{target: "invoice.paid"} = Error.routing_error("No route", target: "invoice.paid")

%Error.TimeoutError{timeout: 5_000} = Error.timeout_error("Gateway timed out", timeout: 5_000)


%Error.InternalError{details: %{reason: :closed}} = Error.internal_error("Socket closed", reason: :closed)
```

### Validation results with a code and path

`Jido.Error.validation_result/4` returns an error tuple with a code and field path. Use it in your own decoders and validators. `Jido.Error.prefix_result_path/2` adds a prefix as the result moves up through nested data, and leaves other results alone.

```elixir
alias Jido.Error

{:error, %Error.ValidationError{code: :missing_number, path: [:number]}} =
  result = Error.validation_result(:missing_number, :number, "Number is required")

{:error, %{path: [:invoices, 0, :number]}} = Error.prefix_result_path(result, [:invoices, 0])
{:ok, :unchanged} = Error.prefix_result_path({:ok, :unchanged}, [:invoices])
```

`Jido.Error.prefix_path/2` does the same for a path stored in `details.path`.

## Branch in code

| Function | Returns | Accepts |
| --- | --- | --- |
| `Jido.Error.type/1` | One public type | Any term |
| `Jido.Error.code/1` | A registered code, or `nil` | Error value, `{:error, reason}`, or `{:error, reason, effects}` |
| `Jido.Error.retryable?/1` | Boolean | Error value, the same tuples, a public type, or any term |

```elixir
alias Jido.Error

failure = Error.execution_error("Callback failed", code: :agent_callback_failed)

:execution_error = Error.type(failure)
:agent_callback_failed = Error.code(failure)
:agent_callback_failed = Error.code({:error, failure})
true = Error.retryable?(failure)

nil = Error.code(Error.execution_error("Other", code: :my_app_code))
```

### Stable codes

`Jido.Error.code/1` returns only codes in the closed set from `Jido.Error.stable_codes/0`, read from `details.code` or a `:code` field. Any other code returns `nil`. To match a code that is not in the set, such as `:unmatched_input`, match the struct field: `%Jido.Error.ValidationError{code: :unmatched_input}`.

```elixir
[
  :non_portable_term,
  :invalid_checkpoint,
  :definition_mismatch,
  :agent_invalid_callback_result,
  :agent_callback_failed,
  :plugin_state_owner_violation,
  :plugin_invalid_callback_result,
  :plugin_callback_failed,
  :plugin_callback_timeout,
  :plugin_callback_task_failed,
  :persistence_invalid_callback_result,
  :persistence_callback_failed,
  :agent_exec_invalid_callback_result,
  :agent_exec_callback_failed,
  :agent_exec_callback_timeout,
  :agent_exec_callback_task_failed,
  :agent_turn_timeout,
  :missing_env,
  :invalid_env,
  :invalid_config,
  :jido_instance_invalid_config,
  :jido_namespace_already_bound,
  :jido_namespace_required,
  :jido_namespace_mismatch
] = Jido.Error.stable_codes()
```

### Retry decisions

`Jido.Error.retryable?/1` returns `false` for `:validation_error`, `:invalid_action`, and `:config_error`. It returns `true` for every other type. A Boolean hint overrides that result. Jido looks for `:retry`, `:retryable`, or `:retryable?` on the error, and then in nested `:details` and `:reason` values, up to four levels.

```elixir
alias Jido.Error

true = Error.retryable?(Error.timeout_error("Gateway timed out"))
false = Error.retryable?(Error.timeout_error("Invoice is locked", retryable: false))
false = Error.retryable?(Error.validation_error("Bad total"))
true = Error.retryable?(Error.validation_error("Stale form", details: %{retry: true}))
```

The result is a default for your policy. It does not make an operation safe to repeat. An Action with side effects needs its own idempotency. See [Execution Policy](../actions/action-execution-policy.md).

## Return an error across a boundary

`Jido.Error.to_map/1` converts any error into a map with exactly `:type`, `:message`, `:details`, and `:retryable?`. Use it for HTTP responses, logs, and other reports.

```elixir
alias Jido.Error

%{
  type: :validation_error,
  message: "Invalid email",
  details: %{kind: :input, subject: :email},
  retryable?: false
} = Error.to_map(Error.validation_error("Invalid email", kind: :input, subject: :email))
```

The struct fields, such as `:kind`, `:phase`, `:code`, and `:path`, appear inside `:details`. The projection has no top-level `:code`.

### Sanitized details

The projection bounds and cleans `:details` as it copies them.

| Rule | Limit or result |
| --- | --- |
| Container depth | 4 levels. Deeper containers become `"[DEPTH_LIMIT]"` |
| Items in one map or list | 20. The rest are dropped |
| String length | 512 characters, followed by `"...(truncated)"` |
| Nested error groups | 2 |
| Key contains `apikey`, `authorization`, `credential`, `password`, `privatekey`, `query`, `secret`, or `token` | Value becomes `"[REDACTED]"` |
| Key contains `stacktrace` | Value becomes `"[OMITTED]"` |
| PID, function, reference, tuple | An inspected string |
| Exception | A map with `:type` and `:message` |
| Improper list | `"[IMPROPER LIST]"` |

Key checks ignore letter case and punctuation, so `api_key`, `API-Key`, and `apiKey` all match.

```elixir
alias Jido.Error

error =
  Error.internal_error("Gateway failed",
    details: %{
      api_key: "sk-example",
      stacktrace: ["frame"],
      caller: self(),
      request: %{gateway: %{attempt: %{detail: %{step: 1}}}}
    }
  )

%{
  api_key: "[REDACTED]",
  stacktrace: "[OMITTED]",
  caller: "#PID<" <> _,
  request: %{gateway: %{attempt: %{detail: "[DEPTH_LIMIT]"}}}
} = Error.to_map(error).details
```

The rules key off field names. A secret under an innocent key, or inside a message, passes through, so keep secrets out of errors when you create them. See [Security Model](../operations/security.md).

## Normalize a foreign failure

Each domain converts foreign failures at its own boundary. Use a shared constructor with explicit details.

`CompensationError`, `compensation_error/2`, and `normalize/1` are removed.
Represent a compensation failure with `execution_error/2` and domain details.
Use explicit `kind:` and `subject:` options in `validation_error/2`.
The `field:` and `action:` keys are ordinary details and do not select a kind or subject.

`Jido.Error.to_map/1` and `Jido.Error.type/1` also accept values that are not Jido errors. A map with a recognized `:type` or `:class` uses that type. A map with an atom `:code` and a list `:path` becomes `:validation_error`. Everything else becomes `:internal`.

## Combine errors

`Jido.Error` uses [Splode](https://hexdocs.pm/splode). Its `to_class/1` function groups several errors into one class error, and `Jido.Error.unwrap!/1` returns an `:ok` value or raises the error. Classes in order of precedence are `:invalid`, `:execution`, `:routing`, `:timeout`, and `:internal`.

```elixir
alias Jido.Error

%Error.Invalid{errors: [_, _]} =
  combined = Error.to_class([Error.validation_error("Bad total"), Error.execution_error("Gateway down")])

[%{type: :validation_error}, %{type: :execution_error}] = Error.to_map(combined).details.errors

:charged = Error.unwrap!({:ok, :charged})
```

## Errors outside this taxonomy

Some modules keep their own error values, so read their guides for the details:

- `Jido.Joi` returns a list of [validation issues](joi-validation.md).
- `Jido.Codec` returns `Jido.Codec.Issue` values and `Jido.Codec.Error` exceptions. See [Jido.Codec Documents](versioned-documents.md).
- `Jido.Catalog` returns `Jido.Catalog.Error` from lookups and tagged tuples from construction. See [Catalog and Discovery](catalog.md).
- `Jido.Session` and `Jido.Thread` return atoms such as `:invalid_session`. See [Sessions and Threads](sessions-and-threads.md).

## Related

- [Flow Errors](../flow-runtime/flow-errors.md) covers failures in Flows.
- Errors and Async introduces error tuples for TypeScript developers.
