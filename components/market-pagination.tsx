"use client";
export const MARKET_PAGE_SIZE=10;
export function MarketPagination({page,total,onPage,label}:{page:number;total:number;onPage:(page:number)=>void;label:string}){
 const pages=Math.max(1,Math.ceil(total/MARKET_PAGE_SIZE));if(pages===1)return null;
 return <nav className="market-pagination" aria-label={label+" pages"}><button className="market-outline" disabled={page===0} onClick={()=>onPage(page-1)}>Previous</button><span aria-live="polite">Page {page+1} of {pages} · {total} items</span><button className="market-outline" disabled={page>=pages-1} onClick={()=>onPage(page+1)}>Next</button></nav>;
}
