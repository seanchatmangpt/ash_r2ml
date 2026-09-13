# Semantic read plane: post-merge follow-up

PR #36 established the canonical read-only GraphQL projection from admitted `SemanticIR` and merged it to `main`.

The next evidence target is runtime conformance, not additional GraphQL configuration. A consuming runtime should serve the generated contract while keeping backend choice and runtime execution outside the compiler surface.

The follow-up should prove that:

- the generated read contract is consumed without custom GraphQL schema authoring;
- runtime observations are recorded separately from compile-time projection evidence;
- backend selection remains external to the semantic compiler;
- the existing read-only boundary remains unchanged;
- the Palantir/Kudzu migration case study can replay representative reads through an external runtime without changing canonical semantic identity.

Repository Issues are disabled, so the tracking note is attached to merged PR #36 and this document records the same next evidence target in-tree.

Standing remains the standing earned by PR #36. This document does not add runtime evidence by itself.
