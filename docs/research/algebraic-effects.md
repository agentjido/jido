# Research: Algebraic Effects and Handlers

Date: April 11, 2026

This note interprets "algebraic side-effects" as the standard programming languages term
"algebraic effects and handlers."

## Summary

Algebraic effects are a strong, well-founded way to model many side effects by separating:

- the interface of an effect: operations such as `read`, `raise`, `choose`, or `yield`
- the interpretation of that effect: a handler

The broad research consensus is:

- algebraic effects are a very good abstraction for many first-order effects and control-flow patterns
- they are not a universal replacement for every effect mechanism
- the theory is elegant, but practical language design still has important tradeoffs around typing, performance, higher-order effects, and interoperability

## Core Idea

The foundational picture comes from Plotkin and Power's work on algebraic operations and generic
effects, and Plotkin and Pretnar's work on handling algebraic effects.

At a high level:

- an algebraic effect is described by operations plus equations
- computations live in a free model, or free algebra
- a handler gives a target model, and handling is the induced homomorphism out of the free model

Operationally, this means:

- a computation either returns a value or performs an operation
- performing an operation suspends the rest of the computation
- the handler receives the operation's arguments plus a resumption
- the handler decides whether, when, and how often to resume

This is why effect handlers are often described as "exceptions plus resumability."

## Why They Matter

The main practical appeal is cleaner decomposition.

Instead of baking in exceptions, generators, coroutines, schedulers, or async support as separate
language features, algebraic effects provide a common mechanism:

- effect operations define what a computation wants to do
- handlers define how the runtime or library interprets that request

This separation gives two recurring benefits in the literature:

- effects compose more freely than many ad hoc abstractions
- effect interfaces stay separate from their semantics

Leijen's work on Koka makes this point especially clearly: algebraic effects can be understood as
a restriction of general monads, and that restriction buys more direct composability and cleaner
separation between interface and interpretation.

## What Fits Well

The literature consistently treats these as strong use cases:

- exceptions
- state
- nondeterminism
- interactive I/O
- time
- generators and coroutines
- user-level threads and schedulers
- async and await style abstractions
- probabilistic programming patterns

This is the zone where algebraic effects feel most compelling in practice: structured side effects
and structured control flow that benefit from resumable interpretation.

## Important Limitation: Not All Effects Are Algebraic

One of the most important findings is that algebraic effects do not cover everything.

The standard example is classical continuations. Foundational papers regularly single them out as
the notable non-algebraic case.

So the right mental model is not "algebraic effects replace all side effects." It is:

- they capture a large and useful fragment
- that fragment includes many practical effect patterns
- some important effects still need different machinery or special treatment

## Theory Versus Practice

The mathematics emphasizes operations together with equations. In practice, many implementations
mostly support operations and handlers while giving little or no first-class treatment to the
equational theory.

That matters because equations are where a lot of reasoning power comes from:

- equational reasoning
- optimization opportunities
- effect laws
- modular proofs

Recent research has pointed out this gap directly: many practical "algebraic effects" systems are
really effect operations plus handlers, with only weak use of the fully algebraic part.

## Effect Safety Is a Separate Design Choice

Effect handlers do not automatically imply static effect safety.

Some languages track effects in types:

- Koka uses row-typed effects and effect inference
- Effekt emphasizes lightweight effect safety and typed handlers

Some languages do not:

- OCaml 5 supports effect handlers, but unhandled effects fail at runtime with
  `Effect.Unhandled`

This is an important design lesson: "has algebraic effects" and "has static effect safety" are
separate choices.

## Polymorphism Is Subtle

A major result in the literature is that naive polymorphic algebraic effects are unsound.

Modern systems therefore need restrictions or disciplined typing strategies, such as:

- signature restrictions
- controlled forms of polymorphism
- more careful type-and-effect systems

This is one reason language designs around handlers vary a lot: the core abstraction is elegant,
but type soundness becomes tricky quickly once polymorphism enters the picture.

## Higher-Order Effects Remain Active Research

The modularity story is strongest for first-order operations. Once operations start taking
computations as parameters, the clean decomposition gets harder.

