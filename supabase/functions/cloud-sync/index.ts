// Pro-Services Univers — proxy Edge Function pour la synchronisation cloud.
//
// But : les données métier partagées (clients, factures, stock, finance,
// logistique, santé, points de vente...) ne doivent plus être lues/écrites
// depuis le navigateur avec une clé Supabase collée en clair dans
// localStorage (ancien mécanisme, vulnérable au vol de clé via une faille
// XSS). Cette fonction tourne côté serveur : elle vérifie la session de
// l'utilisateur connecté (Supabase Auth), puis effectue l'opération avec
// la clé de service — jamais exposée au client.
//
// Vérification d'auth : comme claude-chat, la vérification JWT de
// plateforme est désactivée pour ce projet (clés API nouvelle génération) ;
// on vérifie ici, à la main, via supabase.auth.getUser(token). Sans jeton
// de session valide : 401.
//
// Déploiement (dashboard, sans CLI) :
//   Edge Functions → New function → nom "cloud-sync" → coller ce code → Deploy
//   Edge Functions → cloud-sync → Settings → "Verify JWT with legacy secret" = désactivé
//   (SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY sont injectées
//   automatiquement par Supabase dans chaque Edge Function — rien à ajouter.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Liste blanche stricte : la fonction ne touche jamais une table hors de
// cette liste, même si le client en demande une autre (ex: "profiles").
const TABLES_AUTORISEES = new Set([
  "finance_operations",
  "finance_soldes",
  "stock_quantites",
  "stock_mouvements",
  "commerce_clients",
  "commerce_factures",
  "points_de_vente",
  "logistique_voyages",
  "logistique_recus",
  "logistique_pannes",
  "sante_evenements",
  "logistique_config",
  "parametres",
  "production_pontes",
]);

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

  if (!SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse({ error: "SUPABASE_SERVICE_ROLE_KEY non configurée sur le serveur." }, 500);
  }

  let body: { action?: string; table?: string; rows?: Record<string, unknown>[]; onConflict?: string; select?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Corps de requête JSON invalide." }, 400);
  }

  const table = body.table || "";
  if (!TABLES_AUTORISEES.has(table)) {
    return jsonResponse({ error: "Table non autorisée." }, 403);
  }

  const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  if (body.action === "upsert") {
    const rows = Array.isArray(body.rows) ? body.rows : [];
    if (rows.length === 0) return jsonResponse({ ok: true });
    const { error } = await serviceClient.from(table).upsert(rows, { onConflict: body.onConflict || "id" });
    if (error) return jsonResponse({ error: error.message }, 500);
    return jsonResponse({ ok: true });
  }

  if (body.action === "select") {
    const { data, error } = await serviceClient.from(table).select(body.select || "*");
    if (error) return jsonResponse({ error: error.message }, 500);
    return jsonResponse(data ?? []);
  }

  return jsonResponse({ error: "Action inconnue (attendu: 'upsert' ou 'select')." }, 400);
});
