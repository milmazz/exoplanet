# Exoplanet

Exoplanet is a feed aggregator library that combines multiple RSS and Atom
sources into a single, unified feed.

Exoplanet downloads news feeds, following the RSS or Atom specs, and aggregates
their content together into a single combined feed. The news will be ordered
based on their publication date, in descending order.

Exoplanet is inspired by [Planet Venus](https://github.com/rubys/venus), and
[NimblePublisher](https://github.com/dashbitco/nimble_publisher). It provides
a flexible and efficient way to aggregate content from various sources.

This library is designed for developers who need to aggregate feeds in their applications.
It provides a simple and efficient way to combine multiple feeds into one.

## Installation

This package can be installed by adding `exoplanet` to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:exoplanet, "~> 0.1.0"}
  ]
end
```

You can find this package documentation at <https://hexdocs.pm/exoplanet>.
