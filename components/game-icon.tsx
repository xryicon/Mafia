export function GameIcon({ name, size = 20 }: { name: string; size?: number }) {
  const paths: Record<string, string> = {
    overview: "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z",
    operations: "M9 4V2h6v2 M3 7h18v14H3z M3 12h18 M10 10h4v4h-4z",
    market: "M3 3h2l2 13h12l2-10H6 M8 20h.01 M18 20h.01",
    businesses: "M3 21V8l9-5v18 M12 10h9v11 M6 10h2 M6 14h2 M6 18h2 M15 14h3 M15 18h3",
    inventory: "m3 7 9-5 9 5v10l-9 5-9-5z M3 7l9 5 9-5 M12 12v10 M7 5l9 5",
    ledger: "M5 3h14v19l-3-2-4 2-4-2-3 2z M8 7h8 M8 11h8 M8 15h5",
    cash: "M3 6h18v12H3z M7 6c0 2-2 4-4 4 M21 14c-2 0-4 2-4 4 M12 9v6",
    respect: "m12 2 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1z",
    refresh: "M20 7a9 9 0 0 0-15-2L2 8 M2 2v6h6 M4 17a9 9 0 0 0 15 2l3-3 M22 22v-6h-6",
    arrow: "M5 12h14 M13 6l6 6-6 6",
    clock: "M12 8v5l3 2 M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0",
    shield: "M12 2 3 6v6c0 5 9 10 9 10s9-5 9-10V6z M8 12l3 3 5-6",
  };
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={paths[name] || paths.overview} /></svg>;
}
