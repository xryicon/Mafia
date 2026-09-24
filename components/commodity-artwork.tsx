import {GameIcon} from "@/components/game-icon";

const commodityArt:Record<string,string>={
 bandages:"/art/medical/bandages",
 bandages_blueprint:"/art/medical/bandages-blueprint",
 "m4-carbine":"/art/weapons/m4-carbine",
 "556x45mm-ammo":"/art/weapons/556x45mm-ammo",
 "homemade-pistol":"/art/crafting/homemade-pistol",
 "homemade-bullets":"/art/crafting/homemade-bullets",
 whiskey:"/art/commodities/whiskey",
 silk:"/art/commodities/silk",
 steel:"/art/commodities/steel",
 "iron-ore":"/art/resources/iron-ore",
 "copper-ore":"/art/resources/copper-ore",
 coal:"/art/resources/coal",
 stone:"/art/resources/stone",
 limestone:"/art/resources/limestone",
 pickaxe:"/art/loot/pickaxe",
 pistol_blueprint:"/art/loot/pistol_blueprint",
 bullet_blueprint:"/art/loot/bullet_blueprint",
 "iron-ingot":"/art/resources/iron-ingot",
 "copper-ingot":"/art/resources/copper-ingot",
};

// These images accompany the database commodity name, so they are decorative.
export function CommodityArtwork({goodId,size=56}:{goodId:string;size?:number}){
 if(goodId==="scrap-metal")return <span className="commodity-art" style={{width:size,height:size}} aria-hidden="true"><svg viewBox="0 0 100 100" width="100%" height="100%"><path d="M12 68L39 48L66 62L39 83ZM37 37L63 20L82 29L56 47ZM53 67L77 48L90 55L66 77Z" fill="#546064" stroke="#b99a67" strokeWidth="2"/><path d="M12 68V76L39 91V83M39 83L66 62V70L39 91M37 37V45L56 55V47M56 47L82 29V37L56 55M53 67V75L66 85V77L90 55V63L66 85" fill="#263439" stroke="#ab9166" strokeWidth="1.5"/><path d="M24 67L37 58M48 36L63 27M66 66L78 56" stroke="#cad0cc" strokeWidth="2"/></svg></span>;
 if(["reinforced_jacket_blueprint","kevlar_vest_blueprint"].includes(goodId))return <span className="commodity-art" style={{width:size,height:size,background:"#152b34",border:"1px solid #ba9d69"}} aria-hidden="true"><GameIcon name="blueprint" size={size*.7}/></span>;
 if(goodId==="reinforced-jacket"||goodId==="kevlar-vest")return <span className="commodity-art" style={{width:size,height:size}} aria-hidden="true"><svg viewBox="0 0 100 100" width="100%" height="100%"><path d={goodId==="reinforced-jacket"?"M32 15L20 22L8 60L23 66L29 47L27 88H73L71 47L77 66L92 60L80 22L68 15L50 24Z":"M30 12L19 25L24 48L23 87Q50 94 77 87L76 48L81 25L70 12L62 14Q61 30 50 30Q39 30 38 14Z"} fill={goodId==="reinforced-jacket"?"#544934":"#293a39"} stroke="#bea477" strokeWidth="2"/><path d="M50 30V87M30 40H44V56H30ZM56 40H70V56H56ZM31 67H44V80H31ZM56 67H69V80H56Z" fill="none" stroke="#b79e71" strokeWidth="1.4"/><path d="M32 18L43 34L50 25L57 34L68 18" fill="none" stroke="#d7bd8e"/></svg></span>;
 const art=commodityArt[goodId];
 const arsenalArt=goodId==="m4-carbine"||goodId==="556x45mm-ammo";
 return <picture className={`commodity-art${arsenalArt?" m4-arsenal-art":""}`} style={{width:size,height:size}} aria-hidden="true">
  {art?<img draggable={false} src={art+"-256.webp"} srcSet={art+"-96.webp 96w, "+art+"-256.webp 256w, "+art+".webp 512w"} sizes={size+"px"} alt="" width={512} height={512} loading="lazy" decoding="async"/>:<GameIcon name="inventory" size={Math.min(32,size*.6)}/>}
 </picture>;
}
