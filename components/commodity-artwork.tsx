import {GameIcon} from "@/components/game-icon";

const commodityArt:Record<string,string>={
 whiskey:"/art/commodities/whiskey",
 silk:"/art/commodities/silk",
 steel:"/art/commodities/steel",
};

// These images accompany the database commodity name, so they are decorative.
export function CommodityArtwork({goodId,size=56}:{goodId:string;size?:number}){
 const art=commodityArt[goodId];
 return <picture className="commodity-art" style={{width:size,height:size}} aria-hidden="true">
  {art?<img src={art+"-256.webp"} srcSet={art+"-96.webp 96w, "+art+"-256.webp 256w, "+art+".webp 512w"} sizes={size+"px"} alt="" width={512} height={512} loading="lazy" decoding="async"/>:<GameIcon name="inventory" size={Math.min(32,size*.6)}/>}
 </picture>;
}
