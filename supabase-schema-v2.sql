-- SannazzaroStudenti - Supabase schema v2
-- Preparato per una nuova installazione.
-- NON eseguire finché lo script non è stato revisionato.
-- Non inserire mai la service_role key nel sito pubblico.

begin;

-- =========================================================
-- 1. PROFILI
-- =========================================================

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  class_name text,
  role text not null default 'student'
    check (role in ('student', 'admin')),
  created_at timestamptz not null default now()
);

-- Il database crea sempre un profilo da studente.
-- Non accetta ruolo o classe dai metadati inviati dall'utente.
create or replace function public.create_student_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    'student'
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

revoke all on function public.create_student_profile()
  from public, anon, authenticated;

drop trigger if exists on_auth_user_created_student_profile
  on auth.users;

create trigger on_auth_user_created_student_profile
  after insert on auth.users
  for each row
  execute procedure public.create_student_profile();

-- Crea i profili degli utenti Auth già esistenti.
insert into public.profiles (id, full_name, role)
select
  u.id,
  coalesce(u.raw_user_meta_data ->> 'full_name', ''),
  'student'
from auth.users u
on conflict (id) do nothing;

-- Un solo profilo può avere il ruolo admin.
create unique index if not exists profiles_single_admin_idx
  on public.profiles (role)
  where role = 'admin';

-- Funzione usata dalle policy RLS per riconoscere l'amministratore.
create or replace function public.is_school_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
  );
$$;

revoke all on function public.is_school_admin()
  from public, anon;

grant execute on function public.is_school_admin()
  to authenticated;


-- =========================================================
-- 2. AVVISI
-- =========================================================

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  category text not null default 'Scuola',
  audience_class text,
  published_at timestamptz not null default now(),
  expires_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists announcements_published_idx
  on public.announcements (published_at desc);

alter table public.announcements enable row level security;

drop policy if exists "public read general announcements"
  on public.announcements;

create policy "public read general announcements"
  on public.announcements
  for select to anon
  using (
    audience_class is null
    and published_at <= now()
    and (expires_at is null or expires_at > now())
  );

drop policy if exists "students read relevant announcements"
  on public.announcements;

create policy "students read relevant announcements"
  on public.announcements
  for select to authenticated
  using (
    published_at <= now()
    and (expires_at is null or expires_at > now())
    and (
      audience_class is null
      or audience_class = (
        select p.class_name
        from public.profiles p
        where p.id = (select auth.uid())
      )
    )
  );

drop policy if exists "admins manage announcements"
  on public.announcements;

create policy "admins manage announcements"
  on public.announcements
  for all to authenticated
  using ((select public.is_school_admin()))
  with check ((select public.is_school_admin()));


-- =========================================================
-- 3. ORARIO
-- =========================================================

create table if not exists public.timetable_entries (
  id uuid primary key default gen_random_uuid(),
  class_name text not null,
  weekday smallint not null check (weekday between 1 and 7),
  period smallint not null check (period > 0),
  starts_at time not null,
  ends_at time not null check (ends_at > starts_at),
  subject text not null,
  teacher text,
  room text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (class_name, weekday, period)
);

create index if not exists timetable_class_day_idx
  on public.timetable_entries (class_name, weekday, period);

alter table public.timetable_entries enable row level security;

drop policy if exists "students read own class timetable"
  on public.timetable_entries;

create policy "students read own class timetable"
  on public.timetable_entries
  for select to authenticated
  using (
    class_name = (
      select p.class_name
      from public.profiles p
      where p.id = (select auth.uid())
    )
  );

drop policy if exists "admins manage timetable"
  on public.timetable_entries;

create policy "admins manage timetable"
  on public.timetable_entries
  for all to authenticated
  using ((select public.is_school_admin()))
  with check ((select public.is_school_admin()));


-- =========================================================
-- 4. MATERIALI
-- =========================================================

