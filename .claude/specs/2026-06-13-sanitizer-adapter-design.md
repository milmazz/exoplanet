# Optional sanitizer adapter (`Exoplanet.Sanitizer`)

**Date:** 2026-06-13
**Issue:** #24 — "Consider recommending (or optionally delegating to) `html_sanitize_ex` … for security-sensitive rendering contexts."
**Status:** Approved

## Problem

`Exoplanet.Filters` ships a built-in HTML sanitizer (`apply_html_filters/2`):
a `LazyHTML` tree-walk that drops `drop_tags`, `drop_attrs`, every `on*`
event handler, and URL-bearing attributes whose scheme is not
`http`/`https`/`mailto`. The moduledoc is explicit that this is
defense-in-depth, **not** a guarantee, and points users at a dedicated
sanitizer such as `html_sanitize_ex` for security-sensitive rendering.

Today there is no supported way to actually *delegate* to such a library —
a consumer would have to post-process `Exoplanet.build/1` output themselves.

## Goal

A small, optional adapter so a consumer can delegate HTML sanitization to a
more comprehensive library. When an adapter is configured it **replaces** the
built-in sanitizer (the built-in is the default for consumers who don't bring
their own). No new runtime dependency: `html_sanitize_ex` is documented as the
canonical example adapter, not added to `mix.exs`.

## Design

### `Exoplanet.Sanitizer` behaviour (new `lib/exoplanet/sanitizer.ex`)

A public extension point with a real `@moduledoc` (mirrors `Exoplanet.Cache`),
one required callback:

```elixir
@callback sanitize(html :: String.t()) :: String.t()
```

