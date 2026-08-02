import { env, runInDurableObject, SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

const endpoint = "https://telemetry.pragalva.me/v1/samples";

function timestamp(offsetMs = 0): string {
  return new Date(Math.floor((Date.now() + offsetMs) / 1000) * 1000).toISOString().replace(".000Z", "Z");
}

function sample(at = timestamp()): Record<string, unknown> {
  return {
    timestamp: at,
    flowsPerSecond: 146.4,
    dropsPerSecond: 0.048,
  };
}

function publish(body: Record<string, unknown>, token = "test-producer-token"): Promise<Response> {
  return SELF.fetch(endpoint, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

describe("traffic relay", () => {
  it("uses the timestamp primary-key index for retention queries", async () => {
    const stub = env.TRAFFIC_RELAY.getByName("devata");
    const plans = await runInDurableObject(stub, (_instance, state) => ({
      cleanup: [
        ...state.storage.sql.exec<{ detail: string }>(
          "EXPLAIN QUERY PLAN DELETE FROM samples WHERE timestamp < ?",
          timestamp(-6 * 60 * 60 * 1000),
        ),
      ],
      history: [
        ...state.storage.sql.exec<{ detail: string }>(
          "EXPLAIN QUERY PLAN SELECT timestamp FROM samples WHERE timestamp >= ? ORDER BY timestamp ASC",
          timestamp(-6 * 60 * 60 * 1000),
        ),
      ],
    }));

    expect(plans.cleanup.map(({ detail }) => detail).join(" ")).toContain("INDEX");
    expect(plans.history.map(({ detail }) => detail).join(" ")).toContain("INDEX");
  });

  it("rejects a bad credential", async () => {
    const response = await publish(sample(), "wrong-token");
    expect(response.status).toBe(401);
  });

  it("rejects extra fields", async () => {
    const response = await publish({ ...sample(), node: "must-not-leave-devata" });
    expect(response.status).toBe(400);
  });

  it("accepts one closed payload, then enforces replay and write-rate limits", async () => {
    const at = timestamp();
    const body = sample(at);
    expect((await publish(body)).status).toBe(202);

    const response = await publish(sample(timestamp(5_000)));
    expect(response.status).toBe(429);
    expect(response.headers.get("retry-after")).toBe("3");

    expect((await publish(body)).status).toBe(409);

    const history = await SELF.fetch("https://telemetry.pragalva.me/v1/history", {
      headers: { origin: "https://pragalva.me" },
    });
    expect(history.status).toBe(200);
    expect(history.headers.get("access-control-allow-origin")).toBe("https://pragalva.me");
    expect(await history.json()).toEqual({ windowSeconds: 21600, samples: [body] });
  });

  it("accepts a WebSocket only from the portfolio origin", async () => {
    const denied = await SELF.fetch("https://telemetry.pragalva.me/v1/stream", {
      headers: { upgrade: "websocket", origin: "https://example.com" },
    });
    expect(denied.status).toBe(403);

    const connected = await SELF.fetch("https://telemetry.pragalva.me/v1/stream", {
      headers: { upgrade: "websocket", origin: "https://pragalva.me" },
    });
    expect(connected.status).toBe(101);
    connected.webSocket?.accept();
    connected.webSocket?.close(1000, "test complete");
  });
});
