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
  "commerce_bdc",
  "points_de_vente",
  "pdv_ventes",
  "logistique_voyages",
  "logistique_recus",
  "logistique_pannes",
  "sante_evenements",
  "logistique_config",
  "parametres",
  "production_pontes",
]);

// Ecriture (upsert) restreinte par role, en plus de la liste blanche
// ci-dessus. Determinee cote serveur depuis l'email de la session
// authentifiee — jamais depuis une valeur envoyee par le client, qui
// pourrait pretendre etre n'importe quel role.
//
// null      = acces total (PDG)
// Set<...>  = uniquement ces tables
// (absent)  = email non reconnu -> refuse par defaut
//
// Cette liste reflete les connexions automatiques reelles de l'app
// (ex: une saisie sanitaire cree aussi une depense Finance, une vente
// Commerce decremente aussi le Stock) : chaque role garde acces aux
// tables que ses propres fonctionnalites touchent legitimement, rien
// de plus.
//
// finance_soldes est retire de production@ et stock@ : ces roles ne lisent
// pas finance_operations, leurs soldes calcules localement seraient faux.
// Les soldes sont recalcules par l'app depuis les operations.
const TABLES_PAR_ROLE: Record<string, Set<string> | null> = {
  "pdg@pro-services-univers.com": null,
  "production@pro-services-univers.com": new Set([
    "production_pontes", "sante_evenements",
    "stock_quantites", "stock_mouvements",
    "finance_operations",
  ]),
  "finance@pro-services-univers.com": new Set([
    "finance_operations", "finance_soldes",
    "commerce_clients", "commerce_factures", "commerce_bdc",
    "points_de_vente", "pdv_ventes",
    "stock_quantites", "stock_mouvements",
  ]),
  "stock@pro-services-univers.com": new Set([
    "stock_quantites", "stock_mouvements",
    "production_pontes",
    "finance_operations",
  ]),
};

// Lecture (select) restreinte par role : tables reellement lues par les
// ecrans de chaque role dans index.html. Meme convention que ci-dessus.
//
// Une table modifiable mais non lisible (ex: finance_operations pour
// production@) est en AJOUT SEUL : l'upsert ignore les lignes deja
// presentes, pour qu'une copie locale perimee ne puisse jamais ecraser
// les donnees d'un autre role.
const TABLES_LECTURE_PAR_ROLE: Record<string, Set<string> | null> = {
  "pdg@pro-services-univers.com": null,
  "production@pro-services-univers.com": new Set([
    "production_pontes", "sante_evenements",
    "stock_mouvements", "stock_quantites",
    "parametres",
  ]),
  "finance@pro-services-univers.com": new Set([
    "finance_operations", "finance_soldes",
    "commerce_clients", "commerce_factures", "commerce_bdc",
    "points_de_vente", "pdv_ventes",
    "stock_mouvements", "stock_quantites",
    "parametres",
  ]),
  "stock@pro-services-univers.com": new Set([
    "stock_mouvements", "stock_quantites",
    "production_pontes",
    "parametres",
  ]),
};

const enListe = (s: Set<string> | null) => (s === null ? "*" : [...s]);

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

  // Role determine cote serveur depuis l'email de la session verifiee.
  const email = (userData.user.email || "").toLowerCase();
  const lectureRole = TABLES_LECTURE_PAR_ROLE[email];
  const ecritureRole = TABLES_PAR_ROLE[email];
  if (lectureRole === undefined || ecritureRole === undefined) {
    return jsonResponse({ error: "Rôle non reconnu." }, 403);
  }

  // Droits du compte connecte, pour que l'app n'envoie/ne lise que ses tables.
  if (body.action === "droits") {
    return jsonResponse({ lecture: enListe(lectureRole), ecriture: enListe(ecritureRole) });
  }

  const table = body.table || "";
  if (!TABLES_AUTORISEES.has(table)) {
    return jsonResponse({ error: "Table non autorisée." }, 403);
  }

  const peutLire = lectureRole === null || lectureRole.has(table);
  const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  if (body.action === "upsert") {
    if (ecritureRole !== null && !ecritureRole.has(table)) {
      return jsonResponse({ error: "Écriture non autorisée pour ce rôle sur cette table." }, 403);
    }

    const rows = Array.isArray(body.rows) ? body.rows : [];
    if (rows.length === 0) return jsonResponse({ ok: true });
    const { error } = await serviceClient.from(table).upsert(rows, {
      onConflict: body.onConflict || "id",
      // Ajout seul si le role ne peut pas lire la table (ON CONFLICT DO NOTHING).
      ignoreDuplicates: !peutLire,
    });
    if (error) return jsonResponse({ error: error.message }, 500);
    return jsonResponse({ ok: true });
  }

  if (body.action === "select") {
    if (!peutLire) {
      return jsonResponse({ error: "Lecture non autorisée pour ce rôle sur cette table." }, 403);
    }
    const { data, error } = await serviceClient.from(table).select(body.select || "*");
    if (error) return jsonResponse({ error: error.message }, 500);
    return jsonResponse(data ?? []);
  }

  return jsonResponse({ error: "Action inconnue (attendu: 'droits', 'upsert' ou 'select')." }, 400);
});
