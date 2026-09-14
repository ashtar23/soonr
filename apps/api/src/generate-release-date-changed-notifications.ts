import "dotenv/config";

import { closePostgresPool } from "./lib/postgres";
import {
  generateReleaseDateChangeNotifications,
  postgresReleaseDateChangeStore,
} from "./lib/release-date-change-generation";

async function main() {
  const summary = await generateReleaseDateChangeNotifications({
    store: postgresReleaseDateChangeStore,
  });

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
