'use strict';
const fs=require('fs'),path=require('path'),os=require('os'),{execFileSync}=require('child_process');
const games={forever:{folder:'_classic_beta_',addon:'AZPCForever',toc:'AZPCForever.toc'},tbc:{folder:'_anniversary_',addon:'AZPC',toc:'AZPC.toc'},retail:{folder:'_retail_',addon:'AZPC',toc:'AZPC.toc'}};
function exists(p){try{return fs.statSync(p).isDirectory()}catch{return false}}
function registryRoots(){
 if(process.platform!=='win32')return [];
 const roots=[];
 for(const key of ['HKLM\\SOFTWARE\\WOW6432Node\\Blizzard Entertainment\\World of Warcraft','HKLM\\SOFTWARE\\Blizzard Entertainment\\World of Warcraft','HKCU\\SOFTWARE\\Blizzard Entertainment\\World of Warcraft']){
 try{const out=execFileSync('reg',['query',key],{encoding:'utf8',timeout:1500,windowsHide:true});for(const line of out.split(/\r?\n/)){const m=line.match(/^\s*(InstallPath|InstallLocation|Path)\s+REG_\w+\s+(.+)$/i);if(m)roots.push(m[2].trim())}}catch{}
 }
 return roots;
}
function candidates(saved){
 const roots=[saved,process.env.WOW_ROOT,process.env.ProgramFiles,process.env['ProgramFiles(x86)'],process.env.PUBLIC,...registryRoots()];
 const drives=new Set(['C:','D:','E:','F:']);
 if(process.env.SystemDrive)drives.add(process.env.SystemDrive);
 for(const drive of drives){roots.push(drive+path.sep+'Program Files (x86)',drive+path.sep+'Program Files',drive+path.sep+'Games',drive+path.sep+'World of Warcraft');}
 const result=new Set();
 for(const root of roots){if(!root||typeof root!=='string')continue;const p=path.normalize(root);for(const candidate of [p,path.join(p,'World of Warcraft'),path.join(p,'World of Warcraft Beta')])result.add(candidate)}
 return [...result];
}
function scan(saved){
 const found={};const roots=candidates(saved);
 for(const [key,game] of Object.entries(games)){
  const root=roots.find(r=>exists(path.join(r,game.folder)));
  const addonPath=root?path.join(root,game.folder,'Interface','AddOns'):null;
  const toc=addonPath?path.join(addonPath,game.addon,game.toc):null;
  let version=null;
  try{version=(fs.readFileSync(toc,'utf8').match(/^## Version:\s*(\S+)/m)||[])[1]||'Unknown'}catch{}
  found[key]={detected:!!root,root:root||null,addonPath,addon:{installed:!!toc&&fs.existsSync(toc),version}};
 }
 return found;
}
module.exports={scan,games};
