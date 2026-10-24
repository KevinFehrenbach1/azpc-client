const {app,BrowserWindow,ipcMain,dialog,shell}=require('electron');
const path=require('path'); const fs=require('fs');
const os=require('os');
app.setAppUserModelId('market.azpc.launcher');
let win;
function createWindow(){win=new BrowserWindow({width:1040,height:770,minWidth:920,minHeight:680,center:true,icon:path.join(__dirname,'assets','azpc.ico'),backgroundColor:'#080c0f',title:'AZPC Launcher',autoHideMenuBar:true,webPreferences:{preload:path.join(__dirname,'preload.js'),contextIsolation:true,nodeIntegration:false,sandbox:true}});
win.loadFile('index.html');}
app.whenReady().then(()=>{createWindow();app.on('activate',()=>{if(BrowserWindow.getAllWindows().length===0)createWindow()})});
app.on('window-all-closed',()=>{if(process.platform!=='darwin')app.quit()});
ipcMain.handle('choose-folder',async()=>{const r=await dialog.showOpenDialog(win,{properties:['openDirectory']});return r.canceled?null:r.filePaths[0]});
ipcMain.handle('open-url',async(_e,url)=>{const allowed=['https://azpc.market/','https://forever.azpc.market/','https://anniversary.azpc.market/','https://github.com/KevinFehrenbach1/azpc-client'];if(!allowed.some(p=>url.startsWith(p)))throw new Error('Untrusted URL');await shell.openExternal(url)});
const configFile=()=>path.join(app.getPath('userData'),'launcher-settings.json');
function readConfig(){try{return JSON.parse(fs.readFileSync(configFile(),'utf8'))}catch{return {}}}
function gameRoot(){const c=readConfig();return c.gameFolder||'C:/Program Files (x86)/World of Warcraft'}
function installed(game){
 const root=gameRoot(),forever=game==='forever';
 const toc=path.join(root,forever?'_classic_beta_':'_anniversary_','Interface','AddOns',forever?'AZPCForever':'AZPC',forever?'AZPCForever.toc':'AZPC.toc');
 const result={version:app.getVersion(),gameFolder:root,gameFolderExists:fs.existsSync(root),game,addon:{installed:false,version:null},watcher:{installed:false,version:null}};
 try{const text=fs.readFileSync(toc,'utf8');result.addon={installed:true,version:(text.match(/^## Version:\\s*(\\S+)/m)||[])[1]||'Unknown'}}catch{}
 const local=process.env.LOCALAPPDATA||path.join(os.homedir(),'AppData','Local');
 const candidates=[path.join(local,'AZPC','AZPC-Watcher.ps1'),path.join(local,'AZPC','watcher','AZPC-Watcher.ps1')];
 for(const file of candidates){try{const text=fs.readFileSync(file,'utf8');result.watcher={installed:true,version:(text.match(/version\\s*=\\s*["']([0-9.]+)["']/i)||[])[1]||'Unknown'};break}catch{}}
 return result;
}
ipcMain.handle('get-status',async(_e,game)=>installed(game==='tbc'?'tbc':'forever'));
ipcMain.handle('save-folder',async(_e,folder)=>{if(typeof folder!=='string'||!fs.existsSync(folder)||!fs.statSync(folder).isDirectory())throw new Error('Choose an existing folder');const c=readConfig();c.gameFolder=folder;fs.mkdirSync(path.dirname(configFile()),{recursive:true});fs.writeFileSync(configFile(),JSON.stringify(c,null,2));return {saved:true,gameFolder:folder}});

ipcMain.handle('check-releases',async()=>{try{
 const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),12000);
 const r=await fetch('https://api.github.com/repos/KevinFehrenbach1/azpc-client/releases/latest',{headers:{'User-Agent':'AZPC-Launcher','Accept':'application/vnd.github+json'},signal:controller.signal});clearTimeout(timer);
 if(!r.ok)throw new Error('GitHub HTTP '+r.status);
 const d=await r.json();return {ok:true,tag:d.tag_name,url:d.html_url,checkedAt:new Date().toISOString(),note:'GitHub release lookup succeeded; component updates are not yet integrated.'};
 }catch(e){return {ok:false,error:e.message}}});
