create or replace function public.league_number_v50(value jsonb, key text)
returns numeric language sql immutable set search_path=public,pg_temp as $$
 select case when value->>key ~ '^-?[0-9]+(\.[0-9]+)?$' then (value->>key)::numeric else 0 end;
$$;
revoke all on function public.league_number_v50(jsonb,text) from public,anon,authenticated;
create or replace function public.league_stats_v50(progress jsonb, league text)
returns jsonb language plpgsql stable set search_path=public,pg_temp as $$
declare payload jsonb; item jsonb; events jsonb; words jsonb; n numeric:=0; correct_n numeric:=0; wrong_n numeric:=0;
 sessions_n integer:=0; weekly_n integer:=0; excellent_n integer:=0; score_sum numeric:=0; rounds_n integer:=0;
 battles_n integer:=0; wins_n integer:=0; mastered_n integer:=0; score_n numeric; streak_n numeric:=0;
begin
 if league='english' then
 payload:=coalesce(progress->'englishLeague','{}');n:=greatest(0,public.league_number_v50(payload,'xp'));
 correct_n:=greatest(0,public.league_number_v50(payload,'correct'));wrong_n:=greatest(0,public.league_number_v50(payload,'wrong'));
 rounds_n:=public.league_number_v50(payload,'rounds');battles_n:=public.league_number_v50(payload,'battles');wins_n:=public.league_number_v50(payload,'battleWins');
 elsif league in ('ortho','spanish') then
 payload:=coalesce(progress->(case when league='ortho' then 'orthoBattle' else 'spanishLeague' end),'{}');
 events:=case when jsonb_typeof(payload->'events')='array' then payload->'events' else '[]'::jsonb end;
 for item in select distinct on (e->>'id') e from jsonb_array_elements(events) x(e) where e->>'id' is not null loop
 n:=n+public.league_number_v50(item,'delta');
 if item->>'kind' in ('answer','battle') then if item->>'ok'='true' then correct_n:=correct_n+1;else wrong_n:=wrong_n+1;end if;end if;
 if item->>'kind'='series' then rounds_n:=rounds_n+1;end if;
 if item->>'kind'='match' then battles_n:=battles_n+1;if item->>'win'='true' then wins_n:=wins_n+1;end if;end if;
 end loop;
 else return '{}'::jsonb;end if;
 if league='ortho' then
 for item in select e from jsonb_array_elements(case when jsonb_typeof(progress->'sessions')='array' then progress->'sessions' else '[]'::jsonb end) x(e) loop
 score_n:=greatest(0,least(100,public.league_number_v50(item,'score')));n:=n+round(score_n);score_sum:=score_sum+score_n;sessions_n:=sessions_n+1;
 if score_n>=90 then excellent_n:=excellent_n+1;end if;
 if item->>'date'>=(current_date-(extract(isodow from current_date)::int-1))::text and item->>'date'<=current_date::text then weekly_n:=weekly_n+1;end if;
 end loop;
 if progress->>'lastDay'>=(current_date-1)::text then streak_n:=greatest(0,public.league_number_v50(progress,'streak'));end if;
 words:=case when jsonb_typeof(progress->'words')='object' then progress->'words' else '{}'::jsonb end;
 else words:=case when jsonb_typeof(payload->'words')='object' then payload->'words' else '{}'::jsonb end;end if;
 for item in select value from jsonb_each(words) loop
 if league='ortho' then if public.league_number_v50(item,'correct')>=2 then mastered_n:=mastered_n+1;end if;
 elsif public.league_number_v50(item,'correct')>=3 and round(100*public.league_number_v50(item,'correct')/greatest(1,public.league_number_v50(item,'correct')+public.league_number_v50(item,'wrong')))>=80 then mastered_n:=mastered_n+1;end if;
 end loop;
 return jsonb_build_object('points',greatest(0,n),'correct',correct_n,'attempts',correct_n+wrong_n,'accuracy',round(100*correct_n/greatest(1,correct_n+wrong_n)),
 'rounds',rounds_n,'battles',battles_n,'wins',wins_n,'mastered',mastered_n,'sessions',sessions_n,'weekly',weekly_n,'average',round(score_sum/greatest(1,sessions_n)),
 'excellent',excellent_n,'streak',streak_n,'bestStreak',greatest(0,public.league_number_v50(payload,'bestStreak')),
 'awards',jsonb_array_length(case when jsonb_typeof(payload->'awards')='array' then payload->'awards' else '[]'::jsonb end));
end;$$;
revoke all on function public.league_stats_v50(jsonb,text) from public,anon,authenticated;
create or replace function public.get_league_board(p_league text)
returns table(user_id uuid,display_name text,stats jsonb,is_me boolean)
language sql stable security definer set search_path=public,pg_temp as $$
 select p.user_id,p.display_name,public.league_stats_v50(coalesce(pr.data,'{}'),p_league),p.user_id=auth.uid()
 from public.student_profiles p left join public.student_progress pr on pr.user_id=p.user_id
 where auth.uid() is not null and p_league in ('ortho','english','spanish')
 order by (public.league_stats_v50(coalesce(pr.data,'{}'),p_league)->>'points')::numeric desc,p.display_name,p.user_id;
$$;
revoke all on function public.get_league_board(text) from public,anon;
grant execute on function public.get_league_board(text) to authenticated;
create or replace function public.get_league_roster_v50()
returns table(user_id uuid,display_name text,ortho_xp numeric,english_xp numeric,spanish_xp numeric)
language sql stable security definer set search_path=public,pg_temp as $$
 select p.user_id,p.display_name,(public.league_stats_v50(coalesce(pr.data,'{}'),'ortho')->>'points')::numeric,
 (public.league_stats_v50(coalesce(pr.data,'{}'),'english')->>'points')::numeric,
 (public.league_stats_v50(coalesce(pr.data,'{}'),'spanish')->>'points')::numeric
 from public.student_profiles p left join public.student_progress pr on pr.user_id=p.user_id where auth.uid() is not null;
$$;
revoke all on function public.get_league_roster_v50() from public,anon;
grant execute on function public.get_league_roster_v50() to authenticated;
notify pgrst,'reload schema';
