# Identifiers and UUIDv7

`Jido.Id` creates and checks the UUID formats that Jido uses. Use this reference to generate IDs, read their timestamps, and compare them.

## Create and check a UUIDv7

`Jido.Id.uuid7/0` returns a lower-case RFC 9562 UUIDv7 string. It holds a Unix millisecond timestamp followed by random data.

```elixir
alias Jido.Id

invoice_id = Id.uuid7()

true = Id.uuid7?(invoice_id)
false = Id.uuid7?("INV-7")
false = Id.uuid7?(nil)

36 = byte_size(invoice_id)
true = is_integer(Id.uuid7_timestamp(invoice_id))
```

`Jido.Id.uuid7?/1` accepts any term and returns a Boolean. It accepts upper-case and mixed-case hexadecimal.

`Jido.Id.uuid7_timestamp/1` returns milliseconds since the Unix epoch. It raises `ArgumentError` when the value is not a valid UUIDv7.

## Compare and sort

`Jido.Id.compare_uuid7/2` compares the binary value of two IDs and returns `:lt`, `:eq`, or `:gt`. It ignores letter case, and it raises `ArgumentError` for an invalid ID.

```elixir
alias Jido.Id

first = Id.uuid7()
Process.sleep(2)
second = Id.uuid7()

:lt = Id.compare_uuid7(first, second)
:gt = Id.compare_uuid7(second, first)
:eq = Id.compare_uuid7(first, String.upcase(first))
```

The ordering has limits:

- IDs from different milliseconds sort by time.
- IDs from the same millisecond sort in random order. `Jido.Id` keeps no sequence counter.
- The timestamp comes from the system clock, so a clock change on the node also changes the order.

When order inside one sequence matters, use a value that records it. `Jido.Thread.Entry` carries a `:seq` number for this reason.

## Format a UUIDv8 from your own bytes

`Jido.Id.uuid8/1` formats the first 16 bytes of a binary as a UUIDv8, and sets the version and variant bits. The same bytes give the same ID. It does not hash its input, so hash first when you need a deterministic ID for a longer value.

```elixir
alias Jido.Id

digest = :crypto.hash(:sha256, "invoice:INV-1")

"3c546e42-1f82-8ebe-bc6f-04c15e303aa8" = Id.uuid8(digest)
false = Id.uuid7?(Id.uuid8(digest))
```

A binary shorter than 16 bytes raises `ArgumentError`. You own the meaning and stability of those bytes. Jido provides no UUIDv8 validator or parser.

## Where Jido creates IDs

| Value | Default form |
| --- | --- |
| `Jido.Signal` | A plain UUIDv7 in `:id`, when you do not supply one |
| Turn | A plain UUIDv7 in `:turn_id` |
| `Jido.Session` | `"session_"` followed by a UUIDv7 |
| `Jido.Thread` | `"thread_"` followed by a UUIDv7 |
| `Jido.Thread.Entry` | `"entry_"` followed by a UUIDv7 |
| `Jido.Flow` identity | A UUIDv8 from the Flow digest |

`Jido.Id.uuid7?/1` returns `false` for the prefixed forms. Strip the prefix before you check one. [Flow Identity](../flow-data/flow-identity-and-versioning.md) explains the Flow value. W3C trace and span IDs use a different format, described in [Trace Context](trace-context.md).

Catalog IDs are a separate kind of identifier. A Catalog ID is a stable name that you choose, such as `"billing/charge-invoice"`. See [Catalog and Discovery](catalog.md).
