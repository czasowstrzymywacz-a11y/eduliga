-- Iskierka: konta uczniów z nazwą + PIN, prywatne postępy i bezpieczny odczyt rankingów.
-- Uruchom raz w Supabase: SQL Editor > New query > Run.

create table if not exists public.student_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  login_key text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.student_progress (
  user_id uuid primary key references auth.users (id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.student_pin_attempt_limits (
  rate_key text primary key,
  window_started_at timestamptz not null default now(),
  attempt_count integer not null default 0,
  blocked_until timestamptz
);

alter table public.student_profiles enable row level security;
alter table public.student_progress enable row level security;
alter table public.student_pin_attempt_limits enable row level security;

revoke all on public.student_profiles from public, anon, authenticated;
revoke all on public.student_progress from public, anon;
revoke all on public.student_pin_attempt_limits from public, anon, authenticated;
grant select, insert, update on public.student_progress to authenticated;

create or replace function public.ensure_student_profile(p_display_name text, p_login_key text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Zaloguj się, aby utworzyć profil.';
  end if;
  if p_display_name is null or length(btrim(p_display_name)) not between 2 and 24
     or p_display_name !~ '^[[:alnum:] _-]+$' then
    raise exception 'Imię lub pseudonim musi mieć 2–24 znaki.';
  end if;
  if p_login_key is null or length(p_login_key) > 254 then
    raise exception 'Nieprawidłowy adres konta.';
  end if;

  insert into public.student_profiles(user_id, display_name, login_key)
  values (auth.uid(), btrim(p_display_name), lower(p_login_key))
  on conflict (user_id) do update set display_name = excluded.display_name;
exception when unique_violation then
  raise exception 'Ten profil jest już zarejestrowany.';
end;
$$;

revoke all on function public.ensure_student_profile(text, text) from public, anon;
grant execute on function public.ensure_student_profile(text, text) to authenticated;

drop policy if exists "Students can read their own progress" on public.student_progress;
create policy "Students can read their own progress"
  on public.student_progress for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Students can create their own progress" on public.student_progress;
create policy "Students can create their own progress"
  on public.student_progress for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Students can update their own progress" on public.student_progress;
create policy "Students can update their own progress"
  on public.student_progress for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.consume_student_pin_attempt(p_rate_key text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit public.student_pin_attempt_limits%rowtype;
begin
  insert into public.student_pin_attempt_limits(rate_key)
  values (p_rate_key)
  on conflict (rate_key) do nothing;

  select * into v_limit
  from public.student_pin_attempt_limits
  where rate_key = p_rate_key
  for update;

  if v_limit.blocked_until is not null and v_limit.blocked_until > now() then
    return false;
  end if;

  if v_limit.window_started_at < now() - interval '15 minutes' then
    update public.student_pin_attempt_limits
    set window_started_at = now(), attempt_count = 1, blocked_until = null
    where rate_key = p_rate_key;
    return true;
  end if;

  if v_limit.attempt_count >= 5 then
    update public.student_pin_attempt_limits
    set blocked_until = now() + interval '15 minutes'
    where rate_key = p_rate_key;
    return false;
  end if;

  update public.student_pin_attempt_limits
  set attempt_count = attempt_count + 1
  where rate_key = p_rate_key;
  return true;
end;
$$;

create or replace function public.reset_student_pin_attempt(p_rate_key text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from public.student_pin_attempt_limits where rate_key = p_rate_key;
$$;

revoke all on function public.consume_student_pin_attempt(text) from public, anon, authenticated;
revoke all on function public.reset_student_pin_attempt(text) from public, anon, authenticated;
grant execute on function public.consume_student_pin_attempt(text) to service_role;
grant execute on function public.reset_student_pin_attempt(text) to service_role;

create or replace function public.get_leaderboard(p_category text)
returns table(display_name text, metric numeric, session_count bigint, is_me boolean)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with stats as (
    select
      p.user_id,
      p.display_name,
      (select count(*)
       from jsonb_array_elements(coalesce(pr.data->'sessions', '[]'::jsonb)) as elem(item)) as session_count,
      coalesce((select avg((item->>'score')::numeric)
       from jsonb_array_elements(coalesce(pr.data->'sessions', '[]'::jsonb)) as elem(item)), 0) as average_score,
      (select count(*)
       from jsonb_array_elements(coalesce(pr.data->'sessions', '[]'::jsonb)) as elem(item)
       where (item->>'date')::date >= current_date - (extract(isodow from current_date)::int - 1)) as weekly_count,
      (select count(*)
       from jsonb_array_elements(coalesce(pr.data->'sessions', '[]'::jsonb)) as elem(item)
       where (item->>'score')::numeric >= 90) as excellent_count,
      (select count(*)
       from jsonb_each(coalesce(pr.data->'words', '{}'::jsonb)) w
       where coalesce((w.value->>'correct')::int, 0) >= 2) as mastered_count,
      case
        when coalesce((pr.data->>'lastDay')::date, current_date - 2) >= current_date - 1
          then coalesce((pr.data->>'streak')::int, 0)
        else 0
      end as current_streak
    from public.student_profiles p
    left join public.student_progress pr on pr.user_id = p.user_id
  ), ranked as (
    select
      s.display_name,
      s.session_count,
      s.user_id,
      case p_category
        when 'weekly' then s.weekly_count::numeric
        when 'sessions' then s.session_count::numeric
        when 'average' then round(s.average_score, 0)
        when 'mastered' then s.mastered_count::numeric
        when 'streak' then s.current_streak::numeric
        when 'excellent' then s.excellent_count::numeric
        else 0::numeric
      end as metric
    from stats s
    where case when p_category = 'average' then s.session_count >= 3 else s.session_count > 0 end
  )
  select r.display_name, r.metric, r.session_count, (r.user_id = auth.uid()) as is_me
  from ranked r
  where p_category in ('weekly', 'sessions', 'average', 'mastered', 'streak', 'excellent')
  order by r.metric desc, r.session_count desc, r.display_name asc
  limit 10;
$$;

revoke all on function public.get_leaderboard(text) from public, anon;
grant execute on function public.get_leaderboard(text) to authenticated;


-- Pseudonym-only account roster for the authenticated rankings view.
create or replace function public.get_student_roster()
returns table(user_id uuid, display_name text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.user_id, p.display_name
  from public.student_profiles as p
  order by p.display_name asc;
$$;

revoke all on function public.get_student_roster() from public, anon;
grant execute on function public.get_student_roster() to authenticated;


-- Shared class chat migration: see supabase/migrations/202610070001_class_chat.sql
-- Shared classroom chat. Messages are pseudonymous and visible to signed-in pupils only.
create table if not exists public.class_chat_messages (
  id bigint generated always as identity primary key,
  sender_id uuid not null references auth.users(id) on delete cascade,
  sender_name text not null,
  body text not null check (char_length(body) between 1 and 240),
  created_at timestamptz not null default now()
);

create index if not exists class_chat_messages_created_idx
  on public.class_chat_messages (created_at desc);

alter table public.class_chat_messages enable row level security;
revoke all on public.class_chat_messages from public, anon;
grant select, insert on public.class_chat_messages to authenticated;
grant usage, select on sequence public.class_chat_messages_id_seq to authenticated;

drop policy if exists class_chat_read_signed_in on public.class_chat_messages;
create policy class_chat_read_signed_in on public.class_chat_messages
  for select to authenticated using (true);

drop policy if exists class_chat_insert_own on public.class_chat_messages;
create policy class_chat_insert_own on public.class_chat_messages
  for insert to authenticated with check (sender_id = auth.uid());

create or replace function public.prepare_class_chat_message()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
begin
  if auth.uid() is null or new.sender_id <> auth.uid() then
    raise exception 'Zaloguj się, aby wysłać wiadomość.';
  end if;
  new.body := left(trim(regexp_replace(coalesce(new.body, ''), '\s+', ' ', 'g')), 240);
  if new.body = '' then raise exception 'Wiadomość nie może być pusta.'; end if;
  if new.body ~* '([[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}|https?://|www\.|[0-9][0-9 ()+-]{7,}[0-9])' then
    raise exception 'Nie wpisuj danych kontaktowych ani odnośników na czacie.';
  end if;
  if exists (
    select 1 from public.class_chat_messages m
    where m.sender_id = auth.uid() and m.created_at > now() - interval '2 seconds'
  ) then raise exception 'Odczekaj chwilę przed kolejną wiadomością.'; end if;

  select p.display_name into v_name
  from public.student_profiles p where p.user_id = auth.uid();
  new.sender_name := coalesce(nullif(trim(v_name), ''), 'Uczeń');
  new.created_at := now();
  return new;
end;
$$;

revoke all on function public.prepare_class_chat_message() from public, anon, authenticated;
drop trigger if exists prepare_class_chat_message on public.class_chat_messages;
create trigger prepare_class_chat_message
  before insert on public.class_chat_messages
  for each row execute function public.prepare_class_chat_message();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'class_chat_messages'
  ) then
    alter publication supabase_realtime add table public.class_chat_messages;
  end if;
end;
$$;

-- Shared English XP and private, expiring invitations for the existing open room.
create or replace function public.get_english_student_roster()
returns table(user_id uuid, display_name text, english_xp bigint)
language sql stable security definer
set search_path = public, pg_temp
as $$
  select p.user_id, p.display_name,
    case when (pr.data #>> '{englishLeague,xp}') ~ '^[0-9]+(\.[0-9]+)?$'
      then least(2147483647, greatest(0, (pr.data #>> '{englishLeague,xp}')::numeric))::bigint
      else 0::bigint end
  from public.student_profiles p
  left join public.student_progress pr on pr.user_id = p.user_id
  where auth.uid() is not null
  order by p.display_name;
$$;
revoke all on function public.get_english_student_roster() from public, anon;
grant execute on function public.get_english_student_roster() to authenticated;

create table if not exists public.english_battle_invitations (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  room_name text not null default 'liga-angielska-open-room'
    check (room_name = 'liga-angielska-open-room'),
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '2 minutes'),
  responded_at timestamptz,
  check (sender_id <> recipient_id)
);
create index if not exists english_invites_recipient_pending
  on public.english_battle_invitations(recipient_id, expires_at) where status = 'pending';
create index if not exists english_invites_sender_recent
  on public.english_battle_invitations(sender_id, created_at);
alter table public.english_battle_invitations enable row level security;
revoke all on public.english_battle_invitations from public, anon, authenticated;
grant select on public.english_battle_invitations to authenticated;
drop policy if exists english_invites_participant_read on public.english_battle_invitations;
create policy english_invites_participant_read on public.english_battle_invitations
  for select to authenticated using (auth.uid() in (sender_id,recipient_id));

create or replace function public.send_english_battle_invitation(p_recipient_id uuid)
returns uuid language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_sender uuid := auth.uid(); v_existing uuid; v_id uuid;
begin
  if v_sender is null then raise exception 'Zaloguj się, aby zaprosić do bitwy.'; end if;
  if p_recipient_id is null or p_recipient_id = v_sender then
    raise exception 'Wybierz innego użytkownika.';
  end if;
  if not exists(select 1 from public.student_profiles where user_id = v_sender)
    or not exists(select 1 from public.student_profiles where user_id = p_recipient_id) then
    raise exception 'Nie znaleziono konta użytkownika.';
  end if;
  perform pg_advisory_xact_lock(hashtext('english-invite:' || v_sender::text));
  select id into v_existing from public.english_battle_invitations
    where sender_id = v_sender and recipient_id = p_recipient_id
      and status = 'pending' and expires_at > now()
    order by created_at desc limit 1;
  if v_existing is not null then return v_existing; end if;
  if exists(select 1 from public.english_battle_invitations
    where sender_id = v_sender and recipient_id = p_recipient_id
      and created_at > now() - interval '20 seconds')
    or (select count(*) from public.english_battle_invitations
      where sender_id = v_sender and created_at > now() - interval '1 minute') >= 5 then
    raise exception 'Odczekaj chwilę przed kolejnym zaproszeniem.';
  end if;
  insert into public.english_battle_invitations(sender_id,recipient_id)
    values(v_sender,p_recipient_id) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.send_english_battle_invitation(uuid) from public, anon;
grant execute on function public.send_english_battle_invitation(uuid) to authenticated;

create or replace function public.get_english_battle_invitations()
returns table(id uuid,sender_id uuid,sender_name text,room_name text,expires_at timestamptz)
language sql stable security definer
set search_path = public, pg_temp
as $$
  select i.id,i.sender_id,p.display_name,i.room_name,i.expires_at
  from public.english_battle_invitations i
  join public.student_profiles p on p.user_id = i.sender_id
  where i.recipient_id = auth.uid() and i.status = 'pending' and i.expires_at > now()
  order by i.created_at limit 5;
$$;
revoke all on function public.get_english_battle_invitations() from public, anon;
grant execute on function public.get_english_battle_invitations() to authenticated;

create or replace function public.respond_english_battle_invitation(p_invitation_id uuid,p_accept boolean)
returns void language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'Zaloguj się, aby odpowiedzieć.'; end if;
  if p_accept is null then raise exception 'Wybierz odpowiedź na zaproszenie.'; end if;
  update public.english_battle_invitations
    set status = case when p_accept then 'accepted' else 'declined' end, responded_at = now()
    where id = p_invitation_id and recipient_id = auth.uid()
      and status = 'pending' and expires_at > now();
  if not found then raise exception 'Zaproszenie wygasło lub zostało już rozpatrzone.'; end if;
end;
$$;
revoke all on function public.respond_english_battle_invitation(uuid,boolean) from public, anon;
grant execute on function public.respond_english_battle_invitation(uuid,boolean) to authenticated;

do $$
begin
  if not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime'
    and schemaname = 'public' and tablename = 'english_battle_invitations') then
    alter publication supabase_realtime add table public.english_battle_invitations;
  end if;
end;
$$;
notify pgrst, 'reload schema';
