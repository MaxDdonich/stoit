/**
 * СТОИТ — Cloudflare Worker.
 * Токен GitHub хранится только в секрете Worker, не в коде и не во фронтенде.
 *
 * Переменные окружения:
 *   GITHUB_REPO        — owner/repo, например MaxDdonich/stoit
 *   WORKFLOW_FILE      — update.yml
 *   GITHUB_REF         — main
 *   ALLOWED_ORIGINS    — https://maxddonich.github.io,http://localhost:8787
 *   COOLDOWN_SECONDS   — 1200
 *   GITHUB_TOKEN       — secret, fine-grained token с Actions: read/write
 *   RATE_LIMIT         — optional KV namespace для строгого лимита
 */

const JSON_TYPE = "application/json; charset=utf-8";

function allowedOrigins(env) {
  return String(env.ALLOWED_ORIGINS || "")
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);
}

function corsHeaders(origin, allowed) {
  const ok = allowed.includes("*") || allowed.includes(origin);
  return {
    "Access-Control-Allow-Origin": ok ? origin : "null",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

function json(data, status, origin, allowed, extra = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": JSON_TYPE,
      "Cache-Control": "no-store",
      ...corsHeaders(origin, allowed),
      ...extra,
    },
  });
}

async function rateLimited(env, key, ttl) {
  // KV — надёжный общий лимит. Без KV используем Cache API как мягкий fallback.
  if (env.RATE_LIMIT) {
    const existing = await env.RATE_LIMIT.get(key);
    if (existing) return true;
    await env.RATE_LIMIT.put(key, "1", { expirationTtl: ttl });
    return false;
  }
  const cache = caches.default;
  const request = new Request(`https://rate.stoit.internal/${encodeURIComponent(key)}`);
  if (await cache.match(request)) return true;
  await cache.put(
    request,
    new Response("1", { headers: { "Cache-Control": `max-age=${ttl}` } })
  );
  return false;
}

async function github(env, path, options = {}) {
  if (!env.GITHUB_TOKEN) throw new Error("GITHUB_TOKEN is not configured");
  const repo = String(env.GITHUB_REPO || "").trim();
  if (!/^[^/]+\/[^/]+$/.test(repo)) throw new Error("GITHUB_REPO must be owner/repo");
  const url = `https://api.github.com/repos/${repo}${path}`;
  const response = await fetch(url, {
    ...options,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "stoit-refresh-worker",
      ...(options.headers || {}),
    },
  });
  return response;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin") || "";
    const allowed = allowedOrigins(env);
    const originOk = allowed.includes("*") || allowed.includes(origin);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(origin, allowed) });
    }

    if (url.pathname === "/health") {
      return json(
        {
          ok: true,
          service: "stoit-refresh",
          configured: Boolean(env.GITHUB_TOKEN && env.GITHUB_REPO),
          cooldownSeconds: Number(env.COOLDOWN_SECONDS || 1200),
          kvRateLimit: Boolean(env.RATE_LIMIT),
        },
        200,
        origin,
        allowed
      );
    }

    if (!originOk) {
      return json({ error: "origin_not_allowed" }, 403, origin, allowed);
    }

    if (url.pathname === "/status" && request.method === "GET") {
      try {
        const response = await github(
          env,
          `/actions/workflows/${encodeURIComponent(env.WORKFLOW_FILE || "update.yml")}/runs?per_page=1`
        );
        if (!response.ok) {
          return json({ error: "github_status_failed", status: response.status }, 502, origin, allowed);
        }
        const data = await response.json();
        const run = data.workflow_runs && data.workflow_runs[0];
        return json(
          {
            ok: true,
            run: run
              ? {
                  status: run.status,
                  conclusion: run.conclusion,
                  createdAt: run.created_at,
                  updatedAt: run.updated_at,
                  url: run.html_url,
                }
              : null,
          },
          200,
          origin,
          allowed
        );
      } catch (error) {
        return json({ error: "server_not_configured", message: error.message }, 500, origin, allowed);
      }
    }

    if (url.pathname === "/refresh" && request.method === "POST") {
      const cooldown = Math.max(60, Number(env.COOLDOWN_SECONDS || 1200));
      const ip = request.headers.get("CF-Connecting-IP") || "unknown";

      try {
        // Глобальный и IP-лимит: 20 минут по умолчанию.
        if (await rateLimited(env, "refresh:global", cooldown)) {
          return json(
            { error: "cooldown", retryAfter: cooldown, message: "Refresh already requested" },
            429,
            origin,
            allowed,
            { "Retry-After": String(cooldown) }
          );
        }
        if (await rateLimited(env, `refresh:ip:${ip}`, cooldown)) {
          return json(
            { error: "cooldown", retryAfter: cooldown, message: "Refresh already requested from this IP" },
            429,
            origin,
            allowed,
            { "Retry-After": String(cooldown) }
          );
        }

        const response = await github(
          env,
          `/actions/workflows/${encodeURIComponent(env.WORKFLOW_FILE || "update.yml")}/dispatches`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ ref: env.GITHUB_REF || "main" }),
          }
        );

        if (response.status !== 204) {
          const text = (await response.text()).slice(0, 500);
          return json(
            { error: "github_dispatch_failed", status: response.status, message: text },
            502,
            origin,
            allowed
          );
        }

        return json(
          { ok: true, started: true, cooldownSeconds: cooldown, message: "Workflow dispatched" },
          202,
          origin,
          allowed
        );
      } catch (error) {
        return json({ error: "server_not_configured", message: error.message }, 500, origin, allowed);
      }
    }

    return json({ error: "not_found" }, 404, origin, allowed);
  },
};
