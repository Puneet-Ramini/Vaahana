// ═══════════════════════════════════════════════════════════════════════════
// Marketing — Stories (community journal)
// Editorial. First-person. Each story has a why, not a "happy user testimonial."
// ═══════════════════════════════════════════════════════════════════════════

function MktCommunity({ onNav }) {
  const featured = {
    title: "I got to my sister's wedding because three strangers drove me in shifts.",
    by: 'Aisha K.',
    route: 'Rutgers → Boston, via Hartford',
    date: 'March 2025',
    tint: 'dusk',
    excerpt:
      "My flight got cancelled the day before my sister's wedding. Greyhound was sold out. I posted a ride on Vaahana at 11 PM, half-crying, and by 6 AM I had a reply from a driver going to Hartford. From there, someone's cousin. From there, a grad student doing Boston. I arrived in time to help with the mehendi. I still have all three of their WhatsApp numbers.",
  };

  const stories = [
    { tint: 'plum', q: "My dad stopped worrying about airport rides. He knows who's driving now.", n: 'Rohan S.', r: 'UT Dallas', tag: 'Trust' },
    { tint: 'forest', q: "I drive home every other weekend. Now I bring two students. They chip in for gas.", n: 'Vikram P.', r: 'MIT → Edison', tag: 'Drivers' },
    { tint: 'dawn', q: "First time I asked for a ride in this country without feeling like I was imposing.", n: 'Meera V.', r: 'Stanford', tag: 'Belonging' },
    { tint: 'golden', q: "The captain WhatsApp-ed me before my first ride to say 'the driver's a friend, you'll be fine.' I was.", n: 'Karan R.', r: 'UT Dallas', tag: 'Captains' },
    { tint: 'morning', q: "I thought I was too old for an app like this. I'm 54. I've given 22 rides.", n: 'Sunita I.', r: 'Iselin NJ', tag: 'Drivers' },
    { tint: 'sand', q: "We did a Diwali ride pool — 14 cars, 38 students, one WhatsApp group. Everyone got home.", n: 'Priya M.', r: 'Rutgers captain', tag: 'Events' },
  ];

  const tags = ['All stories', 'Drivers', 'Riders', 'Captains', 'Events', 'Belonging', 'Trust'];

  return (
    <div className="vw-root vw-web-scroll" data-theme="dark" style={{ width: '100%', height: '100%' }}>
      <MktNav active="community" onNav={onNav} />

      {/* Masthead */}
      <section style={{ padding: '96px 32px 48px', background: 'var(--vw-bg)', borderBottom: '1px solid var(--vw-divider)' }}>
        <div style={{ maxWidth: 1200, margin: '0 auto' }}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 40 }}>
            <div>
              <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 12, color: 'var(--vw-muted)', letterSpacing: '0.14em', textTransform: 'uppercase' }}>
                Vol. 02 · Spring 2026 · a journal from the community
              </div>
              <h1 style={{
                fontFamily: 'var(--vw-serif)', fontSize: 96, lineHeight: 0.96, letterSpacing: '-3.6px',
                fontWeight: 400, marginTop: 12,
              }}>
                Stories.
              </h1>
            </div>
            <div style={{ maxWidth: 380, paddingBottom: 20 }}>
              <p className="vw-lead" style={{ fontSize: 16, lineHeight: 1.55 }}>
                Every ride is a small story about getting somewhere. These are the ones people wrote down.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Tag filter */}
      <section style={{ padding: '28px 32px', background: 'var(--vw-bg)', borderBottom: '1px solid var(--vw-divider)', position: 'sticky', top: 60, zIndex: 20 }}>
        <div style={{ maxWidth: 1200, margin: '0 auto', display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          {tags.map((t, i) => (
            <button key={t} style={{
              padding: '7px 14px',
              fontSize: 13, fontFamily: 'var(--vw-mono)', letterSpacing: '0.04em',
              background: i === 0 ? 'var(--vw-text)' : 'transparent',
              color: i === 0 ? 'var(--vw-inverse)' : 'var(--vw-muted)',
              border: '1px solid ' + (i === 0 ? 'var(--vw-text)' : 'var(--vw-divider)'),
              borderRadius: 999, cursor: 'pointer',
            }}>
              {t}
            </button>
          ))}
        </div>
      </section>

      {/* Featured story */}
      <section style={{ padding: '80px 32px', background: 'var(--vw-bg)' }}>
        <div style={{ maxWidth: 1200, margin: '0 auto', display: 'grid', gridTemplateColumns: '1.1fr 1fr', gap: 72, alignItems: 'center' }}>
          <Photo tint={featured.tint} style={{ borderRadius: 20, height: 560 }} label={`${featured.route}`} />
          <div>
            <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 11, color: 'var(--vw-brand)', letterSpacing: '0.14em', textTransform: 'uppercase' }}>
              Featured · {featured.date}
            </div>
            <h2 style={{
              fontFamily: 'var(--vw-serif)', fontSize: 48, letterSpacing: '-1.4px', lineHeight: 1.1,
              fontWeight: 400, marginTop: 20,
            }}>
              "{featured.title}"
            </h2>
            <p style={{
              fontFamily: 'var(--vw-serif)', fontSize: 19, lineHeight: 1.65,
              color: 'var(--vw-text-2)', marginTop: 28,
            }}>
              {featured.excerpt}
            </p>
            <div style={{ marginTop: 40, display: 'flex', alignItems: 'center', gap: 14, paddingTop: 24, borderTop: '1px solid var(--vw-divider)' }}>
              <Avatar name={featured.by} size={48} />
              <div>
                <div style={{ fontSize: 15, fontWeight: 600 }}>— {featured.by}</div>
                <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 12, color: 'var(--vw-muted)', marginTop: 3 }}>
                  {featured.route}
                </div>
              </div>
              <a style={{ marginLeft: 'auto', fontSize: 14, color: 'var(--vw-brand)', cursor: 'pointer', fontWeight: 500 }}>
                Read the full story →
              </a>
            </div>
          </div>
        </div>
      </section>

      {/* Story grid */}
      <section style={{ padding: '80px 32px 120px', background: 'var(--vw-bg)' }}>
        <div style={{ maxWidth: 1200, margin: '0 auto' }}>
          <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 11, color: 'var(--vw-muted)', letterSpacing: '0.14em', textTransform: 'uppercase', marginBottom: 36 }}>
            More from the journal
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 28 }}>
            {stories.map(s => (
              <article key={s.n} style={{
                display: 'flex', flexDirection: 'column',
                cursor: 'pointer',
              }}>
                <Photo tint={s.tint} ratio="4/5" style={{ borderRadius: 14 }} label={s.r} />
                <div style={{ marginTop: 20, display: 'flex', gap: 10, alignItems: 'center' }}>
                  <span style={{
                    fontFamily: 'var(--vw-mono)', fontSize: 10, color: 'var(--vw-brand)',
                    letterSpacing: '0.12em', textTransform: 'uppercase',
                    padding: '3px 8px', border: '1px solid var(--vw-brand)', borderRadius: 999,
                  }}>{s.tag}</span>
                  <span style={{ fontFamily: 'var(--vw-mono)', fontSize: 11, color: 'var(--vw-muted)' }}>· {s.r}</span>
                </div>
                <div style={{
                  fontFamily: 'var(--vw-serif)', fontSize: 22, lineHeight: 1.35, marginTop: 14,
                  letterSpacing: '-0.3px', fontWeight: 400, fontStyle: 'italic',
                }}>
                  "{s.q}"
                </div>
                <div style={{ marginTop: 16, fontSize: 13, color: 'var(--vw-muted)', fontWeight: 500 }}>
                  — {s.n}
                </div>
              </article>
            ))}
          </div>
        </div>
      </section>

      {/* Submit your story */}
      <section style={{ padding: '120px 32px', background: 'var(--vw-bg-alt)', borderTop: '1px solid var(--vw-divider)' }}>
        <div style={{ maxWidth: 820, margin: '0 auto' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 64, alignItems: 'center' }}>
            <div>
              <span className="vw-eyebrow">Your turn</span>
              <h2 style={{ fontFamily: 'var(--vw-serif)', fontSize: 44, letterSpacing: '-1.3px', lineHeight: 1.1, fontWeight: 400, marginTop: 16 }}>
                Had a ride worth writing down?
              </h2>
              <p className="vw-lead" style={{ marginTop: 20, fontSize: 16 }}>
                Send us a paragraph or a page. We'll edit gently, credit you, and publish it in the next volume.
              </p>
            </div>
            <div style={{
              background: 'var(--vw-surface)', border: '1px solid var(--vw-divider)',
              borderRadius: 14, padding: 32,
            }}>
              <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 11, color: 'var(--vw-muted)', letterSpacing: '0.1em', textTransform: 'uppercase' }}>
                Submit
              </div>
              <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 22, marginTop: 10, fontWeight: 500, letterSpacing: '-0.3px', lineHeight: 1.3 }}>
                stories@vaahana.com
              </div>
              <div style={{ marginTop: 20, fontSize: 13.5, color: 'var(--vw-text-2)', lineHeight: 1.6 }}>
                Anonymous is fine. Long or short is fine. We're small — a founder will write back.
              </div>
              <Btn variant="primary" size="md" iconR="arrowR" style={{ marginTop: 24 }}>Draft an email</Btn>
            </div>
          </div>
        </div>
      </section>

      <MktFooter onNav={onNav} />
    </div>
  );
}

Object.assign(window, { MktCommunity });
