import type { FastifyInstance } from "fastify";

import { env } from "../lib/env";
import { HealthStatusSchema } from "../schemas/common";

// Process start, so a restart is visible as well as a redeploy.
const startedAt = new Date().toISOString();

export function registerSystemRoutes(server: FastifyInstance) {
  server.get(
    "/health",
    {
      schema: {
        tags: ["system"],
        summary: "Get API health status",
        response: {
          200: HealthStatusSchema,
        },
      },
    },
    async () => {
      return {
        status: "ok",
        appEnv: env.appEnv,
        dataSource: env.dataSource,
        commit: env.commitSha,
        branch: env.branch,
        startedAt,
      };
    },
  );
}
