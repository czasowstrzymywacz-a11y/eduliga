-- Only aggregate learning statistics and pseudonyms are shared between accounts.
create or replace function public.get_league_rankings(p_league text)
returns table(display_name text, stats jsonb, is_me boolean)
language sql stable security definer
set search_path = public, pg_temp
as $$
  with profiles as (
    select p.user_id, p.display_name, coalesce(pr.data, '{}'::jsonb) as progress
    from public.student_profiles p
    left join public.student_progress pr on pr.user_id = p.user_id
    where auth.uid() is not null and p_league in ('ortho', 'english')
  ), prepared as (
    select p.*, coalesce(progress->'englishLeague', '{}'::jsonb) as english,
      case when jsonb_typeof(progress->'sessions') = 'array' then progress->'sessions' else '[]'::jsonb end as sessions,
      case when jsonb_typeof(progress->'words') = 'object' then progress->'words' else '{}'::jsonb end as ortho_words
    from profiles p
  ), aggregates as (
    select p.*,
      (select jsonb_build_object(
        'points', coalesce(sum(round(score)), 0), 'sessions', count(*),
        'average', coalesce(round(avg(score)), 0),
        'weekly', count(*) filter (where item->>'date' >= (current_date - (extract(isodow from current_date)::int - 1))::text and item->>'date' <= current_date::text),
        'excellent', count(*) filter (where score >= 90))
       from (select item, case when item->>'score' ~ '^[0-9]+(\.[0-9]+)?$'
         then greatest(0, least(100, (item->>'score')::numeric)) else 0 end as score
         from jsonb_array_elements(p.sessions) as s(item)) scored) as ortho_stats,
      (select coalesce(jsonb_object_agg(key, greatest(0, least(2147483647, case when english->>key ~ '^[0-9]+(\.[0-9]+)?$' then (english->>key)::numeric else 0 end))), '{}'::jsonb)
       from unnest(array['xp','correct','wrong','rounds','bestStreak','battles','battleWins']) as keys(key)) as english_counts,
      (select count(*) from jsonb_each(p.ortho_words) w where case when w.value->>'correct' ~ '^[0-9]+$' then (w.value->>'correct')::numeric >= 2 else false end) as ortho_mastered,
      (select count(*) from jsonb_each(case when jsonb_typeof(english->'words')='object' then english->'words' else '{}'::jsonb end) w
       where case when w.value->>'correct' ~ '^[0-9]+$' and coalesce(w.value->>'wrong','0') ~ '^[0-9]+$'
         then (w.value->>'correct')::numeric >= 3 and round(100 * (w.value->>'correct')::numeric / greatest(1, (w.value->>'correct')::numeric + coalesce(w.value->>'wrong','0')::numeric)) >= 80 else false end) as english_mastered
    from prepared p
  ), result as (
    select a.user_id, a.display_name,
      case when p_league='ortho' then ortho_stats || jsonb_build_object(
        'mastered', ortho_mastered,
        'streak', case when progress->>'lastDay' >= (current_date-1)::text and progress->>'streak' ~ '^[0-9]+$' then least(2147483647, (progress->>'streak')::numeric) else 0 end)
      else jsonb_build_object(
        'points', english_counts->'xp', 'correct', english_counts->'correct',
        'accuracy', round(100 * (english_counts->>'correct')::numeric / greatest(1, (english_counts->>'correct')::numeric + (english_counts->>'wrong')::numeric)),
        'attempts', (english_counts->>'correct')::numeric + (english_counts->>'wrong')::numeric,
        'rounds', english_counts->'rounds', 'mastered', english_mastered,
        'bestStreak', english_counts->'bestStreak', 'battles', english_counts->'battles', 'wins', english_counts->'battleWins',
        'awards', jsonb_array_length(case when jsonb_typeof(english->'awards')='array' then english->'awards' else '[]'::jsonb end)) end as stats
    from aggregates a
  )
  select r.display_name, r.stats, r.user_id = auth.uid()
  from result r order by (r.stats->>'points')::numeric desc, r.display_name, r.user_id;
$$;
revoke all on function public.get_league_rankings(text) from public, anon;
grant execute on function public.get_league_rankings(text) to authenticated;
notify pgrst, 'reload schema';
