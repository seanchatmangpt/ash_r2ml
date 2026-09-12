# Legacy path: atomics

AshR2RML does not implement an `Ash.DataLayer` and therefore does not implement its own atomic-write execution path.

Ash atomics, bulk writes, transactions, optimistic locking, and mutation semantics belong to Ash and the active data layer.

See [Actions and mutations](actions.md) for the AshR2RML boundary.

