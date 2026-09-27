# 3. Contracts flow from TypeBox to OpenAPI to generated TS types

*Inferred from code, confirm or correct.*

**Decision.** Request and response shapes are TypeBox schemas on the Fastify routes
(`apps/api/src/schemas`). These schemas both validate requests and generate
`openapi.generated.json`. `packages/api-client` derives its response types from the generated
`paths`. `@repo/types` holds hand-written domain interfaces and zod form schemas alongside them.
iOS writes its Codable models by hand.

**Consequences.**
- There are three hand-kept copies of the same shapes: TypeBox, `@repo/types` and Swift.
- The generated TS types drift unless `check:api-types` runs. Today it runs only in the husky
  pre-push hook, and it is failing.
- Responses are never validated at runtime on the clients.
