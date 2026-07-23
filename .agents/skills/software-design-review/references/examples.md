# Review Examples

## Clear Violation

Change: `analysis` imports `platform_manager.internal.provider_registry`.

Expected result:

- Rule: `BOUNDARY-001`
- Decision: `BLOCK`
- Reason: Cross-module import penetrates an internal path.

## Non-Violation

Change: `app/main.py` initializes multiple modules.

Expected result:

- No SRP finding solely because many modules are initialized.
- Reason: a composition root is allowed to coordinate wiring.

## Ambiguous Case

Change: `ProviderInstaller` validates provider definitions and creates provider
instances.

Expected result:

- At most a warning unless architecture rules define separate owners.
- The finding must explain whether both responsibilities share one reason for
  change.
- Do not report `BLOCK` without project-rule evidence.
