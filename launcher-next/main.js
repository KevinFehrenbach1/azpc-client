const {app,BrowserWindow,ipcMain,dialog,shell}=require('electron');
const path=require('path'); const fs=require('fs');
app.setAppUserModelId('market.azpc.launcher');
let win;
function createWindow(){win=new BrowserWindow({width:1040,height:770,minWidth:920,minHeight:680,center:true,icon:path.join(__dirname,'assets','azpc.ico'),backgroundColor:'#080c0f',title:'AZPC Launcher',autoHideMenuBar:true,webPreferences:{preload:path.join(__dirname,'preload.js'),contextIsolation:true,nodeIntegration:false,sandbox:true}});
win.loadFile('index.html');}
app.whenReady().then(()=>{createWindow();app.on('activate',()=>{if(BrowserWindow.getAllWindows().length===0)createWindow()})});
app.on('window-all-closed',()=>{if(process.platform!=='darwin')app.quit()});
ipcMain.handle('choose-folder',async()=>{const r=await dialog.showOpenDialog(win,{properties:['openDirectory']});return r.canceled?null:r.filePaths[0]});
ipcMain.handle('open-url',async(_e,url)=>{const allowed=['https://azpc.market/','https://forever.azpc.market/','https://anniversary.azpc.market/','https://github.com/KevinFehrenbach1/azpc-client'];if(!allowed.some(p=>url.startsWith(p)))throw new Error('Untrusted URL');await shell.openExternal(url)});
ipcMain.handle('get-status',async()=>({version:app.getVersion(),platform:process.platform,gameFolder:fs.existsSync('C:/Program Files (x86)/World of Warcraft')?'C:/Program Files (x86)/World of Warcraft':null}));
ipcMain.handle('check-releases',async()=>{try{
 const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),12000);
 const r=await fetch('https://api.github.com/repos/KevinFehrenbach1/azpc-client/releases/latest',{headers:{'User-Agent':'AZPC-Launcher','Accept':'application/vnd.github+json'},signal:controller.signal});clearTimeout(timer);
 if(!r.ok)throw new Error('GitHub HTTP '+r.status);
 const d=await r.json();return {ok:true,tag:d.tag_name,url:d.html_url,checkedAt:new Date().toISOString(),note:'GitHub release lookup succeeded; component updates are not yet integrated.'};
 }catch(e){return {ok:false,error:e.message}}});
