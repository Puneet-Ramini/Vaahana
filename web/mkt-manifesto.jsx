// ═══════════════════════════════════════════════════════════════════════════
// Marketing — Manifesto
// A single-column editorial essay. The page that makes us look like a brand.
// ═══════════════════════════════════════════════════════════════════════════

function MktManifesto({ onNav }) {
  return (
    <div className="vw-root vw-web-scroll" data-theme="dark" style={{ width: '100%', height: '100%' }}>
      <MktNav active="manifesto" onNav={onNav} />

      <article style={{ padding: '120px 32px 80px', background: 'var(--vw-bg)' }}>
        <div style={{ maxWidth: 720, margin: '0 auto' }}>
          <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 12, color: 'var(--vw-muted)', letterSpacing: '0.1em', textTransform: 'uppercase' }}>
            Manifesto · April 2026
          </div>
          <h1 style={{
            fontFamily: 'var(--vw-serif)', fontSize: 68, lineHeight: 1.02, letterSpacing: '-2px',
            fontWeight: 400, marginTop: 20,
          }}>
            We were the ones<br />always asking<br />
            <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>for rides.</em>
          </h1>

          <div style={{
            marginTop: 64, fontFamily: 'var(--vw-serif)', fontSize: 21, lineHeight: 1.65,
            color: 'var(--vw-text-2)', fontWeight: 400,
            display: 'flex', flexDirection: 'column', gap: 28,
          }}>
            <p style={{
              fontSize: 26, lineHeight: 1.5, color: 'var(--vw-text)', letterSpacing: '-0.2px', margin: 0,
            }}>
              For us, <em>"Can you drop me?"</em> is a phrase with history.
            </p>
            <p style={{ margin: 0 }}>
              It's how we got to weddings we couldn't miss. To airports at 4 AM. To the grocery store in a new country,
              when the bus didn't come on Sundays. It's how our parents built communities without cars, and how we
              learned to repay favors without counting.
            </p>
            <p style={{ margin: 0 }}>
              That economy still runs. It runs in WhatsApp groups with 200 people in them. It runs in the parent chat
              before Diwali, the freshman chat before move-in week, the temple chat before every festival. When someone
              needs a ride, somebody always offers. And somebody always says <em>"next time, you drive."</em>
            </p>
            <p style={{ margin: 0 }}>
              Vaahana is what happens when that culture meets software.
            </p>
            <p style={{
              fontFamily: 'var(--vw-serif)', fontSize: 28, lineHeight: 1.35, margin: '20px 0',
              color: 'var(--vw-text)', letterSpacing: '-0.3px', fontStyle: 'italic',
              borderLeft: '3px solid var(--vw-brand)', paddingLeft: 28,
            }}>
              Not another rideshare. Not an algorithm matching strangers. A way to turn the drop-me economy we already
              live in into something everyone can find.
            </p>
            <p style={{ margin: 0 }}>
              We didn't come from transportation. We came from the WhatsApp groups. The way we built this is the way we
              always coordinated rides — you ask, someone answers, you talk, you go together. The app is the lightest
              possible wrapper around a thing that already works.
            </p>
            <p style={{ margin: 0 }}>
              We're deliberately not Uber. We don't price. We don't take a cut. We don't assign strangers to each other.
              We don't expand to a city until someone there volunteers to captain it. When we say <em>"live in 6 cities,"</em>
              we mean six. Not 42. Not "soon."
            </p>
            <p style={{ margin: 0 }}>
              There are real things we don't do yet. Full identity verification. 24/7 dispatch. Insurance.
              We'll add them when they're real. We won't claim them until then. That restraint is the whole point — the
              thing that separates a community from a product.
            </p>
            <p style={{ margin: 0 }}>
              We think about our moms every time we make a decision here. Would they trust this? Would they understand
              what it does on the first try? Would they ask the person on the other end where they're from, and would
              they get a real answer? If no, we don't ship it.
            </p>
            <p style={{ margin: 0 }}>
              You don't need another rideshare. You already have four of them. What you might need — what we needed,
              what drove us to build this — is a way to find your people going the same way.
            </p>
            <p style={{
              fontSize: 26, lineHeight: 1.45, color: 'var(--vw-text)', letterSpacing: '-0.2px', margin: '20px 0 0',
              fontFamily: 'var(--vw-serif)',
            }}>
              That's what this is. That's all it is. And if we do it right, that's all it ever needs to be.
            </p>
          </div>

          {/* Signature */}
          <div style={{ marginTop: 80, paddingTop: 40, borderTop: '1px solid var(--vw-divider)', display: 'flex', gap: 20, alignItems: 'center' }}>
            <Avatar name="The Founders" size={56} />
            <div>
              <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 20, fontStyle: 'italic' }}>— the founders</div>
              <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 12, color: 'var(--vw-muted)', marginTop: 4, letterSpacing: '0.04em' }}>
                hello@vaahana.com · April 2026
              </div>
            </div>
          </div>

          {/* Next reads */}
          <div style={{ marginTop: 80, display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 16 }}>
            <div onClick={() => onNav && onNav('stories')} style={{
              padding: 28, background: 'var(--vw-surface)', border: '1px solid var(--vw-divider)',
              borderRadius: 14, cursor: 'pointer',
            }}>
              <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 11, color: 'var(--vw-muted)', letterSpacing: '0.1em', textTransform: 'uppercase' }}>Next read</div>
              <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 20, marginTop: 10, fontWeight: 500, letterSpacing: '-0.3px' }}>
                Real rides, real words →
              </div>
              <div style={{ fontSize: 14, color: 'var(--vw-muted)', marginTop: 8 }}>Twelve stories from the riders and drivers using Vaahana today.</div>
            </div>
            <div onClick={() => onNav && onNav('safety')} style={{
              padding: 28, background: 'var(--vw-surface)', border: '1px solid var(--vw-divider)',
              borderRadius: 14, cursor: 'pointer',
            }}>
              <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 11, color: 'var(--vw-muted)', letterSpacing: '0.1em', textTransform: 'uppercase' }}>Next read</div>
              <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 20, marginTop: 10, fontWeight: 500, letterSpacing: '-0.3px' }}>
                Safety, honestly →
              </div>
              <div style={{ fontSize: 14, color: 'var(--vw-muted)', marginTop: 8 }}>What we do, and — more importantly — what we don't.</div>
            </div>
          </div>
        </div>
      </article>

      <MktFooter onNav={onNav} />
    </div>
  );
}

Object.assign(window, { MktManifesto });
