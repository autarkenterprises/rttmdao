import express from "express";
import { collectFromEnv } from "./collect.js";
import { jsonSafe } from "./serialize.js";

const POLL_MS = Number(process.env.POLL_MS ?? "25000");
const PORT = Number(process.env.PORT ?? "8080");
const CORS_ORIGIN = process.env.CORS_ORIGIN ?? "*";

let cache = await collectFromEnv();

async function refresh(): Promise<void> {
  cache = await collectFromEnv();
}

setInterval(() => {
  void refresh();
}, POLL_MS);

const app = express();

app.use((_req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", CORS_ORIGIN);
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  next();
});

app.options("*", (_req, res) => res.sendStatus(204));

app.get("/health", (_req, res) => {
  res.json({ ok: true, updatedAt: cache.updatedAt, error: cache.error ?? null });
});

app.get("/api/snapshot", (_req, res) => {
  res.type("application/json");
  res.send(jsonSafe(cache));
});

app.listen(PORT, "0.0.0.0", () => {
  console.info(`rttm-indexer listening on 0.0.0.0:${PORT} poll=${POLL_MS}ms`);
});
