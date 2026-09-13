import "dotenv/config";

import { ApnsSender } from "./lib/apns";
import { http2ApnsTransport } from "./lib/apns-transport";
import { env } from "./lib/env";
import { closePostgresPool } from "./lib/postgres";
import {
  deliverPushNotifications,
  postgresPushDeliveryStore,
} from "./lib/push-delivery";

async function main() {
  if (!env.apns) {
    throw new Error(
      "Set APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID and APNS_PRIVATE_KEY to deliver push notifications.",
    );
  }

  const summary = await deliverPushNotifications({
    store: postgresPushDeliveryStore,
    sender: new ApnsSender(env.apns, http2ApnsTransport),
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
