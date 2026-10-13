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
