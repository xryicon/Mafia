import {GameIcon} from "@/components/game-icon";

const commodityArt:Record<string,string>={
 whiskey:"/art/commodities/whiskey",
 silk:"/art/commodities/silk",
 steel:"/art/commodities/steel",
 "iron-ore":"/art/resources/iron-ore",
 "copper-ore":"/art/resources/copper-ore",
 coal:"/art/resources/coal",
 stone:"/art/resources/stone",
 limestone:"/art/resources/limestone",
};

// These images accompany the database commodity name, so they are decorative.
export function CommodityArtwork({goodId,size=56}:{goodId:string;size?:number}){
 if(["iron-ingot","copper-ingot"].includes(goodId))return <span className={"commodity-art ingot-art "+goodId} style={{width:size,height:size}} aria-hidden="true"><svg width={size*.75} height={size*.75} viewBox="0 0 64 64" fill="none" stroke="currentColor" strokeWidth="1.5"><path d="m6 40 12-8 22 3 12 11-14 9-27-5z M6 40l32 6 14 0 M38 46v9 M14 23l13-9 20 3 11 12-14 8-27-5z M14 23l30 6h14 M44 29v8" fill="currentColor" fillOpacity=".22"/></svg></span>;
 const art=commodityArt[goodId];
 return <picture className="commodity-art" style={{width:size,height:size}} aria-hidden="true">
  {art?<img src={art+"-256.webp"} srcSet={art+"-96.webp 96w, "+art+"-256.webp 256w, "+art+".webp 512w"} sizes={size+"px"} alt="" width={512} height={512} loading="lazy" decoding="async"/>:<GameIcon name="inventory" size={Math.min(32,size*.6)}/>}
 </picture>;
}
