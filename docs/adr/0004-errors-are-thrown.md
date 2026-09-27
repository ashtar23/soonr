# 4. Errors are thrown, not returned as a Result

*Inferred from code, confirm or correct.*

**Decision.**
- The server answers every error as `{ error: string }` (`apps/api/src/schemas/common.ts:3`).
- The TS clients throw `ApiClientError{status, method, path}`.
- iOS throws `APIError` and maps it to a typed `FailureReason` for the UI.

**Consequences.**
- This differs from playbook rule 14, which says to return a `Result` across an API boundary.
- 500 responses echo `error.message` (`routes/shared.ts:70`), which leaks internal details. That
  should change whichever style is kept.
