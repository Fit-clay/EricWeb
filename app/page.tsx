"use client";

import type { MouseEvent } from "react";
import { useState } from "react";
import { useRouter } from "next/navigation";

const entries = [
  { href: "/blog", label: "藏文入库", seal: "文" },
  { href: "/tools", label: "器用开匣", seal: "器" },
  { href: "/preview", label: "观景启窗", seal: "景" },
];

export default function Home() {
  const router = useRouter();
  const [selected, setSelected] = useState<string | null>(null);
  const [leaving, setLeaving] = useState(false);

  function enterPage(event: MouseEvent<HTMLAnchorElement>, href: string) {
    event.preventDefault();
    if (leaving) {
      return;
    }

    setSelected(href);
    setLeaving(true);
    window.setTimeout(() => router.push(href), 420);
  }

  return (
    <main className={`minimal-home ${leaving ? "is-leaving" : ""}`}>
      <div className="paper-grain" />
      <div className="ink-wash ink-wash-one" />
      <div className="ink-wash ink-wash-two" />
      <div className="ink-wash ink-wash-three" />

      <section className="home-stage" aria-label="貔貅">
        <h1 className="art-title" aria-label="貔貅">
          <span>貔</span>
          <span>貅</span>
        </h1>
        <nav className="entry-nav" aria-label="入口">
          {entries.map((entry) => (
            <a
              className={`entry-link ${selected === entry.href ? "is-selected" : ""}`}
              href={entry.href}
              key={entry.href}
              onClick={(event) => enterPage(event, entry.href)}
            >
              <span>{entry.label}</span>
              <i aria-hidden="true">{entry.seal}</i>
            </a>
          ))}
        </nav>
      </section>

      <div className="route-ink" aria-hidden="true" />
    </main>
  );
}
