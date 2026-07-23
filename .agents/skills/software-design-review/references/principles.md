# Design Review Principles

Use these principles only when supported by concrete evidence from the diff,
architecture rules, scripts, or nearby code.

## Single Responsibility

Identify responsibility clusters using:

- public method verbs;
- domain concepts manipulated;
- state owned;
- external systems coordinated;
- independent reasons for change.

Do not use file length alone as evidence. Flag a component only when it contains
multiple responsibility clusters that are likely to change for different
reasons.

Composition roots, bootstrappers, and wiring modules may legitimately coordinate
many dependencies without violating single responsibility.

## Open/Closed

Perform a hypothetical extension test:

> To add one more implementation of the same category, which existing core files
> must be modified?

Report extension cost as the number of existing core files requiring
modification.

Flag:

- repeated type switches;
- provider-specific branches outside adapters;
- duplicated registration logic;
- changes required in multiple unrelated core files.

## Dependency Inversion

Check whether high-level modules depend on:

- public abstractions;
- internal services;
- ORM models;
- vendor SDKs;
- concrete adapters.

Cross-module internal or concrete dependencies are violations unless explicitly
allowed by architecture rules.

## Interface Segregation

For changed interfaces, compare:

- total interface operations;
- operations used by each consumer;
- unsupported operations;
- implementation-specific optional fields.

Flag broad interfaces when consumers use disjoint subsets or implementations
must provide meaningless methods.

## Substitutability

Check whether implementations satisfy the same behavior contract.

Prefer contract-test evidence. Flag:

- implementation-specific exceptions;
- stronger input preconditions;
- weaker output guarantees;
- empty or unsupported methods;
- caller-side type checks.
