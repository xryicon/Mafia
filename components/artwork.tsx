type ArtName="harbor"|"distillery"|"textile"|"foundry"|"exchange";
export function Artwork({name,alt="",className="",priority=false}:{name:ArtName;alt?:string;className?:string;priority?:boolean}){
 return <picture className={"bw-art "+className}><source media="(max-width: 720px)" srcSet={"/art/"+name+"-small.webp"}/><img src={"/art/"+name+".webp"} alt={alt} width={name==="harbor"?1680:1280} height={name==="harbor"?945:853} loading={priority?"eager":"lazy"} fetchPriority={priority?"high":"auto"} decoding="async"/></picture>;
}
