-- ════════════════════════════════════════════════════════════
--  Pro-Services Univers — Suppression des policies des tables métier
--  À exécuter dans Supabase : SQL Editor → New query → Run
--  APPLIQUÉE le 2026-10-18 (17 tables, avec commerce_bdc).
-- ════════════════════════════════════════════════════════════
--
-- Constat : les policies des tables métier sont `TO public USING (true)`,
-- donc la clé publique (visible dans index.html) suffit à les lire/écrire
-- via l'API REST, sans aucune connexion.
--
-- Pourquoi supprimer plutôt que restreindre à `authenticated` : l'app ne
-- lit/écrit jamais ces tables directement, uniquement via l'Edge Function
-- `cloud-sync` (clé service_role, qui ignore RLS), après vérification du
-- jeton et des droits par rôle (TABLES_PAR_ROLE). Une policy
-- `authenticated USING (true)` laisserait n'importe quel compte connecté
-- contourner ces droits par l'API REST. RLS activée sans policy = aucun
-- accès sauf service_role.
--
-- Tables visées : les 15 de TABLES_AUTORISEES (functions/cloud-sync/index.ts)
-- + `avidata` et `commerce_bdc` (non utilisées par l'app actuelle ni par
-- cloud-sync : après
-- ce script, elles ne sont plus accessibles que depuis le dashboard /
-- service_role). `profiles` n'est PAS concernée.

-- ── 0. Aperçu (à lancer seul d'abord) ─────────────────────────
-- select tablename, policyname, cmd, roles, qual, with_check
-- from pg_policies
-- where schemaname = 'public'
--   and tablename in (
--     'finance_operations','finance_soldes','stock_quantites','stock_mouvements',
--     'commerce_clients','commerce_factures','points_de_vente','pdv_ventes',
--     'logistique_voyages','logistique_recus','logistique_pannes','logistique_config',
--     'sante_evenements','production_pontes','parametres','avidata',
--     'commerce_bdc')
-- order by tablename, policyname;

-- ── 1. Migration ──────────────────────────────────────────────
begin;

do $$
declare
  t text;
  p record;
  n int := 0;
  tables text[] := array[
    'finance_operations','finance_soldes','stock_quantites','stock_mouvements',
    'commerce_clients','commerce_factures','points_de_vente','pdv_ventes',
    'logistique_voyages','logistique_recus','logistique_pannes','logistique_config',
    'sante_evenements','production_pontes','parametres','avidata',
    'commerce_bdc'];
begin
  -- Garde-fou : ne jamais toucher profiles, même si la liste est modifiée.
  if 'profiles' = any(tables) then
    raise exception 'profiles ne doit pas figurer dans cette migration';
  end if;

  -- Suppression de toutes les policies de ces tables (noms lus dans pg_policies).
  for p in
    select tablename, policyname
    from pg_policies
    where schemaname = 'public' and tablename = any(tables)
  loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
    raise notice 'policy % supprimée sur %', p.policyname, p.tablename;
    n := n + 1;
  end loop;
  raise notice '% policy(s) supprimée(s)', n;

  -- RLS déjà activée d'après le dashboard ; réaffirmée ici par sécurité
  -- (sans RLS, supprimer les policies rouvrirait au contraire l'accès).
  foreach t in array tables loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I enable row level security', t);
    else
      raise notice 'table % absente, ignorée', t;
    end if;
  end loop;
end $$;

commit;

-- ── 2. Vérification ───────────────────────────────────────────
-- a) Doit renvoyer 0 ligne :
-- select tablename, policyname from pg_policies
-- where schemaname = 'public'
--   and tablename in (
--     'finance_operations','finance_soldes','stock_quantites','stock_mouvements',
--     'commerce_clients','commerce_factures','points_de_vente','pdv_ventes',
--     'logistique_voyages','logistique_recus','logistique_pannes','logistique_config',
--     'sante_evenements','production_pontes','parametres','avidata',
--     'commerce_bdc');
--
-- b) rowsecurity doit être true partout :
-- select tablename, rowsecurity from pg_tables
-- where schemaname = 'public'
--   and tablename in (
--     'finance_operations','finance_soldes','stock_quantites','stock_mouvements',
--     'commerce_clients','commerce_factures','points_de_vente','pdv_ventes',
--     'logistique_voyages','logistique_recus','logistique_pannes','logistique_config',
--     'sante_evenements','production_pontes','parametres','avidata',
--     'commerce_bdc');
--
-- c) profiles intacte (ses 2 policies doivent toujours être là) :
-- select policyname, roles, cmd from pg_policies
-- where schemaname = 'public' and tablename = 'profiles';
