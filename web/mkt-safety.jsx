// ═══════════════════════════════════════════════════════════════════════════
// Marketing — Safety & Trust (honest version)
// No Uber-copy-paste. What we do + what we don't.
// ═══════════════════════════════════════════════════════════════════════════

function MktSafety({ onNav }) {
  const doDont = [
    {
      k: 'do',
      t: 'Who\'s on the other end.',
      b: 'Every Vaahana user verifies their email. Many are linked to existing WhatsApp community groups. This is not a stranger-economy.',
    },
    {
      k: 'do',
      t: 'You coordinate, you choose.',
      b: 'You see the driver\'s name, photo, and WhatsApp number before the ride. You can back out, anytime, no questions asked.',
    },
    {
      k: 'do',
      t: 'Contact is on WhatsApp.',
      b: 'Your ride conversation stays in a platform you already trust — with a history you can see and share with your family if something feels off.',
    },
    {
      k: 'do',
      t: 'We report incidents honestly.',
      b: 'If something happens, we write about it (anonymized) in our journal. We don\'t hide behind PR. We don\'t let lawyers write safety copy.',
    },
    {
      k: 'dont',
      t: 'Full identity verification.',
      b: 'We verify emails and let community captains vouch. We don\'t run government-ID or fingerprint checks.',
    },
    {
      k: 'dont',
      t: '24/7 dispatch.',
      b: 'We don\'t have a safety team you can page at 3 AM. For emergencies, call 911. For everything else, hello@vaahana.com — usually same day.',
    },
    {
      k: 'dont',
      t: '$1M liability insurance.',
      b: 'We don\'t insure rides. Drivers are using their personal vehicles; personal auto insurance applies. We\'re upfront about this.',
    },
    {
      k: 'dont',
      t: 'Background checks.',
      b: 'Drivers are community members, not employees. We don\'t run criminal or driving-record checks. Captains know their drivers personally.',
    },
  ];

  return (
    <div className="vw-root vw-web-scroll" data-theme="dark" style={{ width: '100%', height: '100%' }}>
      <MktNav active="safety" onNav={onNav} />

      {/* Hero */}
      <section style={{ padding: '120px 32px 64px', background: 'var(--vw-bg)' }}>
        <div style={{ maxWidth: 920, margin: '0 auto' }}>
          <span className="vw-eyebrow">Safety, honestly</span>
          <h1 style={{
            fontFamily: 'var(--vw-serif)', fontSize: 72, lineHeight: 1.0, letterSpacing: '-2.2px',
            fontWeight: 400, marginTop: 24,
          }}>
            What we do, and<br />
            — more importantly —<br />
            <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>what we don't.</em>
          </h1>
          <p className="vw-lead" style={{ marginTop: 28, fontSize: 19, maxWidth: 620 }}>
            Most rideshare safety pages are PR-speak for things that aren't real. We'd rather tell you the truth, and
            let you decide if it's enough for your ride.
          </p>
        </div>
      </section>

      {/* What we do / don't — the honest list */}
      <section style={{ padding: '72px 32px 120px', background: 'var(--vw-bg)' }}>
        <div style={{ maxWidth: 1000, margin: '0 auto', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 64 }}>
          {/* What we do */}
          <div>
            <div style={{
              fontFamily: 'var(--vw-mono)', fontSize: 12, color: 'var(--vw-green)', letterSpacing: '0.12em',
              textTransform: 'uppercase', marginBottom: 28,
              display: 'inline-flex', alignItems: 'center', gap: 8,
              padding: '6px 12px', border: '1px solid var(--vw-green)', borderRadius: 999,
            }}>
              <Icon name="check" size={14} color="var(--vw-green)" strokeWidth={2.5} />
              What we do
            </div>
            {doDont.filter(x => x.k === 'do').map(item => (
              <div key={item.t} style={{ padding: '24px 0', borderTop: '1px solid var(--vw-divider)' }}>
                <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 22, fontWeight: 500, letterSpacing: '-0.3px', lineHeight: 1.25 }}>
                  {item.t}
                </div>
                <div style={{ fontSize: 15, color: 'var(--vw-text-2)', lineHeight: 1.6, marginTop: 10 }}>
                  {item.b}
                </div>
              </div>
            ))}
          </div>
          {/* What we don't */}
          <div>
            <div style={{
              fontFamily: 'var(--vw-mono)', fontSize: 12, color: 'var(--vw-muted)', letterSpacing: '0.12em',
              textTransform: 'uppercase', marginBottom: 28,
              display: 'inline-flex', alignItems: 'center', gap: 8,
              padding: '6px 12px', border: '1px solid var(--vw-border-2)', borderRadius: 999,
            }}>
              <Icon name="x" size={14} color="var(--vw-muted)" strokeWidth={2.5} />
              What we don't do (yet)
            </div>
            {doDont.filter(x => x.k === 'dont').map(item => (
              <div key={item.t} style={{ padding: '24px 0', borderTop: '1px solid var(--vw-divider)' }}>
                <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 22, fontWeight: 500, letterSpacing: '-0.3px', lineHeight: 1.25 }}>
                  {item.t}
                </div>
                <div style={{ fontSize: 15, color: 'var(--vw-text-2)', lineHeight: 1.6, marginTop: 10 }}>
                  {item.b}
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* The trust move — explicitly NOT claiming Uber-grade theater */}
      <section style={{ padding: '120px 32px', background: 'var(--vw-bg-alt)', borderTop: '1px solid var(--vw-divider)', borderBottom: '1px solid var(--vw-divider)' }}>
        <div style={{ maxWidth: 860, margin: '0 auto' }}>
          <p style={{
            fontFamily: 'var(--vw-serif)', fontSize: 38, lineHeight: 1.25, letterSpacing: '-1px',
            fontWeight: 400, fontStyle: 'italic',
            borderLeft: '4px solid var(--vw-brand)', paddingLeft: 32,
          }}>
            Not claiming Uber-grade safety theater is what makes us trustworthy. When something is real, we'll say so.
            Until then, we say what it actually is.
          </p>
        </div>
      </section>

      {/* Contact */}
      <section style={{ padding: '120px 32px', background: 'var(--vw-bg)', textAlign: 'center' }}>
        <div style={{ maxWidth: 640, margin: '0 auto' }}>
          <h2 style={{ fontFamily: 'var(--vw-serif)', fontSize: 48, letterSpacing: '-1.2px', lineHeight: 1.1, fontWeight: 400 }}>
            Questions? Email a founder.
          </h2>
          <p className="vw-lead" style={{ marginTop: 20 }}>
            Reply to <span style={{ color: 'var(--vw-brand)' }}>founder@vaahana.com</span> — usually same day.
          </p>
          <div style={{ display: 'flex', gap: 12, marginTop: 32, justifyContent: 'center' }}>
            <Btn variant="primary" size="lg" iconR="arrowR">Contact a founder</Btn>
            <Btn variant="ghost" size="lg" onClick={() => onNav && onNav('trust')}>Read the policies</Btn>
          </div>
        </div>
      </section>

      <MktFooter onNav={onNav} />
    </div>
  );
}

Object.assign(window, { MktSafety });
