// Cloudflare Worker: كل لعبة على نطاق فرعي مستقل (slug.games.example.com) = عزل حقيقي للتخزين والكوكيز.
// ويعدّ مرات فتح كل لعبة (بلا IP ولا أي بيانات شخصية) في قاعدة D1 اختيارية.
//
// المتغيرات: BASE_DOMAIN (مثل games.example.com) ، ORIGIN (مثل https://my-host.pages.dev)
// الأسرار:    STATS_TOKEN  (لقراءة /stats من تطبيق Game Control)
// الربط:      DB (قاعدة D1 اختيارية؛ بدونها تعمل الاستضافة بلا إحصاء)

const RESERVED = new Set(["api", "www", "stats", "legal", "admin"]);

function today() {
  return new Date().toISOString().slice(0, 10);
}

async function countPlay(env, slug) {
  if (!env.DB) return;
  try {
    await env.DB.prepare(
      "INSERT INTO plays (slug, day, n) VALUES (?1, ?2, 1) ON CONFLICT(slug, day) DO UPDATE SET n = n + 1"
    ).bind(slug, today()).run();
  } catch (_) {}
}

async function stats(request, env, url) {
  const auth = request.headers.get("Authorization") || "";
  if (!env.STATS_TOKEN || auth !== "Bearer " + env.STATS_TOKEN) {
    return new Response("unauthorized", { status: 401 });
  }
  if (!env.DB) return Response.json({ error: "no database bound" }, { status: 501 });
  const days = Math.min(Math.max(parseInt(url.searchParams.get("days") || "7", 10) || 7, 1), 365);
  const since = new Date(Date.now() - (days - 1) * 86400000).toISOString().slice(0, 10);
  const rows = await env.DB.prepare(
    "SELECT slug, SUM(n) AS plays FROM plays WHERE day >= ?1 GROUP BY slug ORDER BY plays DESC LIMIT 300"
  ).bind(since).all();
  return Response.json({ days, since, games: rows.results || [] }, { headers: { "Cache-Control": "no-store" } });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const base = (env.BASE_DOMAIN || "").toLowerCase();
    const host = url.hostname.toLowerCase();
    if (!base || !host.endsWith("." + base)) return new Response("Not found", { status: 404 });
    const slug = host.slice(0, -(base.length + 1));

    if (slug === "api") {
      if (url.pathname === "/stats") return stats(request, env, url);
      return new Response("Not found", { status: 404 });
    }
    if (RESERVED.has(slug) || !/^[a-z0-9][a-z0-9-]{0,59}$/.test(slug)) {
      return new Response("Not found", { status: 404 });
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405 });
    }

    const prefix = "/games/" + slug;
    const upstream = new URL(env.ORIGIN.replace(/\/$/, "") + prefix + url.pathname + url.search);
    const headers = new Headers();
    for (const h of ["range", "if-none-match", "if-modified-since", "accept", "accept-encoding"]) {
      const v = request.headers.get(h);
      if (v) headers.set(h, v);
    }
    const resp = await fetch(upstream.toString(), { method: request.method, headers, redirect: "manual" });

    // إعادات التوجيه الداخلية (مثل إضافة / في النهاية) نعيد كتابتها لتبقى على نطاق اللعبة
    if (resp.status >= 300 && resp.status < 400) {
      const loc = resp.headers.get("Location") || "";
      let p = loc;
      try { p = new URL(loc, upstream).pathname + new URL(loc, upstream).search; } catch (_) {}
      if (p.startsWith(prefix)) p = p.slice(prefix.length) || "/";
      return new Response(null, { status: resp.status, headers: { Location: p } });
    }

    if (resp.status === 200 && (url.pathname === "/" || url.pathname.endsWith("/index.html"))) {
      if (ctx && ctx.waitUntil) ctx.waitUntil(countPlay(env, slug));
    }

    const out = new Response(resp.body, resp);
    out.headers.set("X-Content-Type-Options", "nosniff");
    out.headers.set("Referrer-Policy", "no-referrer");
    out.headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
    return out;
  },
};
