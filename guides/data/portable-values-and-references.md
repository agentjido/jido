# Portable Values

Use this reference to choose how a value crosses a storage or JSON boundary, and to look up what each format accepts. Three modules cover this: `Jido.Codec.Value` for tagged JSON data, `Jido.Codec.Reference` for Catalog references, and `Jido.Codec.Term` for BEAM term storage.

| You need to | Use |
| --- | --- |
| Put arbitrary maps and atoms in a JSON document | `Jido.Codec.Value` |
| Name an Action, Flow, or other trusted target in a JSON document | `Jido.Codec.Reference` |
| Check that a term holds no process-local values before storing it as a BEAM term | `Jido.Codec.Term` |

These examples share one Catalog. [Catalog and Discovery](catalog.md) explains how to build it.

```elixir
defmodule PortableGuide.ChargeInvoice do
  use Jido.Action, id: "billing/charge-invoice", vsn: 1, name: "charge_invoice"

  @impl true
  def run(params, _context), do: {:ok, params}
end

catalog =
  Jido.Catalog.from_targets!(PortableGuide.ChargeInvoice, :billing, %{
    {"billing/charge-invoice", 1} => {:action, PortableGuide.ChargeInvoice},
    {"billing/atoms/status", 1} => {:atom, :status},
    {"billing/atoms/paid", 1} => {:atom, :paid}
  })
```

## Tagged values

`Jido.Codec.Value.encode/2` turns a value into JSON-safe data. `Jido.Codec.Value.decode/2` restores it through the same Catalog.

```elixir
alias Jido.Codec.Value

invoice = %{:status => :paid, "lines" => [1, "A-1", nil, true, 2.5], 3 => "third"}

{:ok, encoded} = Value.encode(invoice, catalog)

%{
  "$type" => "map",
  "entries" => [
    %{"key" => 3, "value" => "third"},
    %{"key" => "lines", "value" => [1, "A-1", nil, true, 2.5]},
    %{
      "key" => %{"$type" => "atom", "id" => "billing/atoms/status", "vsn" => 1},
      "value" => %{"$type" => "atom", "id" => "billing/atoms/paid", "vsn" => 1}
    }
  ]
} = encoded

{:ok, ^invoice} = encoded |> JSON.encode!() |> JSON.decode!() |> Value.decode(catalog)
```

The decoded value equals the original, including the atom and integer keys.

### Encoded forms

| Elixir value | Encoded form |
| --- | --- |
| `nil`, Boolean, number | Unchanged |
| Valid UTF-8 binary | Unchanged |
| Proper list | List of encoded items |
| Plain map | `%{"$type" => "map", "entries" => [%{"key" => key, "value" => value}]}` |
| Atom in the Catalog as kind `:atom` | `%{"$type" => "atom", "id" => id, "vsn" => vsn}` |

Map entries are sorted by key: integers, then strings, then atom references, then Booleans. The same value therefore encodes to the same entry order.

A map key can be a valid UTF-8 string, a non-negative integer, a Boolean, or a registered atom. `nil`, floats, negative integers, and other terms are not valid keys.

### Rejected values

Every failure below returns `{:error, %Jido.Codec.Value.Error{}}` unless the table says otherwise. Read its `:reason` and `:path` fields.

| Input | `:reason` |
| --- | --- |
| Struct, tuple, PID, function | `:value` |
| Binary that is not valid UTF-8 | `:string` |
| Improper list | `:list` |
| Unsupported map key | `:map_key` |
| More than 10,000 items in one list or map | `:collection` |
| Nesting deeper than 100 levels | `:depth` |
| On decode: a map without a valid `"$type"` shape | `:tag` |
| On decode: a map entry without exactly `"key"` and `"value"` | `:map_entry` |
| On decode: two entries with the same decoded key | `:duplicate_key` |
| Atom missing from the Catalog, or a reference to an entry of another kind | Returns `%Jido.Catalog.Error{}`, with the location in `details.path` |

```elixir
alias Jido.Codec.Value

{:error, %Value.Error{reason: :value, path: [:status, :status]}} =
  Value.encode(%{status: %{status: {:paid, 500}}}, catalog)

{:error, %Jido.Catalog.Error{message: "Catalog has no reference for the required target"}} =
  Value.encode(:refunded, catalog)
```

`Jido.Codec.Value` checks one value at a time. It does not count the nodes of a whole document. If you write a codec, call `Jido.Codec.Document.check/1` on the complete document. `Jido.Codec.encode/2` and `Jido.Codec.decode/2` do that for you.

## Catalog references

`Jido.Codec.Reference.encode/3` turns a target into a two-field map. `Jido.Codec.Reference.decode/3` resolves that map and checks the entry kind. Both accept one kind or a list of kinds.

```elixir
alias Jido.Codec.Reference

{:ok, reference} = Reference.encode(catalog, :action, PortableGuide.ChargeInvoice)
%{"id" => "billing/charge-invoice", "vsn" => 1} = reference

{:ok, PortableGuide.ChargeInvoice} = Reference.decode(catalog, reference, :action)
{:ok, PortableGuide.ChargeInvoice} = Reference.decode(catalog, reference, [:flow, :action])
```

A reference never holds a module name, so a document cannot name a module that the Catalog does not list. Failures return `%Jido.Catalog.Error{}` with structured details.

```elixir
alias Jido.Codec.Reference

{:error, %{message: "Catalog reference has the wrong entry kind", details: %{expected: :flow, actual: :action}}} =
  Reference.decode(catalog, %{"id" => "billing/charge-invoice", "vsn" => 1}, :flow)

{:error, %{message: "Catalog reference has unsupported vsn", details: %{supported_vsns: [1]}}} =
  Reference.decode(catalog, %{"id" => "billing/charge-invoice", "vsn" => 2}, :action)

{:error, %{message: "Catalog reference must contain only id and vsn", details: %{field: "note"}}} =
  Reference.decode(catalog, %{"id" => "billing/charge-invoice", "vsn" => 1, "note" => "x"}, :action)
```

`Jido.Codec.Reference.parse/1` validates the shape without a Catalog and returns `{:ok, {id, vsn}}`. Resolving a reference only finds an inventory entry. Apply your own authorization before you run the target. See [Flow Security](../flow-runtime/flow-security.md).

## BEAM term storage

`Jido.Codec.Term.validate/2` checks a term that stays in Erlang form, such as a value stored with `:erlang.term_to_binary/1`. It rejects PIDs, ports, references, functions, improper lists, and bitstrings that are not byte aligned. Tuples, atoms, and structs pass, because the BEAM can store them.

`Jido.Session` and `Jido.Thread` use this check for their metadata and payloads.

```elixir
alias Jido.Codec.Term

:ok = Term.validate(%{status: :paid, total: {500, :usd}, link: URI.parse("https://example.com")}, :invoice)

{:error, [:invoice, :order, :caller]} = Term.validate(%{order: %{caller: self()}}, :invoice)
{:error, [:invoice, 1]} = Term.validate([1 | :tail], :invoice)

true = Term.valid?(%{status: :paid})
false = Term.valid?(self())
```

The second argument is the path root, either an atom or a list. The error is a path to the first rejected value, limited to 20 segments. An invalid root returns `{:error, []}`.

A term that passes this check is not always JSON-safe. A tuple passes `Jido.Codec.Term.validate/2` and fails `Jido.Codec.Value.encode/2`.

## Related

- [Jido.Codec Documents](versioned-documents.md) wraps these values in a versioned document.
- [Store Flows as JSON](../flow-data/flow-storage.md) uses tagged values and references for Flow definitions.
