// Pro-Services Univers — proxy Edge Function pour l'Agent IA (Claude).
//
// But : la clé API Anthropic ne doit JAMAIS transiter par le navigateur.
// Cette fonction tourne côté serveur Supabase, lit la clé depuis un secret
// (jamais visible côté client) et relaie l'appel à l'API Claude.
//
// Vérification d'auth : ce projet utilise les nouvelles clés API Supabase
// (sb_publishable_...), donc l'option plateforme "Verify JWT with legacy
// secret" ne s'applique pas à nos jetons de session. Elle est désactivée
// dans Settings → cette fonction, et la vérification est faite ici, à la
// main, via supabase.auth.getUser(token) — qui délègue à Supabase Auth
// plutôt que de vérifier une signature locale. Sans jeton valide : 401.
//
// Déploiement (dashboard, sans CLI) :
//   Edge Functions → claude-chat → coller ce code → redeploy
//   Edge Functions → Secrets → ANTHROPIC_API_KEY = sk-ant-xxxxxxxx
//   Edge Functions → claude-chat → Settings → "Verify JWT with legacy secret" = désactivé

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
// Injectées automatiquement par Supabase dans toutes les Edge Functions.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  // ── Vérification manuelle de la session (remplace la vérification JWT
  //    de plateforme, désactivée pour ce projet) ──────────────────────
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return jsonResponse({ error: "Non authentifié." }, 401);
  }

  const authClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { data: userData, error: userErr } = await authClient.auth.getUser(token);
  if (userErr || !userData?.user) {
    return jsonResponse({ error: "Session invalide ou expirée." }, 401);
  }

  if (!ANTHROPIC_API_KEY) {
    return jsonResponse({ error: "ANTHROPIC_API_KEY non configurée sur le serveur." }, 500);
  }

  let body: { system?: string; message?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Corps de requête JSON invalide." }, 400);
  }

  const message = (body.message || "").trim();
  if (!message) {
    return jsonResponse({ error: "Message vide." }, 400);
  }

  const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 800,
      system: body.system || "",
      messages: [{ role: "user", content: message }],
    }),
  });

  const data = await anthropicRes.json();

  let texte = "";
  if (Array.isArray(data.content)) {
    for (const block of data.content) {
      if (block.type === "text") texte += block.text;
    }
  }

  return jsonResponse({ text: texte || null, error: data.error || null }, anthropicRes.ok ? 200 : anthropicRes.status);
});
