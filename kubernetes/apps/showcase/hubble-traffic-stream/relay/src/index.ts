import { DurableObject } from "cloudflare:workers";

const RETENTION_MS = 6 * 60 * 60 * 1000;
const MAX_BODY_BYTES = 512;
const MAX_FUTURE_SKEW_MS = 10_000;
const MAX_SAMPLE_AGE_MS = 30_000;
const MIN_WRITE_INTERVAL_MS = 3_000;
const SAMPLE_KEYS = ["dropsPerSecond", "flowsPerSecond", "timestamp"];

export interface Env {
  ALLOWED_ORIGIN: string;
  PRODUCER_TOKEN: string;
  TRAFFIC_RELAY: DurableObjectNamespace<TrafficRelay>;
}

interface TrafficSample {
  timestamp: string;
  flowsPerSecond: number;
  dropsPerSecond: number;
}

interface StoredSample extends Record<string, SqlStorageValue> {
  timestamp: string;
  flows_per_second: number;
  drops_per_second: number;
}

interface LatestSample extends StoredSample {
  received_at: number;
}

function json(body: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...headers,
    },
  });
}

function cors(response: Response, allowedOrigin: string): Response {
  const headers = new Headers(response.headers);
  headers.set("access-control-allow-origin", allowedOrigin);
  headers.set("vary", "Origin");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

async function constantTimeEquals(left: string, right: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [leftHash, rightHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(left)),
    crypto.subtle.digest("SHA-256", encoder.encode(right)),
  ]);
  const leftBytes = new Uint8Array(leftHash);
  const rightBytes = new Uint8Array(rightHash);
  let difference = 0;
  for (let index = 0; index < leftBytes.length; index += 1) {
    difference |= leftBytes[index] ^ rightBytes[index];
  }
  return difference === 0;
}

async function authenticate(request: Request, token: string): Promise<boolean> {
  if (!token) return false;
  const authorization = request.headers.get("authorization") ?? "";
  return constantTimeEquals(authorization, `Bearer ${token}`);
}

function parseSample(value: unknown, now: number): TrafficSample | string {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return "payload must be an object";
  }

  const record = value as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  if (keys.length !== SAMPLE_KEYS.length || keys.some((key, index) => key !== SAMPLE_KEYS[index])) {
    return "payload fields do not match the contract";
  }

  if (typeof record.timestamp !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(record.timestamp)) {
    return "timestamp must be RFC3339 UTC with second precision";
  }

  const timestampMs = Date.parse(record.timestamp);
  if (!Number.isFinite(timestampMs)) return "timestamp is invalid";
  if (timestampMs > now + MAX_FUTURE_SKEW_MS) return "timestamp is too far in the future";
  if (timestampMs < now - MAX_SAMPLE_AGE_MS) return "timestamp is stale";

  for (const field of ["flowsPerSecond", "dropsPerSecond"] as const) {
    const rate = record[field];
    if (typeof rate !== "number" || !Number.isFinite(rate) || rate < 0 || rate > 1_000_000_000) {
      return `${field} must be a finite non-negative number`;
    }
  }

  return {
    timestamp: record.timestamp,
    flowsPerSecond: record.flowsPerSecond as number,
    dropsPerSecond: record.dropsPerSecond as number,
  };
}

function publicSample(row: StoredSample): TrafficSample {
  return {
    timestamp: row.timestamp,
    flowsPerSecond: row.flows_per_second,
    dropsPerSecond: row.drops_per_second,
  };
}

