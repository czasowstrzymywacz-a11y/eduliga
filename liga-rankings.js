/* Shared sidebar: separate account rankings for each league. */
(() => {
  const categories = {
    ortho: [['points','Punkty XPo','XPo'],['sessions','Ukończone dyktanda','dykt.'],['weekly','Dyktanda w tym tygodniu','dykt.'],['average','Średni wynik','%'],['mastered','Słowa poprawnie ≥2 razy','słów'],['streak','Dni z rzędu','dni'],['excellent','Wyniki co najmniej 90%','wyników']],
    english: [['points','Punkty XP','XP'],['correct','Poprawne odpowiedzi','odp.'],['accuracy','Skuteczność','%'],['mastered','Opanowane czasowniki','słów'],['rounds','Ukończone serie','serii'],['bestStreak','Najlepsza seria odpowiedzi','odp.'],['battles','Ukończone bitwy','bitew'],['wins','Wygrane bitwy','zwycięstw'],['awards','Zdobyte odznaki','odznak']]
  };
  const root=document.getElementById('league-user-rankings'),list=document.getElementById('league-ranking-list'),select=document.getElementById('league-ranking-category');
  const cache=new Map();let generation=0,activeLeague=null;
  const escape=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const user=()=>typeof syncUser!=='undefined'?syncUser:null;
  const value=(row,key)=>Math.max(0,Number(row.stats?.[key])||0);
  const format=(number,unit)=>number.toLocaleString('pl-PL')+(unit==='%'?'%':' '+unit);
  function render(){
    if(!categories[activeLeague])return;
    if(!user()){list.innerHTML='<p class="empty-state">Zaloguj się, aby zobaczyć rankingi użytkowników. Wyniki gościa pozostają prywatne na urządzeniu.</p>';return;}
    const rows=cache.get(user().id+':'+activeLeague);if(!rows)return;
    const metric=select.value,category=categories[activeLeague].find(c=>c[0]===metric),eligible=rows.filter(row=>metric==='average'?value(row,'sessions')>=3:metric==='accuracy'?value(row,'attempts')>=10:true);
    const sorted=[...eligible].sort((a,b)=>value(b,metric)-value(a,metric)||String(a.display_name).localeCompare(String(b.display_name),'pl'));
    let place=0,previous=null;
    list.innerHTML=sorted.map((row,i)=>{
      const score=value(row,metric);if(score!==previous){place=i+1;previous=score;}
      const medal=place===1?'🥇':place===2?'🥈':place===3?'🥉':place+'.';
      const summary=activeLeague==='ortho'?
        [['sessions','Dyktanda'],['average','Średnia'],['mastered','Słowa ≥2×'],['streak','Dni z rzędu']]:
        [['correct','Poprawne'],['accuracy','Skuteczność'],['mastered','Słowa'],['rounds','Serie'],['wins','Wygrane'],['awards','Odznaki']];
      return `<article class="league-ranking-person ${row.is_me?'me':''}"><header><span>${medal}</span><b>${escape(row.display_name)}${row.is_me?' · Ty':''}</b></header><strong>${format(score,category[2])}</strong>${metric!=='points'?`<div class="league-ranking-points">${format(value(row,'points'),activeLeague==='ortho'?'XPo':'XP')}</div>`:''}<dl>${summary.map(([key,label])=>`<div><dt>${label}</dt><dd>${format(value(row,key),['average','accuracy'].includes(key)?'%':'').trim()}</dd></div>`).join('')}</dl></article>`;
    }).join('')||'<p class="empty-state">Brak wyników w tej kategorii. Średnia wymaga 3 dyktand, a skuteczność angielska 10 odpowiedzi.</p>';
    document.getElementById('league-ranking-note').textContent=metric==='average'?'Średnia po minimum 3 dyktandach.':metric==='accuracy'?'Skuteczność po minimum 10 odpowiedziach.':'Remis daje to samo miejsce. Rankingi obejmują zapisane wyniki kont.';
  }
  async function refresh(){
    const league=document.body.dataset.activeLeague,id=user()?.id,request=++generation;
    activeLeague=league;root.hidden=!categories[league];if(root.hidden)return;
    const heading=league==='ortho'?'🏆 Użytkownicy OrtoLigi':'🏆 Użytkownicy Ligi Angielskiej';document.getElementById('league-ranking-title').textContent=heading;
    if(select.dataset.league!==league){select.innerHTML=categories[league].map(([key,label])=>`<option value="${key}">${label}</option>`).join('');select.dataset.league=league;}
    if(!id){render();return;}
    if(cache.has(id+':'+league))render();else list.innerHTML='<p class="empty-state">Wczytuję ranking…</p>';
    try{
      const {data:rows,error}=await syncClient.rpc('get_league_rankings',{p_league:league});
      if(request!==generation||user()?.id!==id||document.body.dataset.activeLeague!==league)return;
      if(error)throw error;cache.set(id+':'+league,Array.isArray(rows)?rows:[]);render();
    }catch{if(request===generation){list.innerHTML='<p class="empty-state">Nie udało się odświeżyć rankingu. Spróbuj ponownie.</p>';}}
  }
  select.addEventListener('change',render);
  window.refreshLeagueRankings=refresh;
  // Existing ranking navigation and refresh buttons lead to the same sidebar.
  window.loadAllLeaderboards=refresh;
  window.addEventListener('ortoliga-auth-change',()=>{cache.clear();void refresh();});
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)void refresh();});
  window.addEventListener('online',()=>void refresh());
  setInterval(()=>{if(!document.hidden&&categories[document.body.dataset.activeLeague])void refresh();},30000);
  void refresh();
})();
