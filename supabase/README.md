# Authentification Supabase + proxy Claude

Remplace l'ancienne authentification 100% côté client (mots de passe/clé API
visibles dans le code source) par une vraie authentification serveur.
État actuel : **déployé et fonctionnel**.

## Comptes (un par rôle, sur pro-services-univers.com)

| Email | Rôle | Permissions |
|---|---|---|
| `pdg@pro-services-univers.com`        | Amadou Sadio Barry (PDG) | accès complet |
| `production@pro-services-univers.com` | Honoré Doré | production, sanitaire |
| `finance@pro-services-univers.com`    | Arabiou Bah | finance, commerce, pos, pdv |
| `stock@pro-services-univers.com`      | Amadou Moron Barry | stock, production |

Gérés dans Supabase : **Authentication → Users** (mot de passe) +
table `public.profiles` (nom, téléphone, rôle affiché — voir `schema_auth.sql`).

Pour ajouter/renommer un compte : créer/éditer l'utilisateur dans
Authentication → Users, ajuster sa ligne dans `profiles`, et mettre à jour
`ROLES_PERMISSIONS` dans `index.html` (droits d'accès aux pages) si besoin.

## Configuration (index.html)

```js
var SUPABASE_URL = 'https://jzaxgaflcknenpxpzulp.supabase.co'
var SUPABASE_ANON_KEY = 'sb_publishable_...'
```

Ces deux valeurs sont publiques par conception (protégées par les policies
RLS de `schema_auth.sql`, jamais par le secret) — **Project Settings → API
Keys**. Ne jamais y mettre la clé `service_role`.

## Edge Function `claude-chat` (proxy Anthropic)

Déployée depuis le dashboard Supabase (Edge Functions), pas via CLI. La clé
`ANTHROPIC_API_KEY` est un secret Supabase (Edge Functions → Secrets),
jamais dans le code ni côté navigateur.

Ce projet utilise les nouvelles clés API Supabase (`sb_publishable_...`),
donc l'option plateforme **"Verify JWT with legacy secret" est désactivée**
sur cette fonction — la vérification de session est faite à la main dans
`functions/claude-chat/index.ts` via `supabase.auth.getUser(token)`. Si tu
redéploies cette fonction depuis zéro, redésactive cette case et garde le
code de vérification manuelle (sinon la fonction devient appelable sans
connexion, ou rejette systématiquement les utilisateurs légitimes — voir
les commentaires en tête du fichier).

Si l'Edge Function n'est pas déployée ou indisponible, l'app retombe
automatiquement sur l'analyse locale (pas de blocage pour l'utilisateur).

## Edge Function `cloud-sync` (proxy synchronisation des données métier)

Remplace l'ancien mécanisme où un administrateur collait l'URL et la clé
Supabase du projet de synchronisation directement dans l'app (Administration),
stockées en clair dans `localStorage` du navigateur — une clé exposée de cette
façon peut être volée par n'importe quelle faille XSS ailleurs dans l'app.

Désormais l'app appelle `functions/v1/cloud-sync` avec le jeton de la session
Supabase Auth déjà ouverte (aucune clé à saisir). La fonction vérifie ce jeton
(comme `claude-chat`), puis effectue la lecture/écriture avec la clé
`service_role`, injectée automatiquement par Supabase dans chaque Edge
Function (`SUPABASE_SERVICE_ROLE_KEY`) — jamais transmise au navigateur.

Déploiement (dashboard, comme `claude-chat`) :
1. **SQL Editor** : exécuter `schema_supabase.sql` (tables Finance, Stock,
   Commerce, Logistique, Points de vente, Sanitaire, Paramètres — un fichier
   séparé, non fourni ici).
2. **Edge Functions → New function** → nom `cloud-sync` → coller
   `functions/cloud-sync/index.ts` → Deploy.
3. Sur cette fonction : **Settings → "Verify JWT with legacy secret"** =
   désactivé (même raison que pour `claude-chat` : vérification manuelle du
   jeton dans le code).
4. **Important — sécurité** : exécuter aussi `schema_cloud_sync_lockdown.sql`
   dans le SQL Editor. Il active RLS sans policy sur ces tables, donc plus
   aucun accès direct via la clé publique (`anon`) — seule l'Edge Function
   (via `service_role`, qui ignore RLS) peut encore les lire/écrire. Sans
   cette étape, la clé publique du projet (déjà visible dans `index.html`
   pour l'authentification) suffirait à lire/écrire ces tables directement,
   sans même passer par l'app.
5. Rien à configurer côté navigateur : chaque compte synchronise
   automatiquement dès qu'il est connecté (bouton "Forcer l'envoi/réception"
   dans Administration pour un déclenchement manuel).

La fonction ne touche que les tables listées dans `TABLES_AUTORISEES`
(`functions/cloud-sync/index.ts`) — jamais `profiles` ni une table arbitraire
passée par le client.

## Notes

- Les anciens comptes (`barrysadio0@gmail.com`, `hhaba@avimanager.sn`,
  `arabioubah@avimanager.sn`, `ambarry@avimanager.sn`) ne sont plus
  référencés dans le code. Ils peuvent être supprimés dans Authentication →
  Users si tu ne veux pas les garder comme accès de secours.
- Une connexion internet est nécessaire pour se connecter (avant, le login
  fonctionnait hors-ligne). Les données métier restent utilisables
  hors-ligne comme avant, une fois connecté.
