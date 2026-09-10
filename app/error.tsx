"use client";
export default function ErrorPage({ reset }: { reset: () => void }) {
  return <section className="message-page"><p className="eyebrow">A SMALL INTERRUPTION</p><h1>Let's try that again.</h1><p>We couldn't load this page. Please try again in a moment.</p><button className="button" onClick={reset}>Try again</button></section>;
}