Recent work such as "Hefty Algebras" argues that the standard algebraic-effects story loses some
of its modularity for higher-order effects, and newer elaboration techniques are trying to recover
that lost structure.

This suggests that the field is mature on the basic idea, but still actively evolving at the
frontier.

## Performance Findings

Historically, a common objection was that effect handlers were elegant but too expensive. The
current picture is more nuanced.

Research and production-oriented implementations suggest:

- handlers do not have to be prohibitively slow
- runtime representation matters a great deal
- performance depends heavily on choices such as one-shot versus multi-shot continuations, stack
  management strategy, and whether the implementation is native or library-encoded

Two notable data points:

- Koka showed efficient compilation using row-typed effects and selective CPS
- retrofitting handlers into OCaml reported a mean overhead around 1% on macro benchmarks that do
  not use handlers

So the performance story is no longer "handlers are too slow." It is "handlers can be practical,
but implementation strategy matters."

## OCaml as a Useful Tradeoff Case Study

OCaml 5 is especially useful because it exposes the design tradeoffs clearly:

- handlers generalize exception handling
- the runtime supports deep and shallow handlers
- continuations are one-shot
- effect safety is not checked statically
- effects are synchronous
- effects cannot cross certain FFI boundaries

That is a good reminder that there is no single canonical algebraic-effects design. Real language
implementations balance:

- expressiveness
- safety
- performance
- runtime complexity
- compatibility with existing ecosystems

## Overall Assessment

The strongest synthesis from the literature is:

- algebraic effects are a real and important abstraction, not just theory
- their biggest conceptual win is modular, local interpretation of effectful operations
- their biggest practical win is expressing many side effects and control abstractions in direct
  style without forcing the entire program into a monadic encoding
- their main limitations are equally real:
  - not all effects are algebraic
  - higher-order effects are harder
  - polymorphism is subtle
  - effect safety is optional, not inherent
  - runtime costs depend heavily on implementation strategy

In one sentence:

Algebraic effects are probably the cleanest general-purpose abstraction available for many
structured side effects, but the last mile of typing, higher-order effects, and production runtime
design remains an active research area.

## Primary Sources

- Plotkin and Power, "Algebraic Operations and Generic Effects"
  - https://homepages.inf.ed.ac.uk/gdp/publications/alg_ops_gen_effects.pdf
- Plotkin and Pretnar, "Handling Algebraic Effects"
  - https://homepages.inf.ed.ac.uk/gdp/publications/handling-algebraic-effects.pdf
- Bauer and Pretnar, "Programming with Algebraic Effects and Handlers"
  - https://arxiv.org/abs/1203.1539
- Leijen, "Type Directed Compilation of Row-Typed Algebraic Effects"
  - https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/algeff.pdf
- Koka project page
  - https://www.microsoft.com/en-us/research/project/koka/
- Effekt language site
  - https://effekt-lang.org/
- OCaml 5.3 manual, "Effect Handlers"
  - https://ocaml.org/manual/5.3/effects.html
- OCaml papers page, including "Retrofitting Effect Handlers onto OCaml"
  - https://ocaml.org/papers
- Sekiyama et al., "Signature Restriction for Polymorphic Algebraic Effects"
  - https://www.cambridge.org/core/journals/journal-of-functional-programming/article/signature-restriction-for-polymorphic-algebraic-effects/1FCD90F7590C031791DBE08DCD65CED5
- van der Rest and Bach, "Hefty Algebras: Modular Elaboration of Higher-Order Effects"
  - https://www.cambridge.org/core/services/aop-cambridge-core/content/view/A33FE759BB81EA94A180798C92E16283/S0956796825100142a.pdf/div-class-title-hefty-algebras-modular-elaboration-of-higher-order-effects-div.pdf
- Hillerstrom et al., "Asymptotic Speedup via Effect Handlers"
  - https://www.cambridge.org/core/journals/journal-of-functional-programming/article/asymptotic-speedup-via-effect-handlers/296879DE2FD96FB6CF388F27978C76E4