create table if not exists public.resources (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  subject text,
  audience_class text,
  file_url text,
  published boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists resources_audience_idx
  on public.resources (audience_class, published);

alter table public.resources enable row level security;

drop policy if exists "students read published resources"
  on public.resources;

create policy "students read published resources"
  on public.resources
  for select to authenticated
  using (
    published = true
    and (
      audience_class is null
      or audience_class = (
        select p.class_name
        from public.profiles p
        where p.id = (select auth.uid())
      )
    )
  );

drop policy if exists "admins manage resources"
  on public.resources;

create policy "admins manage resources"
  on public.resources
  for all to authenticated
  using ((select public.is_school_admin()))
  with check ((select public.is_school_admin()));


-- =========================================================
-- 5. SONDAGGI
-- =========================================================

create table if not exists public.polls (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  published boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);

create table if not exists public.poll_options (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null
    references public.polls(id) on delete cascade,
  label text not null,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  unique (poll_id, position),
  unique (id, poll_id)
);

create index if not exists polls_publication_idx
  on public.polls (published, starts_at, ends_at);

create index if not exists poll_options_poll_idx
  on public.poll_options (poll_id, position);

alter table public.polls enable row level security;
alter table public.poll_options enable row level security;

-- Gli studenti vedono solo sondaggi pubblicati e in corso.
drop policy if exists "students read active polls" on public.polls;

create policy "students read active polls"
  on public.polls
  for select to authenticated
  using (
    published = true
    and starts_at <= now()
    and (ends_at is null or ends_at > now())
  );

drop policy if exists "admins manage polls" on public.polls;

create policy "admins manage polls"
  on public.polls
  for all to authenticated
  using ((select public.is_school_admin()))
  with check ((select public.is_school_admin()));

drop policy if exists "students read active poll options"
  on public.poll_options;

create policy "students read active poll options"
  on public.poll_options
  for select to authenticated
  using (
    exists (
      select 1
      from public.polls p
      where p.id = poll_options.poll_id
        and p.published = true
        and p.starts_at <= now()
        and (p.ends_at is null or p.ends_at > now())
    )
  );

drop policy if exists "admins manage poll options"
  on public.poll_options;

create policy "admins manage poll options"
  on public.poll_options
  for all to authenticated
  using ((select public.is_school_admin()))
  with check ((select public.is_school_admin()));


-- =========================================================
-- 6. VOTI
-- =========================================================

create table if not exists public.poll_votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null,
  option_id uuid not null,
  user_id uuid not null
    references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),

  -- Impedisce di scegliere un'opzione appartenente a un altro sondaggio.
  foreign key (option_id, poll_id)
    references public.poll_options(id, poll_id)
    on delete cascade,

  -- Un solo voto per utente per sondaggio.
  unique (poll_id, user_id)
);

create index if not exists poll_votes_poll_idx
  on public.poll_votes (poll_id);

alter table public.poll_votes enable row level security;

-- Gli studenti possono inserire solo il proprio voto
-- e soltanto per un sondaggio pubblicato e ancora aperto.
drop policy if exists "students cast own vote" on public.poll_votes;

create policy "students cast own vote"
  on public.poll_votes
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.polls p
      where p.id = poll_votes.poll_id
        and p.published = true
        and p.starts_at <= now()
        and (p.ends_at is null or p.ends_at > now())
    )
  );

-- Solo l'amministratore può leggere i voti e analizzare i risultati.
drop policy if exists "admins read votes" on public.poll_votes;

create policy "admins read votes"
  on public.poll_votes
  for select to authenticated
  using ((select public.is_school_admin()));

-- Funzione per consentire a un utente autenticato di sapere
-- se ha già votato, senza leggere i voti degli altri utenti.
create or replace function public.has_voted_in_poll(p_poll_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Autenticazione richiesta';
  end if;

  return exists (
    select 1
    from public.poll_votes v
    where v.poll_id = p_poll_id
      and v.user_id = (select auth.uid())
  );
end;
$$;

revoke all on function public.has_voted_in_poll(uuid)
  from public, anon;

grant execute on function public.has_voted_in_poll(uuid)
  to authenticated;


-- =========================================================
-- 7. PERMESSI E SICUREZZA
-- =========================================================

grant usage on schema public to anon, authenticated;

-- Lettura pubblica limitata agli avvisi generali tramite RLS.
grant select on public.announcements to anon;

-- Gli utenti autenticati possono leggere i contenuti consentiti
-- e inviare voti. Le policy RLS limitano le righe accessibili.
grant select on
  public.profiles,
  public.announcements,
  public.timetable_entries,
  public.resources,
  public.polls,
  public.poll_options
to authenticated;

grant insert, update, delete on
  public.profiles,
  public.announcements,
  public.timetable_entries,
  public.resources,
  public.polls,
  public.poll_options
to authenticated;

grant insert on public.poll_votes to authenticated;
grant select on public.poll_votes to authenticated;

commit;

-- =========================================================
-- 8. CONFIGURAZIONE INIZIALE DELL'AMMINISTRATORE
-- =========================================================
-- NON viene assegnato automaticamente alcun amministratore.
-- Dopo aver verificato l'indirizzo email dell'account scelto,
-- l'amministratore dovrà essere configurato separatamente.
-- Non rendere questa operazione disponibile agli studenti.
