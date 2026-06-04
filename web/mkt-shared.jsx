// ═══════════════════════════════════════════════════════════════════════════
// Marketing — shared nav, footer, and editorial primitives
// ═══════════════════════════════════════════════════════════════════════════

// Small photo placeholder — warm, filmic gradients standing in for real
// community photography. Each has a "label" to make intent clear for review.
function Photo({ tint = 'dusk', ratio = '4/3', label, style, children }) {
  const tints = {
    dusk:    'linear-gradient(135deg, #c89b7b 0%, #6b4e7e 50%, #2d3561 100%)',
    golden:  'linear-gradient(145deg, #f4c47c 0%, #d87c5a 50%, #8b3d3d 100%)',
    morning: 'linear-gradient(160deg, #e8d4b0 0%, #d8a373 40%, #8b7355 100%)',
    forest:  'linear-gradient(150deg, #4a6b4c 0%, #2a3f2d 50%, #1a2520 100%)',
    dawn:    'linear-gradient(150deg, #f8e5c4 0%, #e8a87c 50%, #a16b54 100%)',
    plum:    'linear-gradient(145deg, #8e6b82 0%, #4a3b4f 50%, #2a1f30 100%)',
    slate:   'linear-gradient(165deg, #6b7c8c 0%, #3a4a5c 50%, #1a2028 100%)',
    sand:    'linear-gradient(155deg, #ede0c8 0%, #c9b088 50%, #8f7656 100%)',
    night:   'linear-gradient(180deg, #1a1f2e 0%, #0f1520 100%)',
    mono:    'linear-gradient(165deg, #e8e5de 0%, #a8a59c 50%, #4a4740 100%)',
  };
  return (
    <div style={{
      background: tints[tint] || tints.dusk,
      aspectRatio: ratio,
      borderRadius: 12,
      position: 'relative',
      overflow: 'hidden',
      display: 'flex', alignItems: 'flex-end', padding: 16,
      color: '#fff',
      fontSize: 11, fontFamily: 'var(--vw-mono)',
      letterSpacing: '0.02em',
      ...style,
    }}>
      {/* noise texture */}
      <div style={{
        position: 'absolute', inset: 0, pointerEvents: 'none',
        background: 'radial-gradient(circle at 30% 20%, rgba(255,255,255,0.08), transparent 50%)',
        mixBlendMode: 'overlay', opacity: 0.7,
      }} />
      {label && (
        <span style={{
          position: 'relative', padding: '4px 8px',
          background: 'rgba(0,0,0,0.4)',
          backdropFilter: 'blur(4px)',
          borderRadius: 4,
          opacity: 0.9,
        }}>{label}</span>
      )}
      {children}
    </div>
  );
}

// Rating bar / stat strip reused in hero / sections
function StatStrip({ items, style }) {
  return (
    <div style={{
      display: 'grid', gridTemplateColumns: `repeat(${items.length}, 1fr)`,
      borderTop: '1px solid var(--vw-border)',
      borderBottom: '1px solid var(--vw-border)',
      ...style,
    }}>
      {items.map((it, i) => (
        <div key={i} style={{
          padding: '20px 24px',
          borderRight: i < items.length - 1 ? '1px solid var(--vw-border)' : 'none',
        }}>
          <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 34, fontWeight: 400, letterSpacing: '-0.02em', lineHeight: 1 }}>
            {it.value}
          </div>
          <div style={{ fontSize: 12, color: 'var(--vw-muted)', marginTop: 8, letterSpacing: '0.02em' }}>
            {it.label}
          </div>
        </div>
      ))}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Top nav — sleek, token-driven, translucent on scroll.
