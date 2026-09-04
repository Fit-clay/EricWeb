import Link from "next/link";

type SectionPageProps = {
  seal: string;
  label: string;
  note: string;
  items: string[];
};

export function SectionPage({ seal, label, note, items }: SectionPageProps) {
  return (
    <main className="sub-page">
      <div className="paper-grain" />
      <div className="ink-wash ink-wash-one" />
      <div className="ink-wash ink-wash-two" />
      <div className="ink-wash ink-wash-three" />

      <Link className="back-link" href="/">
        归库
      </Link>

      <section className="sub-stage" aria-label={label}>
        <p className="sub-seal">{seal}</p>
        <p className="sub-label">{label}</p>
        <p className="sub-note">{note}</p>
        <ul className="sub-list">
          {items.map((item) => (
            <li key={item}>
              <span>{item}</span>
              <small>待入库</small>
            </li>
          ))}
        </ul>
      </section>
    </main>
  );
}
