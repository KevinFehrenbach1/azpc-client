const {app,BrowserWindow,ipcMain,dialog,shell}=require('electron');
const path=require('path'); const fs=require('fs');
const os=require('os');
const crypto=require('crypto');
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


const LAUNCHER_RELEASE_PREFIX='launcher-v';
function versionParts(v){return String(v).replace(/^v/i,'').split('.').map(x=>Number(x)||0)}
function newer(a,b){const x=versionParts(a),y=versionParts(b);for(let i=0;i<Math.max(x.length,y.length);i++){if((x[i]||0)!==(y[i]||0))return (x[i]||0)>(y[i]||0)}return false}
async function launcherRelease(){
 const r=await fetch('https://api.github.com/repos/KevinFehrenbach1/azpc-client/releases?per_page=50',{headers:{'User-Agent':'AZPC-Launcher','Accept':'application/vnd.github+json'},signal:AbortSignal.timeout(15000)});
 if(!r.ok)throw new Error('GitHub releases unavailable (HTTP '+r.status+')');
 const releases=await r.json();
 const candidates=releases.filter(x=>!x.draft&&!x.prerelease&&/^launcher-v\d+\.\d+\.\d+$/.test(x.tag_name)).sort((a,b)=>newer(a.tag_name.slice(10),b.tag_name.slice(10))?-1:newer(b.tag_name.slice(10),a.tag_name.slice(10))?1:0);
 const found=candidates.find(x=>x.assets?.some(a=>/^AZPC.Launcher.*\.exe$/i.test(a.name)));
 if(!found)return {available:false,installed:app.getVersion(),reason:'No dedicated launcher installer release published yet'};
 const asset=found.assets.find(a=>/^AZPC.Launcher.*\.exe$/i.test(a.name));
 const version=found.tag_name.slice('launcher-v'.length);
 return {available:newer(version,app.getVersion()),installed:app.getVersion(),latest:version,downloadUrl:asset.browser_download_url,assetName:asset.name,assetSize:asset.size,digest:asset.digest||null,executable:process.execPath};
}
ipcMain.handle('launcher-update-check',async()=>launcherRelease());
ipcMain.handle('launcher-update-install',async()=>{
 const info=await launcherRelease();
 if(!info.available)throw new Error(info.reason||'Launcher is already up to date');
 if(!/^https:\/\/github\.com\/KevinFehrenbach1\/azpc-client\/releases\/download\//.test(info.downloadUrl))throw new Error('Unexpected update URL');
 const confirmation=await dialog.showMessageBox(win,{type:'question',buttons:['Cancel','Download installer'],defaultId:1,cancelId:0,title:'AZPC Launcher update',message:'Update AZPC Launcher to v'+info.latest+'?',detail:'The installer will be downloaded and opened. Your account and game files will not be modified by this download.'});
 if(confirmation.response!==1)return {cancelled:true};
 const r=await fetch(info.downloadUrl,{signal:AbortSignal.timeout(180000)});
 if(!r.ok)throw new Error('Installer download failed (HTTP '+r.status+')');
 const bytes=Buffer.from(await r.arrayBuffer());
 if(bytes.length<1000000||bytes.length>250000000||info.assetSize&&bytes.length!==info.assetSize)throw new Error('Unexpected installer size');
 if(info.digest?.startsWith('sha256:')&&crypto.createHash('sha256').update(bytes).digest('hex')!==info.digest.slice(7))throw new Error('Installer checksum mismatch');
 const file=path.join(app.getPath('temp'),'AZPC-Launcher-update-'+info.latest+'.exe');
 fs.writeFileSync(file,bytes,{flag:'w'});
 const result=await shell.openPath(file);
 if(result)throw new Error('Could not open installer: '+result);
 return {started:true,version:info.latest};
});

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

/*
 * Desktop authentication uses the system browser, never an embedded OAuth
 * password form. The AZPC backend must implement the documented desktop
 * authorization-code endpoints before account pairing can succeed.
 */
const http=require('http');
let desktopSession=null;
let pendingLogin=null;
function publicAccount(){return desktopSession?{authenticated:true,name:desktopSession.name,email:desktopSession.email,provider:desktopSession.provider}:{authenticated:false,pending:!!pendingLogin,reason:pendingLogin?'Waiting for browser authorization':'Not connected'};}
ipcMain.handle('account-status',()=>publicAccount());
ipcMain.handle('account-open',async()=>{
 if(pendingLogin)return {opened:true,pending:true};
 const state=crypto.randomBytes(24).toString('hex');
 const verifier=crypto.randomBytes(32).toString('base64url');
 const challenge=crypto.createHash('sha256').update(verifier).digest('base64url');
 const server=http.createServer();
 let timeout;
 try{
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve)});
 const port=server.address().port;
 const callback='http://127.0.0.1:'+port+'/callback';
 pendingLogin={server,state,verifier};
 const close=()=>{clearTimeout(timeout);pendingLogin=null;server.close()};
 timeout=setTimeout(close,180000);
 server.on('request',async(req,res)=>{
  const u=new URL(req.url,'http://127.0.0.1:'+port);
  if(u.pathname!=='/callback'){res.writeHead(404).end();return}
  if(u.searchParams.get('state')!==state){res.writeHead(403).end('Invalid login state');return}
  const code=u.searchParams.get('code');
  if(!code){res.writeHead(400).end('No authorization code supplied');close();return}
  try{
   const response=await fetch('https://azpc.market/api/desktop-auth/exchange',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code,code_verifier:verifier,redirect_uri:callback}),signal:AbortSignal.timeout(12000)});
   if(!response.ok)throw new Error('AZPC desktop authorization endpoint unavailable (HTTP '+response.status+')');
   const data=await response.json();
   if(!data.access_token||!data.user||!data.user.id)throw new Error('Invalid desktop authorization response');
   desktopSession={token:data.access_token,name:String(data.user.displayName||data.user.name||'AZPC member').slice(0,100),email:String(data.user.email||'').slice(0,160),provider:String(data.user.provider||'AZPC')};
   if(win&&!win.isDestroyed()){if(win.isMinimized())win.restore();win.show();win.focus();}
   res.writeHead(303,{'Location':'https://azpc.market/account','Cache-Control':'no-store','Referrer-Policy':'no-referrer','Content-Length':'0'}).end();
  }catch(err){res.writeHead(502,{'Content-Type':'text/plain'}).end('AZPC desktop sign-in could not finish: '+err.message)}finally{close()}
 });
 const authUrl=new URL('https://azpc.market/desktop-auth/authorize');
 authUrl.searchParams.set('redirect_uri',callback);
 authUrl.searchParams.set('state',state);
 authUrl.searchParams.set('code_challenge',challenge);
 authUrl.searchParams.set('code_challenge_method','S256');
 await shell.openExternal(authUrl.toString());
 return {opened:true,pending:true};
 }catch(err){if(pendingLogin){clearTimeout(timeout);pendingLogin=null;server.close()}throw err}
});
ipcMain.handle('account-signout',()=>{desktopSession=null;return {authenticated:false}});

ipcMain.handle('account-pair',async(_event,code)=>{
 const normalized=String(code||'').trim().toUpperCase();
 if(!/^[A-Z0-9]{6}-[A-Z0-9]{6}$/.test(normalized))throw new Error('Enter the 12-character pairing code');
 const response=await fetch('https://azpc.market/api/desktop-auth/pair/redeem',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code:normalized}),signal:AbortSignal.timeout(15000)});
 const data=await response.json().catch(()=>({}));
 if(!response.ok)throw new Error(data.error||'Pairing failed (HTTP '+response.status+')');
 if(!data.access_token||!data.user?.id)throw new Error('Invalid AZPC account response');
 desktopSession={token:data.access_token,name:String(data.user.displayName||'AZPC member'),email:String(data.user.email||''),provider:'AZPC'};
 return publicAccount();
});
