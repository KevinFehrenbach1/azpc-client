const $=s=>document.querySelector(s);const $$=s=>document.querySelectorAll(s);
function page(id){$$('.page').forEach(e=>e.hidden=e.id!==id);$$('[data-page]').forEach(e=>e.classList.toggle('active',e.dataset.page===id));}
$$('[data-page]').forEach(e=>e.addEventListener('click',()=>page(e.dataset.page)));
$$('[data-link]').forEach(e=>e.addEventListener('click',()=>window.azpc.openUrl(e.dataset.link)));
async function check(){const status=$('#update-message');status.textContent='Checking GitHub releases…';const r=await window.azpc.releases();status.textContent=r.ok?'✓ GitHub connection successful · Latest release: '+r.tag+' · Checked '+new Date(r.checkedAt).toLocaleTimeString()+' · Addon/watcher updates not yet integrated.':'✕ Update check failed: '+r.error;}
$$('[data-check]').forEach(e=>e.addEventListener('click',check));
$$('[data-update]').forEach(e=>e.addEventListener('click',()=>{$('#update-message').textContent='Automatic installation is not connected yet. Your existing addon and watcher have not been modified.';page('updates')}));
const game=()=>$('.game').value;
const BUILD_MARK='1.0.3-browser-auth';

async function refresh(){
 try{
 const state=await window.azpc.status(game());
 if(!state||!state.games)throw new Error('No game scan data returned');
 document.querySelectorAll('.launcher-version').forEach(e=>e.textContent='Launcher v'+state.version);
 document.querySelectorAll('.folder-path').forEach(e=>e.textContent=state.gameFolderExists?state.gameFolder:'Not detected — choose Browse');
 document.querySelectorAll('.addons-path').forEach(e=>e.textContent=state.addonsFolder||'Not detected');
 document.querySelectorAll('.detected-games').forEach(e=>e.textContent=Object.entries(state.games).filter(([key,val])=>val.detected).map(([key])=>({forever:'Forever Beta',tbc:'TBC Anniversary',retail:'Retail'})[key]).join(' · ')||'None found');
 document.querySelectorAll('.current-game').forEach(e=>e.textContent=$('.game').selectedOptions[0].textContent);
 const addon=state.addon.installed?'v'+state.addon.version:'Not installed';
 const watcher=state.watcher.installed?'v'+state.watcher.version:'Not detected';
 document.querySelectorAll('.addon-status').forEach(e=>e.textContent=addon);
 document.querySelectorAll('.watcher-status').forEach(e=>e.textContent=watcher);
 document.querySelectorAll('.addon-badge').forEach(e=>e.textContent=state.addon.installed?'Detected':'Not installed');
 document.querySelectorAll('.watcher-badge').forEach(e=>e.textContent=state.watcher.installed?'Detected':'Not detected');
 }catch(e){console.error('AZPC detection failed',e);document.querySelectorAll('.addon-status,.watcher-status').forEach(el=>el.textContent='Detection error');document.querySelectorAll('.addon-badge,.watcher-badge').forEach(el=>el.textContent='Error');document.querySelectorAll('.folder-path').forEach(el=>el.textContent='Detection error: '+e.message)}
}
document.querySelectorAll('[data-folder]').forEach(e=>e.addEventListener('click',async()=>{try{const p=await window.azpc.chooseFolder();if(p){await window.azpc.saveFolder(p,game());await refresh()}}catch(e){alert('Could not save game folder: '+e.message)}}));
$('.game').addEventListener('change',refresh);
refresh();
console.info('AZPC launcher renderer',BUILD_MARK);

async function refreshWatcher(){
 try{const state=await window.azpc.watcherRuntime();const label=state.running?'Running ('+state.processCount+' process'+(state.processCount===1?'':'es')+')':(state.detail||'Not running'+(state.taskState?' · Task: '+state.taskState:''));
 $$('.watcher-runtime').forEach(el=>el.textContent=label);
 }catch(e){$$('.watcher-runtime').forEach(el=>el.textContent='Status unavailable')}
}
async function refreshAccount(){
 try{const state=await window.azpc.accountStatus();
 $$('.account-name').forEach(el=>el.textContent=state.authenticated?state.name:(state.pending?'Complete sign-in in your browser':'Not signed in'));
 $$('.account-email').forEach(el=>el.textContent=state.authenticated?state.email:(state.pending?'Waiting for AZPC authorization…':'Google / Discord sign-in via your default browser'));
 }catch(e){$$('.account-name').forEach(el=>el.textContent='Account status unavailable')}
}
$$('[data-account-login]').forEach(button=>button.addEventListener('click',async()=>{
 button.disabled=true;try{await window.azpc.accountOpen();await refreshAccount()}catch(e){alert('Could not open AZPC sign in: '+e.message)}finally{button.disabled=false}
}));
window.addEventListener('focus',()=>{refreshWatcher();refreshAccount()});
refreshWatcher();refreshAccount();
setInterval(()=>{refreshWatcher();refreshAccount()},12000);
