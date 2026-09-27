# 5. Server state lives in a query cache (TS) or root stores (iOS)

*Inferred from code, confirm or correct.*

**Decision.**
- **Mobile and web** use TanStack Query v5 for all server state, with optimistic mutations for
  the watchlist and notifications. Client state lives in React Context. There is no Redux or
  Zustand.
- **iOS** creates root-scoped `@Observable` stores in `SoonrApp.swift` for state that screens
  share (session, watchlist, notifications, preferences). Per-screen state uses `@Observable`
  models. There is no TCA.

**Consequences.** Both apps implement the same behaviour twice: optimistic rollback, realtime
patching, and 401 refresh-and-retry.
