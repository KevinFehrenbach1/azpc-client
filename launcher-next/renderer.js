const $=s=>document.querySelector(s);const $$=s=>document.querySelectorAll(s);
function page(id){$$('.page').forEach(e=>e.hidden=e.id!==id);$$('[data-page]').forEach(e=>e.classList.toggle('active',e.dataset.page===id));}
$$('[data-page]').forEach(e=>e.addEventListener('click',()=>page(e.dataset.page)));
$$('[data-link]').forEach(e=>e.addEventListener('click',()=>window.azpc.openUrl(e.dataset.link)));
async function check(){const status=$('#update-message');status.textContent='Checking GitHub releases…';const r=await window.azpc.releases();status.textContent=r.ok?'✓ GitHub connection successful · Latest release: '+r.tag+' · Checked '+new Date(r.checkedAt).toLocaleTimeString()+' · Addon/watcher updates not yet integrated.':'✕ Update check failed: '+r.error;}
$$('[data-check]').forEach(e=>e.addEventListener('click',check));
$$('[data-update]').forEach(e=>e.addEventListener('click',()=>{$('#update-message').textContent='Automatic installation is not connected yet. Your existing addon and watcher have not been modified.';page('updates')}));
const game=()=>$('.game').value;
async function refresh(){
 try{
 const state=await window.azpc.status(game());
 $('.launcher-version').forEach(e=>e.textContent='Launcher v'+state.version);
 $('.folder-path').forEach(e=>e.textContent=state.gameFolderExists?state.gameFolder:'Not detected — choose Browse');
 $('.addons-path').forEach(e=>e.textContent=state.addonsFolder||'Not detected');
 $('.detected-games').forEach(e=>e.textContent=Object.entries(state.games).filter(([key,val])=>val.detected).map(([key])=>({forever:'Forever Beta',tbc:'TBC Anniversary',retail:'Retail'})[key]).join(' · ')||'None found');
 $('.current-game').forEach(e=>e.textContent=$('.game').selectedOptions[0].textContent);
 const addon=state.addon.installed?'v'+state.addon.version:'Not installed';
 const watcher=state.watcher.installed?'v'+state.watcher.version:'Not detected';
 $('.addon-status').forEach(e=>e.textContent=addon);
 $('.watcher-status').forEach(e=>e.textContent=watcher);
 $('.addon-badge').forEach(e=>e.textContent=state.addon.installed?'Detected':'Not installed');
 $('.watcher-badge').forEach(e=>e.textContent=state.watcher.installed?'Detected':'Not detected');
 }catch(e){console.error(e)}
}
$('[data-folder]').forEach(e=>e.addEventListener('click',async()=>{try{const p=await window.azpc.chooseFolder();if(p){await window.azpc.saveFolder(p,game());await refresh()}}catch(e){alert('Could not save game folder: '+e.message)}}));
$('.game').addEventListener('change',refresh);
refresh();
