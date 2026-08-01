-- ════════════════════════════════════════════════════════════
--  Pro-Services Univers — Verrouillage RLS des tables de sync cloud
--  À exécuter dans Supabase : SQL Editor → New query → Run
--  (une fois schema_supabase.sql déjà appliqué, et après avoir déployé
--  l'Edge Function `cloud-sync` — voir supabase/README.md)
-- ════════════════════════════════════════════════════════════
--
-- Depuis la bascule vers l'Edge Function `cloud-sync`, plus aucun appel
-- direct du navigateur vers ces tables n'est nécessaire : l'Edge Function
-- utilise la clé service_role (qui contourne RLS) pour lire/écrire, après
-- avoir vérifié la session de l'utilisateur.
--
-- Activer RLS ci-dessous SANS policy pour anon/authenticated ferme donc
-- tout accès direct (anon key, clé publiée, requête REST manuelle) à ces
-- tables, sans rien casser côté app : seule l'Edge Function y accède
-- encore, via service_role qui n'est jamais soumise à RLS.

alter table if exists public.finance_operations   enable row level security;
alter table if exists public.finance_soldes       enable row level security;
alter table if exists public.stock_quantites      enable row level security;
alter table if exists public.stock_mouvements     enable row level security;
alter table if exists public.commerce_clients     enable row level security;
alter table if exists public.commerce_factures    enable row level security;
alter table if exists public.points_de_vente      enable row level security;
alter table if exists public.logistique_voyages   enable row level security;
alter table if exists public.logistique_recus     enable row level security;
alter table if exists public.logistique_pannes    enable row level security;
alter table if exists public.sante_evenements     enable row level security;
alter table if exists public.logistique_config    enable row level security;
alter table if exists public.parametres           enable row level security;

-- Aucune policy créée intentionnellement : par défaut, RLS activée sans
-- policy = accès refusé à tout le monde sauf service_role (qui l'ignore).
