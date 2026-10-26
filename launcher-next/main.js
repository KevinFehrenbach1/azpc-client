const {app,BrowserWindow,ipcMain,dialog,shell}=require('electron');
const path=require('path'); const fs=require('fs');
const os=require('os');
const {scan,games}=require('./game-detection');
const {execFile}=require('child_process');
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
function installed(game){
 const selected=games[game]?game:'forever';
 const config=readConfig();
 const found=scan(config.gameFolders?.[selected]||config.gameFolder);
 const target=found[selected];
 const result={version:app.getVersion(),game:selected,games:found,gameFolder:target.root,addonsFolder:target.addonPath,gameFolderExists:target.detected,addon:target.addon,watcher:{installed:false,version:null}};
 const local=process.env.LOCALAPPDATA||path.join(os.homedir(),'AppData','Local');
 for(const file of [path.join(local,'AZPC','AZPC-Watcher.ps1'),path.join(local,'AZPC','watcher','AZPC-Watcher.ps1')]){
 try{const data=fs.readFileSync(file,'utf8');result.watcher={installed:true,version:(data.match(/(?:version|watcherVersion)\s*[:=]\s*["']?v?([0-9]+(?:\.[0-9]+)+)/i)||[])[1]||'Unknown'};break}catch{}
 }
 return result;
}
ipcMain.handle('get-status',async(_e,game)=>installed(game));
ipcMain.handle('save-folder',async(_e,folder,game)=>{
 if(typeof folder!=='string'||!fs.existsSync(folder)||!fs.statSync(folder).isDirectory())throw new Error('Choose an existing folder');
 const selected=games[game]?game:'forever';
 const expected=games[selected].folder;
 const normalized=path.normalize(folder);
 const root=path.basename(normalized).toLowerCase()===expected.toLowerCase()?path.dirname(normalized):normalized;
 if(!fs.existsSync(path.join(root,expected)))throw new Error('Selected folder must contain '+expected);
 const c=readConfig();c.gameFolders={...(c.gameFolders||{}),[selected]:root};
 fs.mkdirSync(path.dirname(configFile()),{recursive:true});
 fs.writeFileSync(configFile(),JSON.stringify(c,null,2));
 return {saved:true,gameFolder:root};
});
ipcMain.handle('check-releases',async()=>{try{
 const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),12000);
 const r=await fetch('https://api.github.com/repos/KevinFehrenbach1/azpc-client/releases/latest',{headers:{'User-Agent':'AZPC-Launcher','Accept':'application/vnd.github+json'},signal:controller.signal});clearTimeout(timer);
 if(!r.ok)throw new Error('GitHub HTTP '+r.status);
 const d=await r.json();return {ok:true,tag:d.tag_name,url:d.html_url,checkedAt:new Date().toISOString(),note:'GitHub release lookup succeeded; component updates are not yet integrated.'};
 }catch(e){return {ok:false,error:e.message}}});

function watcherRuntime(){
 return new Promise(resolve=>{
 if(process.platform!=='win32')return resolve({running:false,detail:'Windows only'});
 const script=`$ErrorActionPreference='SilentlyContinue'; $task=Get-ScheduledTask -TaskName 'AZPC Watcher' -ErrorAction SilentlyContinue; $procs=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(powershell|pwsh)\\.exe$' -and $_.CommandLine -match 'AZPC[-_]?Watcher\\.ps1' }); [pscustomobject]@{ running=($procs.Count -gt 0); processCount=$procs.Count; taskState=if($task){[string]$task.State}else{'Not registered'} } | ConvertTo-Json -Compress`;
 execFile('powershell.exe',['-NoProfile','-NonInteractive','-Command',script],{windowsHide:true,timeout:7000,maxBuffer:20000},(err,stdout)=>{
 if(err)return resolve({running:false,detail:'Unable to inspect watcher process'});
 try{const d=JSON.parse(stdout);resolve({running:d.running===true,processCount:d.processCount||0,taskState:d.taskState||'Unknown'})}catch{resolve({running:false,detail:'Watcher status unavailable'})}
 });
 });
}
ipcMain.handle('watcher-runtime',watcherRuntime);
let accountWindow=null;
function accountSession(){
 if(!accountWindow||accountWindow.isDestroyed())return Promise.resolve({authenticated:false});
 return accountWindow.webContents.executeJavaScript(`(async()=>{try{const r=await fetch('https://azpc.market/api/account/session',{credentials:'include',cache:'no-store'});if(!r.ok)return {authenticated:false};const d=await r.json();if(d.authenticated!==true)return {authenticated:false};return {authenticated:true,name:String(d.displayName||d.name||d.user?.name||d.user?.displayName||'AZPC member').slice(0,100),email:String(d.email||d.user?.email||'').slice(0,160),characters:Array.isArray(d.characters)?d.characters.length:null}}catch(e){return {authenticated:false,error:String(e.message)}}})()`,true).catch(()=>({authenticated:false}));
}
ipcMain.handle('account-open',async()=>{
 if(accountWindow&&!accountWindow.isDestroyed()){accountWindow.focus();return {opened:true}}
 accountWindow=new BrowserWindow({width:900,height:720,minWidth:650,minHeight:500,parent:win,icon:path.join(__dirname,'assets','azpc.ico'),title:'AZPC Account',autoHideMenuBar:true,webPreferences:{partition:'persist:azpc-account',contextIsolation:true,nodeIntegration:false,sandbox:true}});
 accountWindow.webContents.setWindowOpenHandler(({url})=>{if(url.startsWith('https://')){shell.openExternal(url)}return {action:'deny'}});
 accountWindow.webContents.on('will-navigate',(event,url)=>{if(!url.startsWith('https://'))event.preventDefault()});
 await accountWindow.loadURL('https://azpc.market/login?return='+encodeURIComponent('https://azpc.market/account'));
 return {opened:true};
});
ipcMain.handle('account-status',accountSession);
