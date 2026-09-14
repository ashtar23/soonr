import "dotenv/config";

import {
  postgresNotificationRetentionStore,
  pruneNotifications,
} from "./lib/notification-retention";
import { closePostgresPool } from "./lib/postgres";

async function main() {
  const summary = await pruneNotifications(
    { store: postgresNotificationRetentionStore },
    { olderThanDays: parseRetentionDaysArg(process.argv.slice(2)) },
  );

  console.log(JSON.stringify({ ok: true, ...summary }, null, 2));
}

void main()
  .catch((error) => {
    console.error(error instanceof Error ? error.message : "Unknown error");
    process.exitCode = 1;
  })
  .finally(async () => {
    await closePostgresPool();
  });

function parseRetentionDaysArg(args: string[]) {
  const arg = args.find((value) => value.startsWith("--older-than-days="));
  if (!arg) {
    return undefined;
  }

  const [, value = ""] = arg.split("=", 2);
  const parsed = Number.parseInt(value.trim(), 10);
  return Number.isInteger(parsed) ? parsed : undefined;
}
