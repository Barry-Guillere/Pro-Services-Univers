-- ════════════════════════════════════════════════════════════
--  Pro-Services Univers — Tables métier de la synchronisation cloud
--  À exécuter dans Supabase : SQL Editor → New query → Run
--  (avant de déployer l'Edge Function `cloud-sync` — voir supabase/README.md)
-- ════════════════════════════════════════════════════════════
--
-- 16 tables = TABLES_AUTORISEES de functions/cloud-sync/index.ts.
-- Colonnes calquées sur syncToSupabase() / pullFromSupabase() dans
-- index.html : toute modification de ces fonctions doit être répercutée ici.
--
-- Choix de types :
--  - `id` en bigint quand l'app génère Date.now() (comparé avec === côté
--    client, il doit revenir en nombre) ; en text quand l'app génère une
--    chaîne ('CLI-…', 'FACT-…', 'pdv_…', 'date_bat', String(v.id)).
--  - Dates en text : l'app envoie '' quand la date est absente, ce qu'une
--    colonne `date` rejetterait (et ferait échouer tout l'upsert).
--  - Montants et quantités en numeric (accepte entiers, décimaux et
--    nombres envoyés sous forme de chaîne).
--
-- Script idempotent : peut être relancé sans perte de données.

-- ── Finance ───────────────────────────────────────────────────
create table if not exists public.finance_operations (
  id          bigint primary key,
  date        text    default '',
  type        text    default '',
  categorie   text    default '',
  description text    default '',
  compte      text    default '',
  montant     numeric default 0,
  responsable text    default ''
);

create table if not exists public.finance_soldes (
  compte  text primary key,
  montant numeric default 0
);

-- ── Stock ─────────────────────────────────────────────────────
create table if not exists public.stock_quantites (
  produit_id text primary key,
  quantite   numeric default 0,
  prix_moyen numeric default 0
);

create table if not exists public.stock_mouvements (
  id          bigint primary key,
  date        text    default '',
  produit_id  text    default '',
  produit_nom text    default '',
  type        text    default '',
  quantite    numeric default 0,
  unite       text    default '',
  prix        numeric default 0,
  total       numeric default 0,
  motif       text    default '',
  batiment    text    default '',
  responsable text    default ''
);

-- ── Commerce ──────────────────────────────────────────────────
create table if not exists public.commerce_clients (
  id             text primary key,
  nom            text    default '',
  type           text    default '',
  telephone      text    default '',
  email          text    default '',
  adresse        text    default '',
  delai_paiement integer default 30,
  plafond_credit numeric default 0,
  solde          numeric default 0
);

create table if not exists public.commerce_factures (
  id         text primary key,
  numero     text    default '',
  date       text    default '',
  client_id  text    default '',
  client_nom text    default '',
  articles   jsonb   default '[]'::jsonb,
  total      numeric default 0,
  acompte    numeric default 0,
  solde      numeric default 0,
  paiement   text    default '',
  statut     text    default ''
);

-- Bons de commande : structure différente des autres tables (objet BDC
-- complet dans `data`). L'app génère des id 'BDC-<horodatage>' : elle
-- n'envoie que l'horodatage (bigint) et remet le préfixe à la réception.
create table if not exists public.commerce_bdc (
  id         bigint primary key,
  data       jsonb,
  updated_at timestamptz default now()
);

-- ── Points de vente ───────────────────────────────────────────
create table if not exists public.points_de_vente (
  id            text primary key,
  nom           text  default '',
  zone          text  default '',
  adresse       text  default '',
  gerant_select text  default '',
  gerant_nom    text  default '',
  gerant_tel    text  default '',
  commission    text  default '',
  produits      jsonb default '[]'::jsonb,
  stock         jsonb default '{}'::jsonb,
  statut        text  default '',
  date_creation text
);

create table if not exists public.pdv_ventes (
  id          text primary key,
  pdv_id      text    default '',
  date        text,
  produit     text    default '',
  produit_nom text    default '',
  qte         numeric default 0,
  pu          numeric default 0,
  montant     numeric default 0,
  responsable text    default ''
);

-- ── Logistique ────────────────────────────────────────────────
create table if not exists public.logistique_voyages (
  id          bigint primary key,
  date        text    default '',
  type        text    default '',
  destination text    default '',
  chauffeur   text    default '',
  km_depart   numeric default 0,
  km_arrivee  numeric default 0,
  litres      numeric default 0,
  cout        numeric default 0,
  notes       text    default ''
);

create table if not exists public.logistique_recus (
  id      bigint primary key,
  date    text    default '',
  litres  numeric default 0,
  montant numeric default 0,
  station text    default '',
  notes   text    default ''
);

create table if not exists public.logistique_pannes (
  id          bigint primary key,
  date        text    default '',
  gravite     text    default '',
  type        text    default '',
  description text    default '',
  lieu        text    default '',
  signale_par text    default '',
  cout        numeric default 0,
  statut      text    default ''
);

-- Une seule ligne (id = 'principal').
create table if not exists public.logistique_config (
  id                     text primary key,
  km_actuel              numeric default 0,
  voyages_total          numeric default 0,
  voyages_depuis_vidange numeric default 0,
  seuil_vidange          numeric default 50,
  date_derniere_vidange  text
);

-- ── Sanitaire ─────────────────────────────────────────────────
create table if not exists public.sante_evenements (
  id          bigint primary key,
  date        text default '',
  type        text default '',
  gravite     text default '',
  description text default '',
  batiment    text default '',
  responsable text default ''
);

-- ── Production (relevés de ponte, id = '<date>_<bâtiment>') ───
create table if not exists public.production_pontes (
  id     text primary key,
  date   text    default '',
  bat    text    default '',
  taux   numeric default 0,
  march  numeric default 0,
  total  numeric default 0,
  feles  numeric default 0,
  sales  numeric default 0,
  morts  numeric default 0,
  alim   numeric default 0,
  eau    numeric default 0
);

-- ── Paramètres de l'app (une seule ligne, id = 'principal') ───
create table if not exists public.parametres (
  id   text primary key,
  data jsonb default '{}'::jsonb
);

-- ── Sécurité ──────────────────────────────────────────────────
-- RLS activée SANS policy : aucun accès via la clé publique (anon /
-- authenticated). Seule l'Edge Function `cloud-sync` (service_role, qui
-- ignore RLS) peut lire/écrire. Même effet que
-- schema_cloud_sync_lockdown.sql, appliqué dès la création des tables.
alter table public.finance_operations enable row level security;
alter table public.finance_soldes     enable row level security;
alter table public.stock_quantites    enable row level security;
alter table public.stock_mouvements   enable row level security;
alter table public.commerce_clients   enable row level security;
alter table public.commerce_factures  enable row level security;
alter table public.commerce_bdc       enable row level security;
alter table public.points_de_vente    enable row level security;
alter table public.pdv_ventes         enable row level security;
alter table public.logistique_voyages enable row level security;
alter table public.logistique_recus   enable row level security;
alter table public.logistique_pannes  enable row level security;
alter table public.logistique_config  enable row level security;
alter table public.sante_evenements   enable row level security;
alter table public.production_pontes  enable row level security;
alter table public.parametres         enable row level security;
