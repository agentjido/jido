> Target seam design. This document is pending approval.

# Agent authoring design

All requirements and decisions in this document are recommended targets. The
[design review index](../README.md#document-review-status) is the source of
truth for approval. The prerequisite seam documents are pending drafts.

## Scope and owner

- Owner: the `Jido.Agent` authoring boundary.
- In scope: module and Spark authoring, inline route Actions, direct map and
  keyword input, Builder, Agent and Plugin Codecs, trusted Registry use,
  generated interfaces, normalization, validation timing, and static Agent
  extensions.
- Out of scope: Agent value field meaning, Action and Flow execution, Router
  precedence, Plugin runtime behavior, Agent checkpoint format, restore,
  commit, persistence records, Agent identity, and Agent Server lifecycle.
- Adjacent owners: seam 01 owns the canonical Agent definition and definition
  revision. `jido_action` owns executable and inline Action contracts.
  `jido_signal` owns Signals and Router values. Seam 12 owns public error
  classes and codes.

## Model

All supported forms end at one boundary:

```text
module keywords or Spark blocks -- compile and lower --+
direct map or keyword data ----------------------------+--> Agent.new/1
Builder staged data -----------------------------------+        |
Codec document -- trusted Registry and decode ---------+        v
                                                    canonical
                                              neutral Agent definition
```

An Agent instance is a separate result of instantiation. Authoring parity
means that equivalent supported source data produces strictly equal canonical
neutral definitions. It does not mean that every source form has compile-time
functions or syntax.

For a generated Agent module, `agent/0` is the canonical public definition.
`__agent_config__/0` and `__agent_interfaces__/0` are private compiler data.
They are not an Agent value and are not a public authoring document.

Codec supports the portable static subset of the normalized definition. A
valid direct definition can be non-encodable when it contains a route predicate
or static value that the trusted Registry cannot identify. This limit does not
make the direct definition invalid.

## Requirements

EARS syntax does not grant approval. Each requirement is a recommended target.

### Supported forms and canonical normalization

`AUTH-REQ-001`: The Agent authoring boundary shall keep module, Spark, direct
map, direct keyword, Builder, and Codec authoring forms supported.

`AUTH-REQ-002`: When equivalent supported authoring forms succeed, the Agent
authoring boundary shall produce strictly equal canonical neutral Agent
definitions.

`AUTH-REQ-003`: When any authoring form completes, the Agent authoring boundary
shall pass its result through the canonical Agent definition constructor.

`AUTH-REQ-004`: The Agent authoring boundary shall preserve Plugin declaration
order and route declaration order.

`AUTH-REQ-005`: When an authoring input uses unknown core definition fields,
the Agent authoring boundary shall reject the input.

`AUTH-REQ-006`: When direct or module authoring declares route defaults, the
Agent authoring boundary shall use the `defaults` name and not the Flow step
`params` name.

`AUTH-REQ-007`: While the legacy `{target, defaults}` route form remains
supported, the Agent authoring boundary shall preserve its acceptance of map
values, including structs.

`AUTH-REQ-008`: When the explicit `defaults:` option is used, the Agent
authoring boundary shall require a plain map.

### Module and Spark authoring

`AUTH-REQ-009`: When a module uses `Jido.Agent`, the Agent DSL compiler shall
combine keyword fields and Spark block fields into one core configuration.

`AUTH-REQ-010`: If a core field appears in both keyword and Spark block form,
then the Agent DSL compiler shall reject the module at compile time.

`AUTH-REQ-011`: When a generated Agent module exposes `agent/0`, the generated
function shall return the canonical validated neutral definition.

`AUTH-REQ-012`: The Agent DSL compiler shall keep `__agent_config__/0` and
`__agent_interfaces__/0` as private compiler metadata.

`AUTH-REQ-013`: When a generated Agent module exposes construction or direct
command functions, the generated functions shall delegate to the canonical
Agent boundaries.

`AUTH-REQ-014`: Where seam 01 assigns a definition revision to a generated
module, the Agent DSL compiler shall preserve that revision in the canonical
definition.

`AUTH-REQ-015`: Where seam 01 permits an unversioned direct or behavior-only
definition, the Agent authoring boundary shall preserve that compatibility
form.

### Inline route Actions

`AUTH-REQ-016`: When a route declares an inline Action, the Agent DSL compiler
shall compile it through the public `jido_action` inline Action contract.

`AUTH-REQ-017`: If a route declares both a named target and an inline Action,
then the Agent DSL compiler shall reject the route.

`AUTH-REQ-018`: If a route declares more than one inline Action, then the Agent
DSL compiler shall reject the route.

`AUTH-REQ-019`: When an inline route Action compiles, the Agent authoring
boundary shall store an ordinary executable Action target in the canonical
route.

`AUTH-REQ-020`: When `route_action/1` receives an inline route path, the
generated Agent module shall return the compiled Action target for reuse by
direct data, Builder, or Codec Registry entries.

### Generated interfaces

`AUTH-REQ-021`: When a route contains `define`, the Agent DSL compiler shall
generate a tagged Signal constructor, a bang Signal constructor, and a live
call helper for that interface name.

`AUTH-REQ-022`: When a route has no `define`, the Agent DSL compiler shall
generate no route interface for it.

`AUTH-REQ-023`: If `define` refers to a wildcard route, a predicate route, or a
non-unique exact route, then the Agent DSL compiler shall reject the interface.

`AUTH-REQ-024`: If `define` has no valid `signal_source`, then the Agent DSL
compiler shall reject the interface.

`AUTH-REQ-025`: If interface names, generated arities, or existing module
functions conflict, then the Agent DSL compiler shall reject the module.

`AUTH-REQ-026`: When interface arguments are declared, the Agent DSL compiler
shall require unique executable input field names with required fields before
optional fields.

`AUTH-REQ-027`: If an optional positional field can be confused with keyword
options, then the Agent DSL compiler shall require that field through the
`input` option.

`AUTH-REQ-028`: When a generated Signal helper packages input, it shall preserve
omitted fields and explicit `nil`, `false`, and zero values.

`AUTH-REQ-029`: When a generated helper receives positional and named input,
it shall reject a payload key supplied by both sources.

`AUTH-REQ-030`: When a generated Signal helper receives envelope options, it
shall prevent those options from replacing Signal type or data.

`AUTH-REQ-031`: When a generated live helper receives `context` or `timeout`,
it shall keep those values outside Signal data.

`AUTH-REQ-032`: When a generated live helper succeeds or fails, it shall
preserve the public Agent Server call result or exit behavior.

`AUTH-REQ-033`: The generated interface shall document its arities, input
fields, options, validation timing, return behavior, and raise behavior.

`AUTH-REQ-034`: The generated interface shall publish types that match its
actual arities and broad pre-Plugin input contract.

### Builder

`AUTH-REQ-035`: The Agent Builder shall keep the first error that occurs and
shall ignore later staged changes after that error.

`AUTH-REQ-036`: When the Agent Builder appends Plugins or routes, it shall
preserve declaration order in the built definition.

`AUTH-REQ-037`: When the Agent Builder accepts a route, it shall validate that
route target without executing it.

`AUTH-REQ-038`: When the Agent Builder builds a definition or instance, it
shall use the canonical Agent definition and instantiation boundaries.

`AUTH-REQ-039`: Where seam 01 adds definition revision, the Agent Builder shall
accept and preserve that revision without removing old Builder input.

### Codec and trusted Registry

`AUTH-REQ-040`: The Agent Codec shall keep authoring documents separate from
Agent checkpoints and persistence records.

`AUTH-REQ-041`: When Agent Codec encodes a definition or instance, it shall
derive and validate the neutral definition before it encodes static data.

`AUTH-REQ-042`: The Agent Codec shall exclude Agent ID, Agent state, generated
interface metadata, and runtime values from its document.

`AUTH-REQ-043`: When Agent Codec decodes a document, it shall resolve modules,
executables, schemas, Plugins, atoms, route predicates, and static structs only
through a trusted Registry.

`AUTH-REQ-044`: The Agent Codec shall not create atoms or derive module names
from stored strings.

`AUTH-REQ-045`: If a Codec document has an unknown field, unknown version,
invalid tagged record, duplicate decoded key, or value beyond a documented
limit, then the Agent Codec shall reject the document before construction.

`AUTH-REQ-046`: When a Registry alias is used for decode, the trusted Registry
shall resolve it directly to one canonical entry.

`AUTH-REQ-047`: When an encoded value has no trusted Registry identifier, the
Agent Codec shall return an authoring error without changing direct Agent
validity.

`AUTH-REQ-048`: Where seam 01 adds definition revision, the Agent Codec shall
preserve it in a versioned authoring document and shall keep an approved rule
for existing version-1 documents.

`AUTH-REQ-049`: The Plugin Codec shall encode one canonical Plugin declaration
as module and options and shall exclude Plugin state and runtime data.

### Authoring extensions and validation

`AUTH-REQ-050`: When an Agent authoring extension lowers declarations, the
extension host shall run each lowerer in declaration order as a pure static
operation.

`AUTH-REQ-051`: If two extensions claim one route target option, an extension
leaves an entity unclaimed, or a lowerer returns an invalid result, then the
extension host shall reject the authored definition.

`AUTH-REQ-052`: When extension lowering completes, the Agent authoring boundary
shall apply the common Agent definition validation.

`AUTH-REQ-053`: The Agent extension boundary shall provide one documented pure
data-lowering entry that can be used before direct, Builder, or Codec
authoring.

`AUTH-REQ-054`: The Agent Builder and Codec shall accept core configuration
after extension lowering and shall not store Spark extension entities.

`AUTH-REQ-055`: When module compilation can depend on an executable module
declared later in the same source, the Agent DSL compiler shall complete the
dependent executable check after module verification.

`AUTH-REQ-056`: If an authoring operation fails, then the Agent authoring
boundary shall use the approved seam-12 error and bang-function rules.

### Additional generated-interface compatibility

`AUTH-REQ-057`: When a generated Signal helper receives no Signal ID, it shall
use the normal Signal constructor to create a fresh ID.

`AUTH-REQ-058`: When a generated Signal helper constructs a Signal, it shall
preserve the normal Signal constructor time behavior.

`AUTH-REQ-059`: When a generated live helper receives its first argument, it
shall require a Server reference accepted by the public Agent Server call
boundary.

`AUTH-REQ-060`: When a generated helper packages payload data, it shall leave
route-default application to command evaluation.

`AUTH-REQ-061`: When `Builder.new/1` receives a generated Agent module, the
Agent Builder shall copy data that produces the module's canonical `agent/0`
definition.

## Public contract

### Supported forms

| Form | Definition entry | Instance entry | Source-only features |
| --- | --- | --- | --- |
| Direct map or keyword | `Agent.new/1` | `Agent.instantiate/2` | None |
| Agent module and Spark | `module.agent/0` | `module.new/1` or `Agent.new/2` | Compile checks, inline syntax, `define` helpers |
| Builder | `Builder.build/1` | `Builder.build/2` | Staged first-error workflow |
| Codec | `Codec.decode/2` | `Codec.decode/3` | Versioned JSON data and trusted Registry |

Each tagged constructor has its supported bang counterpart. Seam 01 owns the
Agent definition and instance fields. This seam owns how authoring data reaches
those values.

### Spark declaration contract

`agent do` contains domain schema, metadata, and ordered Plugin declarations.
`routes do` contains ordered route declarations and an optional Signal source
for generated interfaces. A route can name one Action or Flow, contain one
inline Action, or use one extension-owned target option. The route can contain
`defaults`, `priority`, `match`, and zero or more `define` entries.

Plugin `config` accepts a map or keyword list. Keyword order is retained. Map
input uses a stable sorted order. The Plugin module is its identity and can
appear once. Plugin labels are not part of the core syntax.

An inline Action receives the complete prepared input map and uses the public
inline Action callback grammar. It is suitable for a small Action owned by one
route. A named Action is clearer when several routes reuse it, it has several
callback clauses, or it needs a separate policy boundary. Flow binding syntax
is not valid inline Action callback syntax.

### Generated interface contract

A `define :name, args: [...]` entry generates these public roles:

```elixir
name_signal(..., opts)    # {:ok, signal} | {:error, error}
name_signal!(..., opts)   # signal or raise
name(server, ..., opts)   # Agent Server call result or exit
```

Required positional inputs come first. Optional positional inputs can be
omitted. `input: %{...}` adds named payload fields. `signal: [...]` supplies
allowed Signal envelope options. Only the live helper accepts `context` and
`timeout`. The helper packages input. Plugin and executable validation occurs
during command evaluation. Route defaults also apply during command
evaluation. A Signal helper uses the normal Signal constructor for ID and time.
The live helper accepts a Server reference, not an immutable Agent value.
Direct evaluation stays explicit through `Agent.cmd/3`.

Generated names that are not valid Elixir variables use safe local argument
names. Collisions receive stable suffixes. Documentation keeps the original
payload field names and declaration order.

### Builder contract

`Builder.new/1` accepts core static fields or a generated Agent module.
`Builder.name/2`, `description/2`, `schema/2`, `metadata/2`, `plugin/3`, and
`route/4` stage data. `build/1` returns a definition. `build/2` returns an
instance. Builder does not run Actions, start processes, or lower Spark
entities.

### Codec and Registry contract

The Agent Codec stores static Agent configuration in a JSON-compatible,
versioned document. The Plugin Codec uses the same Registry and tagged record
format. A generated Registry is for temporary transport and tests. Durable
authoring data uses application-owned stable identifiers.

Registry entry kinds are `agent`, `action`, `flow`, `plugin`, `schema`,
`route_match`, `atom`, and static struct `value`. Route predicates must be
external unary captures to be Registry entries. Direct and Builder definitions
can keep other valid Router predicates, but such definitions are not encodable.

The document limits are 100 nested levels, 100,000 nodes, 10,000 entries per
collection, 10,000 Registry entries, 255 bytes per Registry identifier, and
1 MiB per document string. Closed tagged records carry tuples, maps, atoms,
non-UTF-8 binaries, and trusted static structs.

### Validation timing

| Boundary | Required checks |
| --- | --- |
| Spark syntax | Field overlap, route target count, interface syntax, source, names, arities, and source locations |
| After module verification | Canonical Agent construction and executable schema fields that can depend on later modules |
| Direct and Builder | Input shape, route normalization, executable validity, Plugin declarations, and canonical Agent validation |
| Codec before resolution | Document shape, tags, duplicates, version, and size limits |
| Codec after resolution | Registry kind, static value, route, Plugin, and canonical Agent validation |

The earliest check can differ by form. The final accepted definition cannot
bypass common Agent validation.

## Invariants

- `AUTH-INV-001`: Every successful authoring form ends at one canonical Agent
  definition constructor.
- `AUTH-INV-002`: Definition parity does not include generated module
  functions, compiler metadata, or source syntax.
- `AUTH-INV-003`: Authoring preserves Plugin and route declaration order.
- `AUTH-INV-004`: Inline Actions become ordinary `jido_action` executables.
- `AUTH-INV-005`: Builder and extension lowering do not execute runtime work.
- `AUTH-INV-006`: Codec documents contain static authoring data and are not
  checkpoints or persistence records.
- `AUTH-INV-007`: Stored strings do not create atoms, modules, functions, or
  executable code.
- `AUTH-INV-008`: A valid direct definition can be outside the Codec portable
  subset without becoming invalid.
- `AUTH-INV-009`: Definition revision, Codec document version, checkpoint
  version, Agent state version, and storage revision are separate concepts.

## Downstream guarantees

These guarantees apply only after the related requirements are approved.

| Consumer seam | Guaranteed contract |
| --- | --- |
| 01 Agent | Every form reaches the canonical definition and preserves the Agent-owned revision contract. |
| 04 Turn evaluation | All forms preserve ordered normalized routes and executable targets; this seam does not select a route. |
| 05 Plugins | All forms preserve ordered canonical Plugin declarations; this seam does not define Plugin runtime authority. |
| 07 Persistence | Codec data is not checkpoint data. Revision propagation does not define restore policy. |
| 08 Agent Server | Generated live helpers delegate to the public call boundary and do not redefine live results or timeout meaning. |
| 11 Topology control plane | Static authoring extensions lower before activation and do not add runtime authority. |
| 12 Errors and contracts | Authoring failures use the approved public error and bang rules. |
| 90 Package boundaries | Inline Actions, Signals, Plugins, authoring extensions, and ordinary wrappers keep separate package owners. |
| 99 Delivery | Supported forms remain until a separate staged migration has replacement proof. |

## Open design decisions

All recommendations are pending approval.

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `AUTH-DEC-001` | Which authoring forms remain? | Keep module, Spark, direct map and keyword, Builder, Codec, and neutral definitions. | The historical module-only proposal is retired. |
| `AUTH-DEC-002` | What does authoring parity include? | Compare canonical neutral Agent definitions only. | Module helpers and syntax can differ without creating another Agent contract. |
| `AUTH-DEC-003` | What is the module authority? | Make `agent/0` canonical and keep `__agent_config__/0` private compiler data. | Keyword declarations do not need to be canonical inside private metadata. |
| `AUTH-DEC-004` | Can Codec encode an Agent instance? | Yes. Derive and validate its neutral definition, then encode only static data. | Current instance calls stay supported without repeated state parsing. |
| `AUTH-DEC-005` | Must every valid definition be encodable? | No. Codec supports the Registry-resolvable static subset. | Runtime closures stay valid for direct use and fail clearly at Codec. |
| `AUTH-DEC-006` | How do data users apply extensions? | Publish the pure lowerer; Builder and Codec consume lowered core data only. | Extension syntax does not enter the document format or runtime. |
| `AUTH-DEC-007` | How does definition revision enter authoring? | Apply the approved seam-01 default and preservation rules to all applicable forms. | This seam does not redefine checkpoint or restore policy. |
| `AUTH-DEC-008` | Does explicit route `defaults:` accept structs? | No. Keep the plain-map rule and retain the legacy tuple exception until a staged migration is approved. | Existing tuple input remains compatible. |