// No hardcoded colors; reads from --vw-bg / --vw-text so it flips cleanly
// when the page swaps themes.
// ──────────────────────────────────────────────────────────────────────────
function MktNav({ active, onNav }) {
  const items = [
    { id: 'riders',    label: 'Riders' },
    { id: 'drivers',   label: 'Drivers' },
    { id: 'cities',    label: 'Cities' },
    { id: 'safety',    label: 'Safety' },
    { id: 'manifesto', label: 'Manifesto' },
    { id: 'community', label: 'Stories' },
  ];
  return (
    <nav style={{
      position: 'sticky', top: 0, zIndex: 40,
      // Translucent tinted glass using the token — works in either theme
      background: 'color-mix(in srgb, var(--vw-bg) 78%, transparent)',
      backdropFilter: 'saturate(180%) blur(20px)',
      WebkitBackdropFilter: 'saturate(180%) blur(20px)',
      borderBottom: '1px solid var(--vw-divider)',
    }}>
      <div style={{
        maxWidth: 1280, margin: '0 auto', padding: '0 28px',
        height: 60, display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 28,
      }}>
        <button onClick={() => onNav && onNav('home')} style={{
          background:'none', border:'none', cursor:'pointer', padding:0,
          color: 'var(--vw-text)', display: 'inline-flex', alignItems: 'center',
        }} aria-label="Vaahana home">
          <Wordmark size={22} accent="var(--vw-brand)" />
        </button>

        <div style={{ display: 'flex', gap: 2, flex: 1, justifyContent: 'center' }}>
          {items.map(it => {
            const isActive = active === it.id;
            return (
              <button key={it.id}
                onClick={() => onNav && onNav(it.id)}
                style={{
                  padding: '7px 12px',
                  fontSize: 13.5,
                  fontWeight: isActive ? 600 : 500,
                  background: 'transparent',
                  border: 'none',
                  borderRadius: 8,
                  color: isActive ? 'var(--vw-text)' : 'var(--vw-muted)',
                  cursor: 'pointer',
                  fontFamily: 'inherit',
                  letterSpacing: '-0.005em',
                  transition: 'color .15s ease',
                }}
                onMouseEnter={e => { if (!isActive) e.currentTarget.style.color = 'var(--vw-text)'; }}
                onMouseLeave={e => { if (!isActive) e.currentTarget.style.color = 'var(--vw-muted)'; }}
              >
                {it.label}
              </button>
            );
          })}
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <Btn variant="ghost" size="sm" onClick={() => onNav && onNav('login')}>Sign in</Btn>
          <Btn variant="primary" size="sm" onClick={() => onNav && onNav('download')}>Get the app</Btn>
        </div>
      </div>
    </nav>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Footer
// ──────────────────────────────────────────────────────────────────────────
function MktFooter({ onNav }) {
  const cols = [
    {
      title: 'Product',
      items: [['For riders','riders'],['For drivers','drivers'],['Cities','cities'],['Pricing','pricing'],['Download','download']],
    },
    {
      title: 'Company',
      items: [['About','about'],['Careers','careers'],['Press','press'],['Community','community'],['Blog',null]],
    },
    {
      title: 'Safety & trust',
      items: [['Safety center','safety'],['Trust & policies','trust'],['Accessibility',null],['Report an issue','help'],['Driver requirements','drivers']],
    },
    {
      title: 'Support',
      items: [['Help center','help'],['Contact us',null],['Lost item',null],['Feedback',null],['Refund policy',null]],
    },
  ];
  return (
    <footer style={{ background: 'var(--vw-bg-alt)', borderTop: '1px solid var(--vw-border)', padding: '80px 32px 40px', color: 'var(--vw-text-2)' }}>
      <div style={{ maxWidth: 1280, margin: '0 auto' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1.4fr repeat(4, 1fr)', gap: 48, marginBottom: 64 }}>
          <div>
            <Wordmark size={26} />
            <p style={{ marginTop: 20, fontSize: 14, lineHeight: 1.6, color: 'var(--vw-muted)', maxWidth: 280 }}>
              Rides between neighbors. Built for the South Asian diaspora, open to everyone going the same way.
            </p>
            <div style={{ display: 'flex', gap: 12, marginTop: 24 }}>
              {[
                {name:'App Store', sub:'Download on the'},
                {name:'Google Play', sub:'Get it on'},
              ].map(s => (
                <button key={s.name} style={{
                  display: 'inline-flex', alignItems: 'center', gap: 10,
                  padding: '8px 14px',
                  background: 'var(--vw-text)', color: 'var(--vw-inverse)',
                  border: 'none', borderRadius: 8, cursor: 'pointer',
                  fontFamily: 'inherit', fontSize: 11, textAlign: 'left',
                }}>
                  <Icon name="download" size={18} color="var(--vw-inverse)" />
                  <div>
                    <div style={{ fontSize: 9, opacity: 0.7, letterSpacing: '0.02em' }}>{s.sub}</div>
                    <div style={{ fontWeight: 600, fontSize: 13 }}>{s.name}</div>
                  </div>
                </button>
              ))}
            </div>
          </div>
          {cols.map(c => (
            <div key={c.title}>
              <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.12em', textTransform: 'uppercase', color: 'var(--vw-muted)', fontFamily: 'var(--vw-mono)', marginBottom: 16 }}>
                {c.title}
              </div>
              <ul style={{ listStyle: 'none', padding: 0, margin: 0, display: 'flex', flexDirection: 'column', gap: 10 }}>
                {c.items.map(([label, route]) => (
                  <li key={label}>
                    <a onClick={() => route && onNav && onNav(route)} style={{
                      fontSize: 14, color: 'var(--vw-text-2)', cursor: route ? 'pointer' : 'default',
                      textDecoration: 'none', borderBottom: 'none',
                    }}>{label}</a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div style={{
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          paddingTop: 32, borderTop: '1px solid var(--vw-border)',
          fontSize: 12, color: 'var(--vw-muted)',
        }}>
          <div>© 2026 Vaahana, Inc. All rights reserved.</div>
          <div style={{ display: 'flex', gap: 20 }}>
            <a style={{ color: 'inherit', textDecoration: 'none', borderBottom: 'none' }}>Privacy</a>
            <a style={{ color: 'inherit', textDecoration: 'none', borderBottom: 'none' }}>Terms</a>
            <a style={{ color: 'inherit', textDecoration: 'none', borderBottom: 'none' }}>Cookies</a>
            <a style={{ color: 'inherit', textDecoration: 'none', borderBottom: 'none' }}>Sitemap</a>
          </div>
        </div>
      </div>
    </footer>
  );
}

// Quote card for testimonials
function Quote({ children, name, role, location, tint }) {
  return (
    <div style={{
      background: 'var(--vw-surface)',
      border: '1px solid var(--vw-border)',
      borderRadius: 14,
      padding: 28,
      display: 'flex', flexDirection: 'column', gap: 20,
      height: '100%',
    }}>
      <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 22, lineHeight: 1.35, letterSpacing: '-0.01em' }}>
        “{children}”
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 'auto' }}>
        <Avatar name={name} size={40} />
        <div>
          <div style={{ fontSize: 14, fontWeight: 600 }}>{name}</div>
          <div style={{ fontSize: 12, color: 'var(--vw-muted)' }}>{role} · {location}</div>
        </div>
      </div>
    </div>
  );
}

// "How it works" step
function Step({ num, title, children, icon, tint }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <Photo tint={tint} ratio="4/3" label={`${num.toString().padStart(2,'0')} · ${title}`} />
      <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
        <div style={{
          width: 28, height: 28, borderRadius: '50%',
          background: 'var(--vw-text)', color: 'var(--vw-inverse)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontFamily: 'var(--vw-mono)', fontSize: 12, fontWeight: 600,
          flexShrink: 0,
        }}>{num}</div>
        <div>
          <div style={{ fontSize: 18, fontWeight: 600, marginBottom: 6 }}>{title}</div>
          <div style={{ fontSize: 14, color: 'var(--vw-text-2)', lineHeight: 1.55 }}>{children}</div>
        </div>
      </div>
    </div>
  );
}

// Simple feature tile
function FeatureTile({ icon, title, children }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12, padding: 28, borderTop: '1px solid var(--vw-border)' }}>
      <Icon name={icon} size={22} color="var(--vw-text)" />
      <div style={{ fontSize: 17, fontWeight: 600, marginTop: 4 }}>{title}</div>
      <div style={{ fontSize: 14, color: 'var(--vw-text-2)', lineHeight: 1.6 }}>{children}</div>
    </div>
  );
}

Object.assign(window, { Photo, StatStrip, MktNav, MktFooter, Quote, Step, FeatureTile });
