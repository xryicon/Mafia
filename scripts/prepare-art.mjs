import sharp from "sharp";
import {mkdir,readFile,writeFile} from "node:fs/promises";
await mkdir("public/art",{recursive:true});
const report=[];
for(const name of ["harbor","distillery","textile","foundry","exchange"]){
 const source=await readFile("art-source/"+name+".png");
 const wide=await sharp(source).resize({width:name==="harbor"?1680:1280,withoutEnlargement:true}).webp({quality:82,effort:6}).toBuffer();
 const compact=await sharp(source).resize({width:720,withoutEnlargement:true}).webp({quality:78,effort:6}).toBuffer();
 await writeFile("public/art/"+name+".webp",wide);
 await writeFile("public/art/"+name+"-small.webp",compact);
 report.push({name,sourceBytes:source.length,webpBytes:wide.length,mobileBytes:compact.length});
}
await writeFile("public/art/manifest.json",JSON.stringify(report,null,2)+"\n");
console.log(JSON.stringify(report));
