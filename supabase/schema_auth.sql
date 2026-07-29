-- ════════════════════════════════════════════════════════════
--  Pro-Services Univers — Authentification (Supabase Auth)
--  À exécuter dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════

-- 1. Table de profils, liée 1-pour-1 à auth.users (géré par Supabase Auth).
--    Ne contient AUCUN mot de passe : Supabase Auth (GoTrue) gère le hash
--    (bcrypt, salé) dans son propre schéma interne, jamais exposé au client.
create table if not exists public.profiles (
  id    uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  name  text not null,
  tel   text default '',
  role  text not null default 'Utilisateur',
  init  text default '',
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Tout utilisateur connecté peut lire l'annuaire de l'équipe
-- (nécessaire pour l'écran Admin > Équipe et l'affichage des responsables).
create policy "profiles_select_authenticated"
  on public.profiles for select
  to authenticated
  using (true);

-- Un utilisateur ne peut modifier que sa propre fiche (pas son role/email).
create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ── Étapes manuelles (dans le Dashboard Supabase, pas en SQL) ──────────
-- 1. Authentication → Users → Add user, pour chacun des 4 comptes :
--      barrysadio0@gmail.com / hhaba@avimanager.sn /
--      arabioubah@avimanager.sn / ambarry@avimanager.sn
--    → cocher "Auto Confirm User", définir un NOUVEAU mot de passe
--      (ne pas réutiliser Barry2025! / Pro-serv1 / Bah2025! / Moron2025! —
--      ces mots de passe par défaut ont été exposés dans le code source).
-- 2. Copier l'UUID généré pour chaque utilisateur (colonne "id" dans la
--    liste Authentication → Users), puis exécuter ci-dessous en remplaçant
--    les UUID_xxx par les vrais UUID :

-- insert into public.profiles (id, email, name, tel, role, init) values
--   ('UUID_1', 'barrysadio0@gmail.com',    'Amadou Sadio Barry', '621989823', 'PDG Directeur General',              'ASB'),
--   ('UUID_2', 'hhaba@avimanager.sn',      'Honore Doré',        '625171922', 'Resp. Production et Suivi Sanitaire','HD'),
--   ('UUID_3', 'arabioubah@avimanager.sn', 'Arabiou Bah',        '629481997', 'Resp. Finance et Commerce',          'ABH'),
--   ('UUID_4', 'ambarry@avimanager.sn',    'Amadou Moron Barry', '621540515', 'Responsable Stock',                  'AMB');
