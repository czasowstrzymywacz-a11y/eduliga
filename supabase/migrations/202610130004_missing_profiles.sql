-- Named non-anonymous accounts must exist in the ranking profile registry.
create or replace function public.register_named_league_account()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare nickname text;
begin
 if coalesce(new.is_anonymous,false) then return new;end if;
 nickname:=left(btrim(coalesce(nullif(new.raw_user_meta_data->>'display_name',''),new.raw_user_meta_data->>'full_name','')),24);
 if length(nickname)<2 then return new;end if;
 insert into public.student_profiles(user_id,display_name,login_key,created_at)
 values(new.id,nickname,coalesce(lower(new.email),'account:'||new.id::text),new.created_at)
 on conflict do nothing;
 return new;
end;$$;
revoke all on function public.register_named_league_account() from public,anon,authenticated;
do $$begin
 if not exists(select 1 from pg_trigger where tgname='league_named_account_profile' and tgrelid='auth.users'::regclass) then
 create trigger league_named_account_profile after insert or update of raw_user_meta_data on auth.users
 for each row execute function public.register_named_league_account();
 end if;
end;$$;
insert into public.student_profiles(user_id,display_name,login_key,created_at)
select u.id,left(btrim(coalesce(nullif(u.raw_user_meta_data->>'display_name',''),u.raw_user_meta_data->>'full_name','')),24),
 coalesce(lower(u.email),'account:'||u.id::text),u.created_at
from auth.users u where not coalesce(u.is_anonymous,false)
 and length(btrim(coalesce(nullif(u.raw_user_meta_data->>'display_name',''),u.raw_user_meta_data->>'full_name','')))>=2
 and not exists(select 1 from public.student_profiles p where p.user_id=u.id)
on conflict do nothing;
notify pgrst,'reload schema';
