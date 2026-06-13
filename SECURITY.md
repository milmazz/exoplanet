# Security Policy

## Supported versions

Exoplanet is pre-1.0 software. Security fixes are applied to the latest
released version on [Hex](https://hex.pm/packages/exoplanet) and the `main`
branch. Please make sure you are on the most recent release before reporting.

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
discussions, or pull requests.**

Instead, report them privately through GitHub's
[private vulnerability reporting](https://github.com/milmazz/exoplanet/security/advisories/new):

1. Go to the **Security** tab of the
   [exoplanet repository](https://github.com/milmazz/exoplanet/security).
2. Click **Report a vulnerability**.
3. Fill in the advisory form with as much detail as you can (see below).

This keeps the report private between you and the maintainers until a fix is
released, and lets us coordinate a CVE and credit you if you wish.

If you are unable to use private advisories, you can reach the maintainer
through the contact listed on the
[Hex package page](https://hex.pm/packages/exoplanet).

## What to include

A good report lets us reproduce the problem quickly. Where applicable, please
include:

- A description of the issue and its security impact.
- The Exoplanet version (or commit) and your Elixir/OTP versions.
- A minimal feed (RSS/Atom XML snippet) or input that triggers the problem.
- The relevant configuration — especially `filters` settings such as
  `sanitize_html`, `drop_tags`, `drop_attrs`, and `strip_images`.
- A proof of concept, if you have one.

### HTML sanitization issues

Exoplanet renders untrusted, third-party feed content. The built-in
sanitizer in `Exoplanet.Filters` (active when `sanitize_html: true`) is a
primary security boundary: it drops dangerous tags, event-handler and
URL-bearing attributes, and disallowed URL schemes. A bypass that allows
script execution, `javascript:`/`data:` URLs, or other active content to
survive sanitization is a security vulnerability — please report it
privately.

If you use a custom `Exoplanet.Sanitizer` adapter, note that the sanitization
guarantees come from your adapter; bypasses specific to a third-party library
(for example `html_sanitize_ex`) should also be reported to that project.

## Response expectations

This is a volunteer-maintained project, so response times are best-effort.
We aim to acknowledge a report within a few days, agree on a disclosure
timeline with you, and credit reporters in the release notes unless you ask
to remain anonymous.
