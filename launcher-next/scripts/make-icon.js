const sharp=require('sharp');const pngToIco=require('png-to-ico');const fs=require('fs');const path=require('path');
(async()=>{
const root=path.resolve(__dirname,'..');
const source=path.join(root,'assets','azpc-account-logo.png');
const meta=await sharp(source).metadata();
const crop=Math.min(meta.height,Math.floor(meta.width*0.35));
const left=0,top=0;
const png=await sharp(source).extract({left,top,width:crop,height:meta.height}).resize(256,256,{fit:'contain',background:'#14171c'}).png().toBuffer();
const ico=await pngToIco(png);
fs.writeFileSync(path.join(root,'assets','azpc.ico'),ico);
console.log('Created branded AZPC icon from official logo artwork');
})().catch(e=>{console.error(e);process.exit(1)});
