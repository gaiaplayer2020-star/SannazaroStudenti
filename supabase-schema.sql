-- Student portal schema for Supabase / PostgreSQL.
-- Apply after creating a Supabase project. Keep service_role keys on the server only.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  class_name text,
  role text not null default 'student' check (role in ('student', 'admin')),
  created_at timestamptz not null default now()
);

-- Do not trust user-supplied signup metadata for class or role.
create or replace function public.create_student_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_student_profile on auth.users;
create trigger on_auth_user_created_student_profile
  after insert on auth.users
  for each row execute procedure public.create_student_profile();

create or replace function public.is_school_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

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

create index if not exists announcements_published_idx on public.announcements (published_at desc);
create index if not exists timetable_class_day_idx on public.timetable_entries (class_name, weekday, period);
create index if not exists resources_audience_idx on public.resources (audience_class, published);

alter table public.profiles enable row level security;
alter table public.announcements enable row level security;
alter table public.timetable_entries enable row level security;
alter table public.resources enable row level security;

-- Profiles are private. Students can read their own profile; only admins can assign classes/roles.
drop policy if exists "students read own profile" on public.profiles;
create policy "students read own profile" on public.profiles
  for select to authenticated using (id = (select auth.uid()) or (select public.is_school_admin()));
drop policy if exists "admins manage profiles" on public.profiles;
create policy "admins manage profiles" on public.profiles
  for all to authenticated using ((select public.is_school_admin()))
  with check ((select public.is_school_admin()));

-- Authenticated students see only published announcements addressed to everyone or their class.
drop policy if exists "students read relevant announcements" on public.announcements;
create policy "students read relevant announcements" on public.announcements
  for select to authenticated using (
    published_at <= now()
    and (expires_at is null or expires_at > now())
    and (audience_class is null or audience_class = (
      select p.class_name from public.profiles p where p.id = (select auth.uid())
    ))
  );
drop policy if exists "admins manage announcements" on public.announcements;
create policy "admins manage announcements" on public.announcements
  for all to authenticated using ((select public.is_school_admin()))
  with check ((select public.is_school_admin()));

drop policy if exists "students read own class timetable" on public.timetable_entries;
create policy "students read own class timetable" on public.timetable_entries
  for select to authenticated using (class_name = (
    select p.class_name from public.profiles p where p.id = (select auth.uid())
  ));
drop policy if exists "admins manage timetable" on public.timetable_entries;
create policy "admins manage timetable" on public.timetable_entries
  for all to authenticated using ((select public.is_school_admin()))
  with check ((select public.is_school_admin()));

drop policy if exists "students read published resources" on public.resources;
create policy "students read published resources" on public.resources
  for select to authenticated using (
    published = true
    and (audience_class is null or audience_class = (
      select p.class_name from public.profiles p where p.id = (select auth.uid())
    ))
  );
drop policy if exists "admins manage resources" on public.resources;
create policy "admins manage resources" on public.resources
  for all to authenticated using ((select public.is_school_admin()))
  with check ((select public.is_school_admin()));

grant usage on schema public to authenticated;
grant select on public.profiles, public.announcements, public.timetable_entries, public.resources to authenticated;
grant insert, update, delete on public.profiles, public.announcements, public.timetable_entries, public.resources to authenticated;
