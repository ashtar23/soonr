import { connect } from "node:http2";

import type { ApnsResponse, ApnsTransport } from "./apns";

const requestTimeoutMs = 10_000;

/**
 * APNs over HTTP/2, one session per request.
 *
 * Sending happens in batches on a schedule rather than continuously, so the
 * pooling a long-lived session buys does not apply, and a session that is
 * never reused cannot go stale between runs.
 */
export const http2ApnsTransport: ApnsTransport = {
  post({ host, path, headers, body }) {
    return new Promise<ApnsResponse>((resolve, reject) => {
      const session = connect(`https://${host}`);
      let settled = false;

      const finish = (outcome: () => void) => {
        if (settled) {
          return;
        }

        settled = true;
        session.close();
        outcome();
      };

      session.on("error", (error) => finish(() => reject(error)));

      const request = session.request({
        ":method": "POST",
        ":path": path,
        ...headers,
      });
      request.setTimeout(requestTimeoutMs, () => {
        request.close();
        finish(() => reject(new Error(`APNs request to ${host} timed out.`)));
      });

      let statusCode = 0;
      let responseBody = "";

      request.on("response", (responseHeaders) => {
        statusCode = Number(responseHeaders[":status"] ?? 0);
      });
      request.on("data", (chunk: Buffer) => {
        responseBody += chunk.toString("utf8");
      });
      request.on("error", (error) => finish(() => reject(error)));
      request.on("end", () =>
        finish(() => resolve({ statusCode, body: responseBody })),
      );

      request.end(body);
    });
  },
};
