/* English league roster actions and recipient-only invitation notifications. */
(() => {
  const currentUser=()=>typeof syncUser!=='undefined'?syncUser:window.ortoligaSyncUser;
  const client=()=>window.ortoligaSyncClient;
  const escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const inviteStates=new Map();window.englishInviteStates=inviteStates;
  let generation=0,owner=null,channel=null,pollTimer=null,expiryTimer=null,statusTimer=null,polling=false;
  let invitations=[],busy=new Set(),errors=new Map(),handled=new Set();
  function refreshRoster(){if(typeof renderStudentRoster==='function')renderStudentRoster();}
  function status(message,error=false){const el=document.getElementById('battle-invite-status');if(!el)return;clearTimeout(statusTimer);el.hidden=!message;el.textContent=message;el.classList.toggle('error',error);if(message)statusTimer=setTimeout(()=>el.hidden=true,error?12000:8000);}
  function renderInvitations(){
    const root=document.getElementById('battle-invite-notifications');if(!root)return;
    clearTimeout(expiryTimer);invitations=invitations.filter(x=>Date.parse(x.expires_at)>Date.now());
    root.hidden=!invitations.length;
    root.innerHTML=invitations.slice(0,3).map(invite=>`<article class="battle-invite-card"><span class="invite-icon" aria-hidden="true">⚔️</span><div><h2>${escape(invite.sender_name)} zaprasza Cię do bitwy</h2><p>Dołącz do wspólnego pokoju Ligi Angielskiej.</p><small>Zaproszenie jest ważne przez 2 minuty.</small>${errors.has(invite.id)?`<p class="invite-error">${escape(errors.get(invite.id))}</p>`:''}<div class="invite-card-actions"><button class="primary" type="button" onclick="respondEnglishBattleInvite('${invite.id}',true)" ${busy.has(invite.id)?'disabled':''}>${busy.has(invite.id)?'Chwileczkę…':'Dołącz do bitwy →'}</button><button class="secondary" type="button" onclick="respondEnglishBattleInvite('${invite.id}',false)" ${busy.has(invite.id)?'disabled':''}>Nie teraz</button></div></div></article>`).join('');
    if(invitations.length)expiryTimer=setTimeout(renderInvitations,Math.max(100,Math.min(...invitations.map(x=>Date.parse(x.expires_at)-Date.now()))+50));
  }
  async function poll(){
    if(!owner||polling||!client())return;polling=true;const sequence=generation,id=owner;
    try{const {data:rows,error}=await client().rpc('get_english_battle_invitations');if(sequence!==generation||currentUser()?.id!==id)return;if(error)throw error;invitations=(rows||[]).filter(x=>x.room_name==='liga-angielska-open-room'&&!handled.has(x.id));renderInvitations();}
    catch(error){if(sequence===generation)console.warn('Battle invitations unavailable',error.message);}
    finally{if(sequence===generation)polling=false;}
  }
  function restart(){
    const user=currentUser(),nextOwner=user?.id||null;if(nextOwner===owner)return;
    generation++;owner=nextOwner;clearInterval(pollTimer);clearTimeout(expiryTimer);polling=false;
    const old=channel;channel=null;if(old)void client()?.removeChannel(old);
    invitations=[];busy=new Set();errors=new Map();handled=new Set();inviteStates.clear();status('');renderInvitations();refreshRoster();
    if(!owner||!client())return;
    const sequence=generation,id=owner,localChannel=client().channel('english-invitations:'+id);
    channel=localChannel;localChannel.on('postgres_changes',{event:'*',schema:'public',table:'english_battle_invitations',filter:'recipient_id=eq.'+id},()=>{if(sequence===generation)void poll();}).subscribe(state=>{if(state==='SUBSCRIBED'&&sequence===generation)void poll();});
    pollTimer=setInterval(()=>void poll(),10000);void poll();
  }
  async function inviteUser(targetId){
    const user=currentUser();if(!user){openSyncDialog();return;}if(!targetId||targetId===user.id)return;
    const previous=inviteStates.get(targetId);if(previous&&previous.until>Date.now())return;
    const id=user.id,sequence=generation,profile=typeof studentRoster!=='undefined'?studentRoster.find(x=>x.user_id===targetId):null;
    inviteStates.set(targetId,{label:'Łączenie…',until:Infinity});refreshRoster();status('Wchodzę do pokoju bitew…');
    try{
      await window.ensureEnglishBattleRoom();if(currentUser()?.id!==id||sequence!==generation)return;
      status('Wysyłam zaproszenie…');
      const {error}=await client().rpc('send_english_battle_invitation',{p_recipient_id:targetId});
      if(currentUser()?.id!==id||sequence!==generation)return;if(error)throw error;
      const sentState={label:'Zaproszono ✓',until:Date.now()+20000};inviteStates.set(targetId,sentState);refreshRoster();
      status('Zaproszenie do '+(profile?.display_name||'użytkownika')+' wysłane. Czekasz we wspólnym pokoju.');
      setTimeout(()=>{if(sequence===generation&&inviteStates.get(targetId)===sentState){inviteStates.delete(targetId);refreshRoster();}},20000);
    }catch(error){if(sequence!==generation)return;inviteStates.delete(targetId);refreshRoster();status(error.message||'Nie udało się wysłać zaproszenia. Spróbuj ponownie.',true);}
  }
  async function respond(invitationId,accept){
    const invite=invitations.find(x=>x.id===invitationId),user=currentUser(),sequence=generation;
    if(!invite||!user||busy.has(invitationId))return;
    if(Date.parse(invite.expires_at)<=Date.now()){renderInvitations();return;}
    busy.add(invitationId);errors.delete(invitationId);renderInvitations();
    try{
      if(accept)await window.ensureEnglishBattleRoom();
      if(sequence!==generation||currentUser()?.id!==user.id)return;
      const {error}=await client().rpc('respond_english_battle_invitation',{p_invitation_id:invitationId,p_accept:accept});
      if(sequence!==generation)return;if(error)throw error;
      handled.add(invitationId);invitations=invitations.filter(x=>x.id!==invitationId);renderInvitations();
      if(accept)status('Dołączono do pokoju bitew. Zaproszenie od '+invite.sender_name+' przyjęte.');
      void poll();
    }catch(error){if(sequence===generation){errors.set(invitationId,error.message||'Nie udało się dołączyć. Spróbuj ponownie.');}}
    finally{if(sequence===generation){busy.delete(invitationId);renderInvitations();}}
  }
  window.inviteEnglishBattleUser=inviteUser;window.respondEnglishBattleInvite=respond;
  window.refreshEnglishRoster=refreshRoster;
  window.addEventListener('ortoliga-auth-change',restart);
  document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible'){restart();void poll();if(typeof loadStudentRoster==='function')void loadStudentRoster();}});
  restart();
})();
