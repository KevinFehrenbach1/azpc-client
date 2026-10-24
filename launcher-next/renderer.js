const $=s=>document.querySelector(s);const $$=s=>document.querySelectorAll(s);
function page(id){$$('.page').forEach(e=>e.hidden=e.id!==id);$$('[data-page]').forEach(e=>e.classList.toggle('active',e.dataset.page===id));}
$$('[data-page]').forEach(e=>e.addEventListener('click',()=>page(e.dataset.page)));
$$('[data-link]').forEach(e=>e.addEventListener('click',()=>window.azpc.openUrl(e.dataset.link)));
async function check(){const status=$('#update-message');status.textContent='Checking GitHub releases…';const r=await window.azpc.releases();status.textContent=r.error?'Unable to check: '+r.error:'Latest published release: '+r.tag+' (component compatibility not yet verified)';}
$$('[data-check]').forEach(e=>e.addEventListener('click',check));
$$('[data-update]').forEach(e=>e.addEventListener('click',()=>{$('#update-message').textContent='Automatic installation is not connected yet. Your existing addon and watcher have not been modified.';page('updates')}));
$$('[data-folder]').forEach(e=>e.addEventListener('click',async()=>{const p=await window.azpc.chooseFolder();if(p)$$('.folder-path').forEach(n=>n.textContent=p)}));
window.azpc.status().then(s=>{$$('.launcher-version').forEach(e=>e.textContent='Launcher v'+s.version);if(s.gameFolder)$$('.folder-path').forEach(e=>e.textContent=s.gameFolder)});