export class TrafficRelay extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS samples (
        timestamp TEXT PRIMARY KEY,
        received_at INTEGER NOT NULL,
        flows_per_second REAL NOT NULL CHECK (flows_per_second >= 0),
        drops_per_second REAL NOT NULL CHECK (drops_per_second >= 0)
      )
    `);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/internal/sample") {
      return this.acceptSample(request);
    }
    if (request.method === "GET" && url.pathname === "/internal/history") {
      return this.history();
    }
    if (request.method === "GET" && url.pathname === "/internal/stream") {
      return this.openStream(request);
    }
    return json({ error: "not found" }, 404);
  }

  private async acceptSample(request: Request): Promise<Response> {
    let value: unknown;
    try {
      value = await request.json();
    } catch {
      return json({ error: "invalid JSON" }, 400);
    }

    const now = Date.now();
    const sample = parseSample(value, now);
    if (typeof sample === "string") return json({ error: sample }, 400);

    const latest = [...this.ctx.storage.sql.exec<LatestSample>(`
      SELECT timestamp, received_at, flows_per_second, drops_per_second
      FROM samples
      ORDER BY timestamp DESC
      LIMIT 1
    `)][0];

    if (latest && sample.timestamp <= latest.timestamp) {
      return json({ error: "timestamp was already accepted or is out of order" }, 409);
    }
    if (latest && now - latest.received_at < MIN_WRITE_INTERVAL_MS) {
      return json({ error: "write rate exceeded" }, 429, { "retry-after": "3" });
    }

    this.ctx.storage.sql.exec(
      `INSERT INTO samples (timestamp, received_at, flows_per_second, drops_per_second)
       VALUES (?, ?, ?, ?)`,
      sample.timestamp,
      now,
      sample.flowsPerSecond,
      sample.dropsPerSecond,
    );
    this.ctx.storage.sql.exec("DELETE FROM samples WHERE received_at < ?", now - RETENTION_MS);

    const message = JSON.stringify({ type: "sample", sample });
    for (const socket of this.ctx.getWebSockets()) {
      try {
        socket.send(message);
      } catch {
        socket.close(1011, "delivery failed");
      }
    }

    return json({ accepted: true }, 202);
  }

  private history(): Response {
    const cutoff = Date.now() - RETENTION_MS;
    const samples = [...this.ctx.storage.sql.exec<StoredSample>(`
      SELECT timestamp, flows_per_second, drops_per_second
      FROM samples
      WHERE received_at >= ?
      ORDER BY timestamp ASC
    `, cutoff)].map(publicSample);
    return json({ windowSeconds: RETENTION_MS / 1000, samples });
  }

  private openStream(request: Request): Response {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return json({ error: "websocket upgrade required" }, 426, { upgrade: "websocket" });
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server);

    const latest = [...this.ctx.storage.sql.exec<StoredSample>(`
      SELECT timestamp, flows_per_second, drops_per_second
      FROM samples
      ORDER BY timestamp DESC
      LIMIT 1
    `)][0];
    server.send(JSON.stringify({ type: "ready", latest: latest ? publicSample(latest) : null }));

    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): void {
    if (message === "ping") {
      socket.send("pong");
      return;
    }
    socket.close(1008, "read only");
  }

  webSocketClose(socket: WebSocket, code: number, reason: string): void {
    socket.close(code, reason);
  }
}

async function relay(request: Request, env: Env): Promise<Response> {
  const stub = env.TRAFFIC_RELAY.getByName("devata");
  const url = new URL(request.url);

  if (request.method === "GET" && url.pathname === "/health") {
    return json({ status: "ok" });
  }

  if (request.method === "OPTIONS" && (url.pathname === "/v1/history" || url.pathname === "/v1/stream")) {
    return cors(new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-methods": "GET, OPTIONS",
        "access-control-max-age": "86400",
      },
    }), env.ALLOWED_ORIGIN);
  }

  if (request.method === "POST" && url.pathname === "/v1/samples") {
    if (!(await authenticate(request, env.PRODUCER_TOKEN))) {
      return json({ error: "unauthorized" }, 401);
    }
    if (request.headers.get("content-type")?.split(";", 1)[0].trim() !== "application/json") {
      return json({ error: "content type must be application/json" }, 415);
    }
    const contentLength = Number(request.headers.get("content-length") ?? "0");
    if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
      return json({ error: "payload too large" }, 413);
    }
    const body = await request.text();
    if (new TextEncoder().encode(body).byteLength > MAX_BODY_BYTES) {
      return json({ error: "payload too large" }, 413);
    }
    return stub.fetch(new Request("https://relay/internal/sample", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body,
    }));
  }

  if (request.method === "GET" && url.pathname === "/v1/history") {
    const response = await stub.fetch(new Request("https://relay/internal/history"));
    return cors(response, env.ALLOWED_ORIGIN);
  }

  if (request.method === "GET" && url.pathname === "/v1/stream") {
    const origin = request.headers.get("origin");
    if (origin && origin !== env.ALLOWED_ORIGIN) {
      return json({ error: "origin not allowed" }, 403);
    }
    return stub.fetch(new Request("https://relay/internal/stream", { headers: request.headers }));
  }

  return json({ error: "not found" }, 404);
}

export default { fetch: relay } satisfies ExportedHandler<Env>;