The callback receives one HTML field (a post's `body` or `summary`) and returns
sanitized HTML. Canonical adapter, documented in README — **not** a dependency:

```elixir
defmodule MyApp.FeedSanitizer do
  @behaviour Exoplanet.Sanitizer
  @impl true
  def sanitize(html), do: HtmlSanitizeEx.basic_html(html)
end
```

Activated globally via application env (same pattern as `Exoplanet.Cache`):

```elixir
config :exoplanet, sanitizer_adapter: MyApp.FeedSanitizer
```

Set to `nil` or omit to use the built-in sanitizer.

### Wiring into `Exoplanet.Filters`

The adapter is read from application env via a private `sanitizer_adapter/0`
helper (`Application.get_env(:exoplanet, :sanitizer_adapter)`), read per call —
the same approach `Exoplanet.Fetcher` uses for `cache_adapter`. It is **not** a
filter-map key, so `@type t`, `@defaults`, `merge/2`, `normalize_categories/1`,
and `Exoplanet.Config.from_file/1` are all unchanged.

`sanitize_html` remains the master on/off switch. The adapter, when set,
**replaces** the built-in sanitize step:

| `sanitize_html` | adapter set? | sanitize step |
|---|---|---|
| `true` | no | built-in fused walk (today's behavior, unchanged) |
| `true` | yes | `adapter.sanitize/1` only (built-in bypassed) |
| `false` | either | none (adapter does not run) |

`strip_images` and `excerpt_length` are content-shaping, not sanitization, and
run independently in all cases.

**Control flow** in `apply_html_filters/2`:

```
adapter   = sanitizer_adapter()              # nil unless configured
sanitize? = Map.get(filters, :sanitize_html, true)
strip?    = Map.get(filters, :strip_images, false)

cond do
  sanitize? and adapter ->
    # Adapter replaces the built-in. strip_images still applies, after,
    # via the existing image-rewrite walk (sanitize?: false).
    post
    |> run_adapter(adapter)        # adapter.sanitize/1 on :body and :summary
    |> maybe_strip_images(strip?)  # existing strip-only walk when strip? == true

  sanitize? ->
    <existing fused sanitize (+ optional strip_images) path — UNCHANGED>

  strip? ->
    <existing strip-images-only path — UNCHANGED>

  true ->
    post
end
```

- `run_adapter/2` calls the adapter on both `:body` and `:summary`. `nil` →
  `nil`, `""` → `""` (the adapter is not invoked on empty/absent fields).
- The no-adapter paths are the current code, byte-for-byte — no perf or
  byte-equality regression for the common case.

**Order note (strip_images after the adapter):** when both an adapter and
`strip_images` are set, the adapter sanitizes first, then `<img>` rewriting
runs on the adapter's output. The strip-only walk runs with `sanitize?: false`
(no scheme re-check). This is safe because the adapter is the trusted
sanitization authority for that content; a comprehensive adapter such as
`html_sanitize_ex` already enforces a `src` scheme allowlist, so the
image-replacement `href` it produces is already constrained.

### Error handling

A missing/misconfigured adapter (module not loaded, no `sanitize/1`) raises a
normal Elixir error when called — surfacing the misconfiguration loudly. Inside
`Exoplanet.build/1` a raised error is confined to that feed's task and the feed
is dropped with a logged warning (existing `Task.async_stream` backstop); a
direct `Exoplanet.Filters.apply/2` call propagates it to the caller. No special
swallowing is added.

## Testing

New `test/exoplanet/filters_sanitizer_test.exs`, `async: false` (it swaps the
`:sanitizer_adapter` application env; restore with `on_exit`). Uses inline fake
`Exoplanet.Sanitizer` adapters — no new dependency — mirroring how the cache
adapter tests work in `test/exoplanet/fetcher_cache_test.exs`.

Cases:
1. **Adapter replaces the built-in.** Configure an adapter that *keeps* a tag
   the built-in would drop (e.g. wraps output verbatim / keeps `<iframe>`), feed
   HTML containing that tag, assert the tag survives — proving the built-in walk
   was bypassed, not layered.
2. **Adapter effect lands in output.** An adapter that removes a marker (e.g.
   replaces `"SECRET"` with `"***"`); assert the output reflects it.
3. **`sanitize_html: false` ⇒ adapter not called.** Use a recording adapter
   (sends a message / bumps an Agent); assert it was never invoked and body is
   untouched.
4. **`strip_images` still applies with an adapter.** Adapter returns HTML
   containing `<img src="https://e/x.png" alt="A">`; with `strip_images: true`
   assert the `<img>` is rewritten to the text/link replacement in the output
   (proving strip runs after the adapter).
5. **No adapter ⇒ unchanged.** With `:sanitizer_adapter` unset, assert output is
   identical to the current built-in behavior for a representative input
   (regression guard for the fused path).
6. **Adapter invoked on both body and summary**, and skipped for `nil`/`""`
   fields (recording adapter asserts which inputs it saw).

The existing `test/exoplanet/filters_test.exs` is the regression net for the
no-adapter path.

## Documentation

- `Exoplanet.Sanitizer` — full `@moduledoc`: the behaviour, activation via
  app env, the replace semantics, and the `html_sanitize_ex` example adapter.
- `Exoplanet.Filters` moduledoc — note the optional `sanitizer_adapter` app-env
  key and that it replaces the built-in sanitize step when set.
- `README.md` — a "Stronger sanitization" subsection with the example adapter
  and the `config :exoplanet, sanitizer_adapter: …` line. (Per the repo's
  documentation-edit rule, every referenced module/key is verified to exist
  before editing. `Exoplanet.Sanitizer` is a public module, so README/CHANGELOG
  autolinks resolve — no `skip_code_autolink_to` entry needed, unlike the hidden
  `Exoplanet.Fetcher`/`Exoplanet.Parser`.)
- `CHANGELOG.md` — an entry under the unreleased section.
- `CLAUDE.md` — an `Exoplanet.Sanitizer` architecture bullet and a note on the
  Filters bullet that sanitization is delegable.

## Out of scope

- Whether `tel:` belongs in the built-in scheme allowlist (separate #24 item).
- A public helper exposing the built-in sanitizer for adapters that want to
  compose built-in + their own (YAGNI; revisit if a real need appears).
- Adding `html_sanitize_ex` as a dependency.
