import { Type } from "@sinclair/typebox";

export const ErrorResponseSchema = Type.Object({
  error: Type.String(),
});

export const AppEnvSchema = Type.Union([
  Type.Literal("development"),
  Type.Literal("staging"),
  Type.Literal("production"),
  Type.Literal("test"),
]);

export const DataSourceSchema = Type.Union([
  Type.Literal("postgres"),
  Type.Literal("supabase"),
]);

export const HealthStatusSchema = Type.Object({
  status: Type.Literal("ok"),
  appEnv: AppEnvSchema,
  dataSource: DataSourceSchema,
  // Which build is answering, so "did my change deploy?" is one request
  // rather than a trip to the Railway dashboard.
  commit: Type.Union([Type.String(), Type.Null()]),
  branch: Type.Union([Type.String(), Type.Null()]),
  startedAt: Type.String(),
});
