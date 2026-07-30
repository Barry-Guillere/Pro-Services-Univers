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

-- ── Comptes (Authentication → Users), un par rôle ───────────────────────
--   pdg@pro-services-univers.com        → Amadou Sadio Barry (PDG)
--   production@pro-services-univers.com → Honore Doré (Production & Sanitaire)
--   finance@pro-services-univers.com    → Arabiou Bah (Finance & Commerce)
--   stock@pro-services-univers.com      → Amadou Moron Barry (Stock)
--
-- Lier les profils par email (pas besoin de copier les UUID à la main,
-- auth.users est interrogeable depuis le SQL Editor) :

insert into public.profiles (id, email, name, tel, role, init)
select id, email,
  case email
    when 'pdg@pro-services-univers.com'        then 'Amadou Sadio Barry'
    when 'production@pro-services-univers.com' then 'Honore Doré'
    when 'finance@pro-services-univers.com'    then 'Arabiou Bah'
    when 'stock@pro-services-univers.com'      then 'Amadou Moron Barry'
  end,
  case email
    when 'pdg@pro-services-univers.com'        then '621989823'
    when 'production@pro-services-univers.com' then '625171922'
    when 'finance@pro-services-univers.com'    then '629481997'
    when 'stock@pro-services-univers.com'      then '621540515'
  end,
  case email
    when 'pdg@pro-services-univers.com'        then 'PDG Directeur General'
    when 'production@pro-services-univers.com' then 'Resp. Production et Suivi Sanitaire'
    when 'finance@pro-services-univers.com'    then 'Resp. Finance et Commerce'
    when 'stock@pro-services-univers.com'      then 'Responsable Stock'
  end,
  case email
    when 'pdg@pro-services-univers.com'        then 'ASB'
    when 'production@pro-services-univers.com' then 'HD'
    when 'finance@pro-services-univers.com'    then 'ABH'
    when 'stock@pro-services-univers.com'      then 'AMB'
  end
from auth.users
where email in ('pdg@pro-services-univers.com','production@pro-services-univers.com','finance@pro-services-univers.com','stock@pro-services-univers.com')
on conflict (id) do update set
  name = excluded.name, tel = excluded.tel, role = excluded.role, init = excluded.init;
