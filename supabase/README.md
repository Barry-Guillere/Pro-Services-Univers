# Déploiement — Authentification Supabase + proxy Claude

Ce dossier contient tout ce qu'il faut pour remplacer l'authentification
100% côté client (mots de passe/clé API visibles dans le code source) par
une vraie authentification serveur.

## 1. Créer/ouvrir le projet Supabase

Si un projet existe déjà (utilisé pour la synchronisation cloud dans
Paramètres), tu peux le réutiliser tel quel.

1. https://supabase.com → New project (gratuit).
2. **SQL Editor → New query** → coller le contenu de `schema_auth.sql` → Run.
3. **Authentication → Users → Add user**, pour chacun des 4 comptes
   (`barrysadio0@gmail.com`, `hhaba@avimanager.sn`, `arabioubah@avimanager.sn`,
   `ambarry@avimanager.sn`) :
   - Cocher **Auto Confirm User**.
   - Définir un **nouveau** mot de passe (ne pas réutiliser les anciens mots
     de passe par défaut — ils ont été exposés dans l'historique du code).
   - Copier l'UUID généré pour chaque utilisateur.
4. Retourner dans **SQL Editor**, dérouler les commentaires en bas de
   `schema_auth.sql`, et exécuter le `insert into public.profiles ...` en
   remplaçant les `UUID_x` par les vrais UUID copiés à l'étape 3.

## 2. Brancher le front (index.html)

Dans `index.html`, chercher :

```js
var SUPABASE_URL = 'https://VOTRE-PROJET.supabase.co'
var SUPABASE_ANON_KEY = 'VOTRE_CLE_ANON_PUBLIQUE'
```

Remplacer par les vraies valeurs — **Project Settings → API Keys** :
`Project URL` et la clé `anon` / `public` (jamais la `service_role`, qui
elle doit rester secrète et n'a rien à faire dans ce fichier).

Tant que ces deux valeurs ne sont pas renseignées, l'écran de connexion
affiche un message clair au lieu de planter.

## 3. Déployer l'Edge Function (proxy Claude)

Nécessite le CLI Supabase (`npm install -g supabase`) et d'être lié au
projet (`supabase link --project-ref xxxxxxxx`).

```bash
supabase functions deploy claude-chat
supabase secrets set ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxxxxx
```

À partir de là, l'agent IA appelle `${SUPABASE_URL}/functions/v1/claude-chat`
avec le jeton de session de l'utilisateur connecté ; la clé Anthropic ne
quitte jamais le serveur. Si l'Edge Function n'est pas déployée, l'app
retombe automatiquement sur l'analyse locale (pas de blocage).

## 4. Tester

- Se connecter avec chacun des 4 comptes (nouveaux mots de passe).
- Vérifier que le nom/rôle/téléphone s'affichent bien (issus de `profiles`).
- Page Admin → Équipe : la liste doit se charger depuis Supabase.
- Paramètres → Sécurité → changer son mot de passe : doit fonctionner sans
  recharger la page.
- Poser une question à l'agent IA : si l'Edge Function est déployée, la
  réponse vient de Claude ; sinon, analyse locale (comportement normal).

## Ce qui a changé pour l'équipe

- Les 4 comptes doivent utiliser leur **nouveau** mot de passe défini à
  l'étape 1 (les anciens ne fonctionnent plus).
- Une connexion internet est désormais nécessaire pour se connecter (avant,
  l'app fonctionnait 100% hors-ligne pour le login). Les données métier
  restent utilisables hors-ligne comme avant une fois connecté.
