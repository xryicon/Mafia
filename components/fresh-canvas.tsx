import {requireUser} from "@/lib/auth";

// Deliberately empty: each destination is a clean starting point for new gameplay.
export async function FreshCanvas({path,title}:{path:string;title:string}){
 await requireUser(path);
 return <section className="fresh-canvas" aria-label={title}><h1 className="sr-only">{title}</h1></section>;
}
