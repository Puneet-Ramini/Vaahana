// ═══════════════════════════════════════════════════════════════════════════
// Marketing — Cities (honest version)
// Six campuses. Real numbers. Real captains. No "42 cities" theater.
// ═══════════════════════════════════════════════════════════════════════════

function MktCities({ onNav }) {
  const cities = [
    { name: 'Rutgers · Edison NJ',     riders: 412, rides: 128, captain: 'Priya M.', launched: 'Sep 2024', tint: 'dusk',
      note: 'Our origin city. Weekly EWR airport shuttles, weekend Manhattan runs.' },
    { name: 'MIT · Cambridge MA',      riders: 287, rides: 94,  captain: 'Rohan S.', launched: 'Jan 2025', tint: 'plum',
      note: 'South Asian Student Association–backed. Thanksgiving rides to NJ every fall.' },
    { name: 'Northeastern · Boston',   riders: 203, rides: 71,  captain: 'Aisha K.', launched: 'Feb 2025', tint: 'dawn',
      note: 'Grew off MIT. Big move-in week every Aug.' },
    { name: 'UT Austin',               riders: 178, rides: 62,  captain: 'Arjun D.', launched: 'Mar 2025', tint: 'golden',
      note: 'First Texas city. Austin ↔ Dallas every third weekend.' },
    { name: 'Stanford · Palo Alto',    riders: 156, rides: 53,  captain: 'Meera V.', launched: 'Sep 2025', tint: 'forest',
      note: 'West coast launch. SFO airport is the #1 route.' },
    { name: 'UT Dallas · Plano TX',    riders: 134, rides: 48,  captain: 'Karan R.', launched: 'Jan 2026', tint: 'sand',
      note: 'Newest. Diwali ride program launched here first.' },
  ];

  return (
    <div className="vw-root vw-web-scroll" data-theme="dark" style={{ width: '100%', height: '100%' }}>
      <MktNav active="cities" onNav={onNav} />

      {/* Hero */}
      <section style={{ padding: '120px 32px 72px', background: 'var(--vw-bg)' }}>
        <div style={{ maxWidth: 920, margin: '0 auto' }}>
          <span className="vw-eyebrow">Cities · as of April 2026</span>
          <h1 style={{
            fontFamily: 'var(--vw-serif)', fontSize: 72, lineHeight: 1, letterSpacing: '-2.2px',
            fontWeight: 400, marginTop: 24,
          }}>
            Six places.<br />
            And growing <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>slowly</em> on purpose.
          </h1>
          <p className="vw-lead" style={{ marginTop: 28, fontSize: 19, maxWidth: 620 }}>
            We launch when a captain volunteers. Not before. That doesn't scale, which is why it works.
          </p>
        </div>
      </section>

      {/* City grid */}
      <section style={{ padding: '32px 32px 120px', background: 'var(--vw-bg)' }}>
        <div style={{ maxWidth: 1200, margin: '0 auto' }}>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 24 }}>
            {cities.map(c => (
              <article key={c.name} style={{
                background: 'var(--vw-surface)', border: '1px solid var(--vw-divider)',
                borderRadius: 16, overflow: 'hidden',
                display: 'grid', gridTemplateColumns: '180px 1fr',
              }}>
                <Photo tint={c.tint} style={{ borderRadius: 0, width: '100%', height: '100%' }} />
                <div style={{ padding: 28 }}>
                  <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 11, color: 'var(--vw-muted)', letterSpacing: '0.1em', textTransform: 'uppercase' }}>
                    Launched {c.launched}
                  </div>
                  <h3 style={{ fontFamily: 'var(--vw-serif)', fontSize: 26, fontWeight: 500, letterSpacing: '-0.4px', marginTop: 6, lineHeight: 1.15 }}>
                    {c.name}
                  </h3>
                  <p style={{ fontSize: 14, color: 'var(--vw-text-2)', lineHeight: 1.55, marginTop: 12 }}>
                    {c.note}
                  </p>
                  <div style={{ display: 'flex', gap: 20, marginTop: 20, fontFamily: 'var(--vw-mono)', fontSize: 12, color: 'var(--vw-muted)' }}>
                    <span><span style={{ color: 'var(--vw-text)', fontWeight: 600 }}>{c.riders}</span> riders</span>
                    <span><span style={{ color: 'var(--vw-text)', fontWeight: 600 }}>{c.rides}</span> rides/month</span>
                  </div>
                  <div style={{ marginTop: 20, paddingTop: 16, borderTop: '1px solid var(--vw-divider)', display: 'flex', alignItems: 'center', gap: 12 }}>
                    <Avatar name={c.captain} size={32} />
                    <div>
                      <div style={{ fontSize: 13, fontWeight: 600 }}>{c.captain}</div>
                      <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 11, color: 'var(--vw-muted)' }}>City captain · WhatsApp</div>
                    </div>
                  </div>
                </div>
              </article>
            ))}
          </div>
        </div>
      </section>

      {/* Request a city */}
      <section style={{ padding: '120px 32px', background: 'var(--vw-bg-alt)', borderTop: '1px solid var(--vw-divider)' }}>
        <div style={{ maxWidth: 720, margin: '0 auto', textAlign: 'center' }}>
          <h2 style={{ fontFamily: 'var(--vw-serif)', fontSize: 52, letterSpacing: '-1.4px', lineHeight: 1.05, fontWeight: 400 }}>
            Not in your city?<br />
            <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>Volunteer to bring us there.</em>
          </h2>
          <p className="vw-lead" style={{ marginTop: 24 }}>
            If you can get 20 people in your community to sign up, we'll launch with you. You become the city captain.
          </p>
          <div style={{ marginTop: 32 }}>
            <Btn variant="primary" size="xl" iconR="arrowR" onClick={() => onNav && onNav('request-city')}>
              Request your city
            </Btn>
          </div>
        </div>
      </section>

      <MktFooter onNav={onNav} />
    </div>
  );
}

Object.assign(window, { MktCities });
