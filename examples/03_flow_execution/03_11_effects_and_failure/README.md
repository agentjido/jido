# Effects and Failure

Exec returns successful effects in authored component order. It does not
dispatch them. A failed component returns one error and does not expose effects
from failed work.

See [the ExUnit proof](effects_and_failure_test.exs).
