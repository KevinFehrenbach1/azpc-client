const {app,BrowserWindow,ipcMain,dialog,shell}=require('electron');
const path=require('path'); const fs=require('fs');
const os=require('os');
const {scan,games}=require('./game-detection');
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
 try{const data=fs.readFileSync(file,'utf8');result.watcher={installed:true,version:(data.match(/version\\s*=\\s*["']([0-9.]+)["']/i)||[])[1]||'Unknown'};break}catch{}
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
