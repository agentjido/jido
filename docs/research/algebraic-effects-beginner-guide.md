# Algebraic Effects: A Beginner-Friendly Explanation

Date: April 11, 2026

This is a companion note to `algebraic-effects.md`. That document focuses on research findings.
This one explains the idea in plain language and uses simple examples.

## Short Version

Algebraic effects are a way to describe side effects without hard-coding how those effects work.

Instead of writing code that directly talks to the world, a computation can say:

- "I need to read some state"
- "I need to raise an error"
- "I need to ask for input"
- "I need to choose between alternatives"

Then a handler decides what those requests actually mean.

That separation is the whole point:

- the computation says what it wants
- the handler decides how to do it

## Why This Feels Useful

Most side effects mix two concerns together:

- the logic of the program
- the mechanics of the runtime

Algebraic effects try to separate those back apart.

For example, imagine a function that needs configuration:

```text
get_config("db_url")
```

In a traditional system, that might mean:

- read an environment variable
- read a config file
- ask a dependency injection container
- use a test stub

With algebraic effects, the function does not need to know which one is happening. It just
performs the `get_config` operation. The handler decides how to answer.

## A Simple Mental Model

Think of an algebraic effect as a named request.

Examples:

- `Read(key)`
- `Raise(error)`
- `Choose(options)`
- `Log(message)`

When code performs one of these requests, control jumps to a handler.

The handler gets:

- the operation name
- the operation arguments
- the rest of the computation, usually called the resumption

The handler can:

- resume immediately
- transform the result
- resume multiple times
- not resume at all

That is what makes handlers more flexible than plain exceptions.

## Exception Analogy

Exceptions are the easiest way to get the intuition.

Traditional exception flow looks like this:

- code raises an exception
- control jumps to a catch block
- the catch block decides what to do
- the original computation does not resume from the raise point

Effect handlers generalize that idea:

- code performs an operation
- control jumps to a handler
- the handler can decide what to do
- unlike exceptions, the handler may resume the suspended computation

So a common summary is:

effect handlers are like exceptions, but resumable

## Tiny Pseudocode Example

Imagine a program that asks for a username:

```text
function greet() {
  let name = perform AskName()
  return "hello, " + name
}
```

That function does not know where the name comes from. It just asks.

A handler could supply a real answer:

```text
handle greet() with {
  AskName() -> resume("Pascal")
}
```

Now `greet()` returns:

```text
"hello, Pascal"
```

In a test, a different handler could supply a fake answer:

```text
handle greet() with {
  AskName() -> resume("Test User")
}
```

The computation stays the same. Only the interpretation changes.

## Why Resumptions Matter

The resumption is what lets handlers do more than simple dependency injection.

Suppose a computation asks for a choice:

```text
function pickDinner() {
  let meal = perform Choose(["ramen", "tacos"])
  return "tonight: " + meal
}
```

A handler could try both choices:

```text
handle pickDinner() with {
  Choose(options, resume) ->
    [resume("ramen"), resume("tacos")]
}
```

Now the result might be:

```text
["tonight: ramen", "tonight: tacos"]
```

That kind of control flow is much harder to express with ordinary exceptions alone.

## How This Differs From Monads

Monads and algebraic effects are often trying to solve overlapping problems:

- structure side effects
- keep pure logic separate from effectful execution
- make effectful programs composable

The difference is mostly in how the programming model feels.

Monadic code often makes the sequencing explicit in the code shape. Algebraic effects aim to let
you write code in a more direct style and defer interpretation to handlers.

That does not make effects strictly "better" than monads in every case. It means they offer a
different tradeoff:

- monads give one kind of discipline and compositionality
- algebraic effects give a more direct style and flexible interpretation model

## What They Are Good At

Algebraic effects tend to fit well for:

- exceptions
- state
- nondeterminism
- generators
- coroutines
- user-level scheduling
- async-like abstractions
- interactive I/O patterns

They work especially well when the effect looks like a structured request that can be interpreted
by a surrounding context.

## What They Are Not Good At

They do not solve every side-effect problem.

Some important effects are not algebraic in the clean theoretical sense. Classical continuations
are the standard example.

There are also practical complications:

- type systems get tricky fast
- polymorphism can become unsound if designed naively
- higher-order effects are harder than first-order ones
- performance depends heavily on runtime strategy

So the honest takeaway is:

algebraic effects are powerful, but not magic

## A Useful Real-World Analogy

A helpful way to think about them is "structured requests plus interpreters."

That looks a lot like patterns people already use:

- command objects
- message passing
- dependency injection
- middleware
- event handlers
- test doubles

Algebraic effects are more principled and more expressive than those analogies, but the analogies
help explain why the idea feels natural.

## The Main Insight to Remember

If you only keep one idea from this topic, keep this one:

Instead of mixing business logic with effect execution, algebraic effects let a computation state
its needs while a separate handler decides how those needs are fulfilled.

That is why the idea keeps showing up in research and in newer language runtime designs.
