const {app,BrowserWindow,ipcMain,dialog,shell}=require('electron');
const path=require('path'); const fs=require('fs');
app.setAppUserModelId('market.azpc.launcher');
let win;
function createWindow(){win=new BrowserWindow({width:1000,height:700,minWidth:860,minHeight:610,backgroundColor:'#080c0f',title:'AZPC Launcher',autoHideMenuBar:true,webPreferences:{preload:path.join(__dirname,'preload.js'),contextIsolation:true,nodeIntegration:false,sandbox:true}});
win.loadFile('index.html');}
app.whenReady().then(()=>{createWindow();app.on('activate',()=>{if(BrowserWindow.getAllWindows().length===0)createWindow()})});
app.on('window-all-closed',()=>{if(process.platform!=='darwin')app.quit()});
ipcMain.handle('choose-folder',async()=>{const r=await dialog.showOpenDialog(win,{properties:['openDirectory']});return r.canceled?null:r.filePaths[0]});
ipcMain.handle('open-url',async(_e,url)=>{const allowed=['https://azpc.market/','https://forever.azpc.market/','https://anniversary.azpc.market/','https://github.com/KevinFehrenbach1/azpc-client'];if(!allowed.some(p=>url.startsWith(p)))throw new Error('Untrusted URL');await shell.openExternal(url)});
ipcMain.handle('get-status',async()=>({version:app.getVersion(),platform:process.platform,gameFolder:fs.existsSync('C:/Program Files (x86)/World of Warcraft')?'C:/Program Files (x86)/World of Warcraft':null}));
ipcMain.handle('check-releases',async()=>{try{const r=await fetch('https://api.github.com/repos/KevinFehrenbach1/azpc-client/releases/latest',{headers:{'User-Agent':'AZPC-Launcher'}});if(!r.ok)throw new Error('GitHub HTTP '+r.status);const d=await r.json();return {tag:d.tag_name,url:d.html_url};}catch(e){return {error:e.message}}});
