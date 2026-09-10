import Link from "next/link";
export default function NotFound() {
  return <section className="message-page"><p className="eyebrow">404 / WRONG ROOM</p><h1>This seat is empty.</h1><p>The page you're looking for isn't here.</p><Link className="button" href="/">Back home</Link></section>;
}
