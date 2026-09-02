# AnyDocSwift Contributor Instructions

These instructions apply to the whole repository.

## Source documents

Read the relevant sections before making changes and follow their requirements:

- [README.md](README.md): consumer API, requirements, supported formats, and
  limitations.
- [docs/architecture.md](docs/architecture.md): module responsibilities,
  runtime behavior, ownership, and invariants.
- [CONTRIBUTING.md](CONTRIBUTING.md): setup, verification, artifact generation,
  and dependency or ABI changes.
- [docs/releasing.md](docs/releasing.md): release authorization, publishing
  sequence, and artifact immutability.

Keep release status, version numbers, architecture explanations, and command
recipes in those documents rather than repeating them here. Verify contracts
against the implementation, tests, and pinned upstream source. If they
conflict, stop and surface the conflict; do not guess, weaken a requirement,
or substitute the latest upstream branch as authority.

## Implementation and testing rules

- Do not add public protocols, factories, registries, format-specific
  converters, or native types.
- Internal seams are allowed only for real variation or deterministic fault
  injection. Do not introduce pass-through wrappers or public test hooks.
- Document unsafe pointer lifetime, bounds, and ownership assumptions next to
  the code that relies on them.
- Changes to documented concurrency, cancellation, error-code, panic, or
  allocation rules require focused tests alongside the implementation.
- Test observable Swift behavior through the public interface. Test below it
  only for ABI behavior that cannot be observed safely from Swift.
- Use deterministic gates, continuations, or canonical events for concurrency
  tests. Do not synchronize with timing sleeps.

## Completion

- Follow the [verification workflow](CONTRIBUTING.md#build-and-test) before
  handing off a change. Do not add no-op scripts or placeholder artifacts to
  make checks appear green.
- Report the exact commands run, their results, and any unverified acceptance
  criteria. Never report an unrun check as passing or claim completion early.
- Keep implementation, documentation, examples, and licensing consistent;
  update affected material together when a contract changes.
- Refer to the upstream library as `anydoc` in lowercase. Preserve the
  `AnyDocSwift` project name and existing API identifiers.
