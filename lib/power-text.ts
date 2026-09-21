/** Display legacy score terminology without changing stored metric identifiers. */
export function powerText(text:string|null|undefined){return (text??"").replace(/\bRESPECT\b/g,"POWER").replace(/\bRespect\b/g,"Power").replace(/\brespect\b/g,"power");}
