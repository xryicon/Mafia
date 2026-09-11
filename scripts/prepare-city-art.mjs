import sharp from "sharp";
const image=await sharp("public/art/city-map.png").webp({quality:88,effort:6}).toBuffer();
const encoded=image.toString("base64");
console.log("CITY_ART_BYTES "+image.length);
for(let n=0;n<encoded.length;n+=12000)console.log("CITY_ART_"+Math.floor(n/12000)+":"+encoded.slice(n,n+12000));
