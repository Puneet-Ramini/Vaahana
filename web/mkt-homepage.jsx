// ═══════════════════════════════════════════════════════════════════════════
// Marketing — Homepage
// Honest voice. Community transportation, not rideshare. First-person plural.
// ═══════════════════════════════════════════════════════════════════════════

// ──────────────────────────────────────────────────────────────────────────
// HERO — 3 presentations of the same content. All use the new honest voice.
// ──────────────────────────────────────────────────────────────────────────

function HomeHeroEditorial({ onNav }) {
  return (
    <section style={{ padding: '80px 32px 96px', position: 'relative' }}>
      <div style={{ maxWidth: 1200, margin: '0 auto', display: 'grid', gridTemplateColumns: '1.05fr 1fr', gap: 72, alignItems: 'center' }}>
        <div>
          <span className="vw-eyebrow" style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
            <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--vw-green)' }} />
            A community carpool · est. 2024
          </span>
          <h1 className="vw-display" style={{ marginTop: 28, fontSize: 82, lineHeight: 0.98, letterSpacing: '-3px' }}>
            Rides between<br />
            <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>neighbors.</em>
          </h1>
          <p className="vw-lead" style={{ marginTop: 28, maxWidth: 460, fontSize: 20, lineHeight: 1.55 }}>
            Every South Asian kid has begged their cousin for an airport drop. We've turned that favor economy
            into an app — built for diasporas far from home, open to anyone going the same way.
          </p>
          <div style={{ display: 'flex', gap: 12, marginTop: 36 }}>
            <Btn variant="primary" size="xl" iconR="arrowR" onClick={() => onNav && onNav('download')}>Open the app</Btn>
            <Btn variant="ghost" size="xl" iconL="play" onClick={() => onNav && onNav('how-it-works')}>Watch how it works</Btn>
          </div>
          <div style={{ marginTop: 48, fontSize: 13, color: 'var(--vw-muted)', lineHeight: 1.55, maxWidth: 420 }}>
            Currently active in <strong style={{ color: 'var(--vw-text)' }}>6 campus communities</strong> across NJ, MA, TX and CA. <br />
            <a onClick={() => onNav && onNav('cities')} style={{ color: 'var(--vw-brand)', cursor: 'pointer', textDecoration: 'underline', textUnderlineOffset: 3 }}>See where we are today →</a>
          </div>
        </div>

        {/* Editorial photo — single, confident, not a collage */}
        <div style={{ position: 'relative', height: 620 }}>
          <Photo tint="dusk" style={{
            position: 'absolute', inset: 0,
            borderRadius: 20,
          }} label="Route 1 · Edison → EWR · 6:12 PM"/>
          {/* Single subtle overlay quote — the editorial anchor */}
          <div style={{
            position: 'absolute', bottom: 24, left: 24, right: 24,
            background: 'rgba(10,10,10,0.55)', backdropFilter: 'blur(14px)',
            border: '1px solid rgba(255,255,255,0.1)',
            borderRadius: 14, padding: '20px 22px',
            color: '#fff',
          }}>
            <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 17, fontStyle: 'italic', lineHeight: 1.45, fontWeight: 400 }}>
              "It's the first ride app my mom lets me use."
            </div>
            <div style={{ marginTop: 10, fontFamily: 'var(--vw-mono)', fontSize: 11, letterSpacing: '0.04em', opacity: 0.75 }}>
              — Priya, sophomore · Rutgers
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function HomeHeroSplit({ onNav }) {
  return (
    <section style={{ padding: '80px 32px', background: 'var(--vw-bg)' }}>
      <div style={{ maxWidth: 1200, margin: '0 auto', display: 'grid', gridTemplateColumns: '1fr 420px', gap: 80, alignItems: 'center' }}>
        <div>
          <span className="vw-eyebrow">The community carpool</span>
          <h1 className="vw-display" style={{ marginTop: 20, fontSize: 72, lineHeight: 1, letterSpacing: '-2.6px' }}>
            The ride home<br />shouldn't be <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>lonely.</em>
          </h1>
          <p className="vw-lead" style={{ marginTop: 24, maxWidth: 480 }}>
            Post your route. Match with someone in your community who's going the same way. Coordinate on WhatsApp.
            That's the whole app.
          </p>
          <div style={{ display: 'flex', gap: 12, marginTop: 32 }}>
            <Btn variant="primary" size="xl" iconR="arrowR" onClick={() => onNav && onNav('download')}>Open the app</Btn>
            <Btn variant="secondary" size="xl" onClick={() => onNav && onNav('manifesto')}>Read our manifesto</Btn>
          </div>
        </div>
        <Photo tint="golden" ratio="3/4" style={{ borderRadius: 20 }} label="The app · home feed" />
      </div>
    </section>
  );
}

function HomeHeroCenter({ onNav }) {
  const cities = ['Rutgers · Edison', 'MIT · Cambridge', 'UT Austin', 'Stanford · Palo Alto', 'UT Dallas · Plano', 'Northeastern · Boston'];
  return (
    <section style={{ padding: '112px 32px 72px', background: 'var(--vw-bg)', textAlign: 'center' }}>
      <div style={{ maxWidth: 900, margin: '0 auto' }}>
        <span className="vw-eyebrow">A community carpool, not another rideshare</span>
        <h1 className="vw-display" style={{ marginTop: 22, fontSize: 92, lineHeight: 1, letterSpacing: '-3.2px' }}>
          Your people.<br />
          Your route.<br />
          <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>Your ride.</em>
        </h1>
        <p className="vw-lead" style={{ marginTop: 28, maxWidth: 560, margin: '28px auto 0', fontSize: 19 }}>
          We turned the drop-me economy we already live in into something everyone can find.
        </p>
        <div style={{ display: 'flex', gap: 12, marginTop: 36, justifyContent: 'center' }}>
          <Btn variant="primary" size="xl" iconR="arrowR" onClick={() => onNav && onNav('download')}>Open the app</Btn>
          <Btn variant="ghost" size="xl" onClick={() => onNav && onNav('cities')}>See active cities</Btn>
        </div>
      </div>
      {/* Ticker of real cities — scrolls slowly */}
      <div style={{
        marginTop: 80,
        borderTop: '1px solid var(--vw-divider)',
        borderBottom: '1px solid var(--vw-divider)',
        padding: '22px 0',
        display: 'flex', gap: 64, justifyContent: 'center',
        overflow: 'hidden', whiteSpace: 'nowrap',
        fontFamily: 'var(--vw-mono)', fontSize: 13, color: 'var(--vw-muted)',
        letterSpacing: '0.04em',
      }}>
        {cities.map(c => (
          <span key={c} style={{ display: 'inline-flex', alignItems: 'center', gap: 10 }}>
            <span style={{ width: 4, height: 4, borderRadius: '50%', background: 'var(--vw-brand)' }} />
            {c}
          </span>
        ))}
      </div>
    </section>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Section: "The reason we exist" — 2 sentences, first-person plural
// ──────────────────────────────────────────────────────────────────────────
function WhyWeExist({ onNav }) {
  return (
    <section style={{ padding: '120px 32px', background: 'var(--vw-bg)', borderTop: '1px solid var(--vw-divider)' }}>
      <div style={{ maxWidth: 920, margin: '0 auto', textAlign: 'left' }}>
        <span className="vw-eyebrow">Why we exist</span>
        <p style={{
          fontFamily: 'var(--vw-serif)', fontSize: 44, lineHeight: 1.2,
          letterSpacing: '-1.2px', marginTop: 20, fontWeight: 400,
        }}>
          We were the ones always asking for rides.{' '}
          <span style={{ color: 'var(--vw-muted)' }}>
            "Can you drop me?" is a phrase with history — it's how we got to weddings, to airports, to grocery runs in a new country.
            Vaahana is what happens when that culture meets software.
          </span>
        </p>
        <div style={{ marginTop: 32 }}>
          <a onClick={() => onNav && onNav('manifesto')} style={{ fontSize: 15, color: 'var(--vw-brand)', cursor: 'pointer', fontWeight: 500, borderBottom: '1px solid var(--vw-brand)', paddingBottom: 2 }}>
            Read the full manifesto →
          </a>
        </div>
      </div>
    </section>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Section: 3 honest steps
// ──────────────────────────────────────────────────────────────────────────
function HowItWorks({ onNav }) {
  const steps = [
    { n: '01', t: 'Post your ride.', b: 'From, to, when, and a note if you want. You decide what to share.', tint: 'morning' },
    { n: '02', t: 'Someone you know — or someone like you — reaches out.', b: 'On WhatsApp, where you already talk. No in-app chat. No hidden identities.', tint: 'dusk' },
    { n: '03', t: 'Go together.', b: 'Agree on the rest yourselves. Vaahana stays out of it.', tint: 'plum' },
  ];
  return (
    <section style={{ padding: '120px 32px', background: 'var(--vw-bg-alt)', borderTop: '1px solid var(--vw-divider)', borderBottom: '1px solid var(--vw-divider)' }}>
      <div style={{ maxWidth: 1200, margin: '0 auto' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 2fr', gap: 80, marginBottom: 72 }}>
          <div>
            <span className="vw-eyebrow">How it works</span>
            <h2 className="vw-h2" style={{ marginTop: 16, fontSize: 44, letterSpacing: '-1.2px' }}>
              Three steps. Then it's just two people, one car.
            </h2>
          </div>
          <div style={{ alignSelf: 'end' }}>
            <p className="vw-lead" style={{ fontSize: 17, maxWidth: 520 }}>
              We're intentionally small. What happens after the match is up to you — that's the whole point.
            </p>
          </div>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 32 }}>
          {steps.map(s => (
            <div key={s.n} style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
              <Photo tint={s.tint} ratio="4/3" label={`${s.n} · ${s.t.toLowerCase().replace(/[.\u2014]/g,'').slice(0,32)}`} style={{ borderRadius: 14 }} />
              <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 12, color: 'var(--vw-brand)', letterSpacing: '0.1em' }}>{s.n}</div>
              <div style={{ fontSize: 22, fontWeight: 500, fontFamily: 'var(--vw-serif)', letterSpacing: '-0.3px', lineHeight: 1.25 }}>{s.t}</div>
              <div style={{ fontSize: 15, color: 'var(--vw-text-2)', lineHeight: 1.6 }}>{s.b}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Section: Why not just Uber? — honest comparison
// ──────────────────────────────────────────────────────────────────────────
function WhyNotUber() {
  const rows = [
    { t: 'Who\'s driving', us: 'Someone from your community. Verified email, linked WhatsApp, visible profile.', them: 'A stranger matched by algorithm.' },
    { t: 'How you talk', us: 'WhatsApp. A platform you already trust, with a history you can see.', them: 'In-app chat that disappears after the ride.' },
    { t: 'What it costs', us: 'Vaahana doesn\'t price. Drivers and riders agree on cost-sharing themselves, off-platform.', them: 'Dynamic pricing, surge multipliers, service fees.' },
    { t: 'Who makes money', us: 'Nobody — yet. We take no cut. The app is free.', them: 'Platform takes 25–40% per ride.' },
  ];
  return (
    <section style={{ padding: '120px 32px', background: 'var(--vw-bg)' }}>
      <div style={{ maxWidth: 1100, margin: '0 auto' }}>
        <div style={{ textAlign: 'center', marginBottom: 64 }}>
          <span className="vw-eyebrow">The honest comparison</span>
          <h2 className="vw-h2" style={{ marginTop: 16, fontSize: 44, letterSpacing: '-1.2px' }}>
            Why not just use Uber?
          </h2>
          <p className="vw-lead" style={{ marginTop: 20, maxWidth: 600, margin: '20px auto 0' }}>
            We're not trying to replace it. We're a different thing altogether — for when the other thing doesn't fit.
          </p>
        </div>
        <div style={{ border: '1px solid var(--vw-divider)', borderRadius: 16, overflow: 'hidden' }}>
          <div style={{
            display: 'grid', gridTemplateColumns: '200px 1fr 1fr',
            background: 'var(--vw-surface-2)',
            padding: '18px 28px',
            fontFamily: 'var(--vw-mono)', fontSize: 11, letterSpacing: '0.1em', textTransform: 'uppercase',
            color: 'var(--vw-muted)',
            borderBottom: '1px solid var(--vw-divider)',
          }}>
            <div></div>
            <div style={{ color: 'var(--vw-brand)' }}>Vaahana</div>
            <div>The big app</div>
          </div>
          {rows.map((r, i) => (
            <div key={r.t} style={{
              display: 'grid', gridTemplateColumns: '200px 1fr 1fr',
              padding: '24px 28px', gap: 24,
              borderBottom: i < rows.length - 1 ? '1px solid var(--vw-divider)' : 'none',
              alignItems: 'start',
            }}>
              <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 17, fontWeight: 500, paddingTop: 2 }}>{r.t}</div>
              <div style={{ fontSize: 14.5, lineHeight: 1.55, color: 'var(--vw-text)' }}>{r.us}</div>
              <div style={{ fontSize: 14.5, lineHeight: 1.55, color: 'var(--vw-muted)' }}>{r.them}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Section: Real rides, real words — 3 stories
// ──────────────────────────────────────────────────────────────────────────
function RealStories({ onNav }) {
  const stories = [
    {
      q: "I got to my sister's wedding in Boston because three people I'd never met drove me in shifts. I'd have flown home crying otherwise.",
      n: 'Aisha K.', loc: 'Rutgers → Boston', tint: 'dawn',
    },
    {
      q: "My dad stopped worrying about me going to the airport alone. He knows who's driving now — someone's cousin, not a stranger.",
      n: 'Rohan S.', loc: 'UT Dallas', tint: 'plum',
    },
    {
      q: "I drive home to Jersey every other weekend. Now I bring two students with me. They chip in for gas. That's it. It's easy.",
      n: 'Vikram P.', loc: 'MIT → Edison NJ', tint: 'forest',
    },
  ];
  return (
    <section style={{ padding: '120px 32px', background: 'var(--vw-bg-alt)', borderTop: '1px solid var(--vw-divider)', borderBottom: '1px solid var(--vw-divider)' }}>
      <div style={{ maxWidth: 1200, margin: '0 auto' }}>
        <div style={{ marginBottom: 64, maxWidth: 760 }}>
          <span className="vw-eyebrow">Real rides, real words</span>
          <h2 className="vw-h2" style={{ marginTop: 16, fontSize: 44, letterSpacing: '-1.2px' }}>
            These are the people using Vaahana today.
          </h2>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 28 }}>
          {stories.map(s => (
            <div key={s.n} style={{
              background: 'var(--vw-surface)',
              border: '1px solid var(--vw-divider)',
              borderRadius: 16, padding: 32,
              display: 'flex', flexDirection: 'column', gap: 24,
              minHeight: 360,
            }}>
              <div style={{
                fontFamily: 'var(--vw-serif)', fontSize: 21, lineHeight: 1.4,
                fontStyle: 'italic', fontWeight: 400,
                letterSpacing: '-0.2px',
              }}>"{s.q}"</div>
              <div style={{ marginTop: 'auto', display: 'flex', alignItems: 'center', gap: 12 }}>
                <Avatar name={s.n} size={40} />
                <div>
                  <div style={{ fontSize: 14, fontWeight: 600 }}>{s.n}</div>
                  <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 11, color: 'var(--vw-muted)', marginTop: 2 }}>{s.loc}</div>
                </div>
              </div>
            </div>
          ))}
        </div>
        <div style={{ marginTop: 48, textAlign: 'center' }}>
          <Btn variant="ghost" size="lg" iconR="arrowR" onClick={() => onNav && onNav('stories')}>Read more stories</Btn>
        </div>
      </div>
    </section>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Section: What we don't do (yet) — the credibility move
// ──────────────────────────────────────────────────────────────────────────
function WhatWeDont() {
  const items = [
    "We don't do background checks. Drivers are community members, not employees.",
    "We don't take a cut. There's nothing to cut.",
    "We don't operate in 42 cities. We're in 6. We'll say when we're in more.",
    "We don't surge price. We don't price at all.",
    "We don't use in-app chat. You talk on WhatsApp, where you already live.",
  ];
  return (
    <section style={{ padding: '120px 32px', background: 'var(--vw-bg)' }}>
      <div style={{ maxWidth: 980, margin: '0 auto' }}>
        <span className="vw-eyebrow">In plain english</span>
        <h2 className="vw-h2" style={{ marginTop: 16, fontSize: 48, letterSpacing: '-1.4px', maxWidth: 720 }}>
          Some things we're proud <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>not</em> to do yet.
        </h2>
        <ul style={{ listStyle: 'none', padding: 0, marginTop: 56, display: 'flex', flexDirection: 'column', gap: 0 }}>
          {items.map((it, i) => (
            <li key={i} style={{
              padding: '28px 0',
              borderTop: '1px solid var(--vw-divider)',
              borderBottom: i === items.length - 1 ? '1px solid var(--vw-divider)' : 'none',
              display: 'grid', gridTemplateColumns: '60px 1fr', gap: 24, alignItems: 'center',
            }}>
              <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 12, color: 'var(--vw-muted)' }}>{String(i+1).padStart(2,'0')}</div>
              <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 24, lineHeight: 1.35, fontWeight: 400, letterSpacing: '-0.3px' }}>
                {it}
              </div>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Section: Places we're at — honest 6 campuses
// ──────────────────────────────────────────────────────────────────────────
function PlacesWereAt({ onNav }) {
  const places = [
    { city: 'Rutgers · Edison NJ',    riders: 412, captain: 'Priya M.' },
    { city: 'MIT · Cambridge MA',     riders: 287, captain: 'Rohan S.' },
    { city: 'Northeastern · Boston',  riders: 203, captain: 'Aisha K.' },
    { city: 'UT Austin',              riders: 178, captain: 'Arjun D.' },
    { city: 'Stanford · Palo Alto',   riders: 156, captain: 'Meera V.' },
    { city: 'UT Dallas · Plano TX',   riders: 134, captain: 'Karan R.' },
  ];
  return (
    <section style={{ padding: '120px 32px', background: 'var(--vw-bg-alt)', borderTop: '1px solid var(--vw-divider)', borderBottom: '1px solid var(--vw-divider)' }}>
      <div style={{ maxWidth: 1200, margin: '0 auto' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.4fr', gap: 80, alignItems: 'end', marginBottom: 56 }}>
          <div>
            <span className="vw-eyebrow">Where we are</span>
            <h2 className="vw-h2" style={{ marginTop: 16, fontSize: 42, letterSpacing: '-1.2px' }}>
              Six places, and growing slowly on purpose.
            </h2>
          </div>
          <p className="vw-lead" style={{ fontSize: 16, maxWidth: 520 }}>
            We grow campus-by-campus. Each one has a captain — a real person who knows the drivers and answers
            their WhatsApp messages. That doesn't scale, which is why it works.
          </p>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 2, background: 'var(--vw-divider)' }}>
          {places.map(p => (
            <div key={p.city} style={{ background: 'var(--vw-bg-alt)', padding: 28, cursor: 'pointer' }}
              onClick={() => onNav && onNav('cities')}>
              <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 22, fontWeight: 500, letterSpacing: '-0.3px' }}>{p.city}</div>
              <div style={{ display: 'flex', gap: 24, marginTop: 14, fontFamily: 'var(--vw-mono)', fontSize: 12, color: 'var(--vw-muted)' }}>
                <span><span style={{ color: 'var(--vw-text)' }}>{p.riders}</span> active riders</span>
                <span>Captain: <span style={{ color: 'var(--vw-text)' }}>{p.captain}</span></span>
              </div>
            </div>
          ))}
        </div>
        <div style={{ marginTop: 48, display: 'flex', gap: 12 }}>
          <Btn variant="primary" size="lg" iconR="arrowR" onClick={() => onNav && onNav('request-city')}>Bring Vaahana to your city</Btn>
          <Btn variant="ghost" size="lg" onClick={() => onNav && onNav('cities')}>See all six in detail</Btn>
        </div>
      </div>
    </section>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Section: Join — single clean CTA
// ──────────────────────────────────────────────────────────────────────────
function JoinCTA({ onNav }) {
  return (
    <section style={{ padding: '140px 32px', background: 'var(--vw-bg)', textAlign: 'center' }}>
      <div style={{ maxWidth: 720, margin: '0 auto' }}>
        <h2 style={{
          fontFamily: 'var(--vw-serif)', fontSize: 68, lineHeight: 1, letterSpacing: '-2px',
          fontWeight: 400,
        }}>
          Open the app,<br />
          or <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>get an invite</em><br />
          to your city's launch.
        </h2>
        <div style={{ display: 'flex', gap: 12, marginTop: 40, justifyContent: 'center' }}>
          <Btn variant="primary" size="xl" iconR="arrowR" onClick={() => onNav && onNav('download')}>Open the app</Btn>
          <Btn variant="secondary" size="xl" onClick={() => onNav && onNav('request-city')}>Request your city</Btn>
        </div>
        <div style={{ marginTop: 28, fontSize: 13, color: 'var(--vw-muted)' }}>
          Questions? <span style={{ color: 'var(--vw-brand)', cursor: 'pointer' }}>hello@vaahana.com</span> — usually same day.
        </div>
      </div>
    </section>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Compose
// ──────────────────────────────────────────────────────────────────────────
function MktHomepage({ onNav, heroVariant = 'editorial' }) {
  const Hero = heroVariant === 'split'  ? HomeHeroSplit :
               heroVariant === 'center' ? HomeHeroCenter :
                                          HomeHeroEditorial;
  return (
    <div className="vw-root vw-web-scroll" data-theme="dark" style={{ width: '100%', height: '100%' }}>
      <MktNav active="home" onNav={onNav} />
      <Hero onNav={onNav} />
      <WhyWeExist onNav={onNav} />
      <HowItWorks onNav={onNav} />
      <WhyNotUber />
      <RealStories onNav={onNav} />
      <WhatWeDont />
      <PlacesWereAt onNav={onNav} />
      <JoinCTA onNav={onNav} />
      <MktFooter onNav={onNav} />
    </div>
  );
}

Object.assign(window, {
  MktHomepage,
  HomeHeroEditorial, HomeHeroSplit, HomeHeroCenter,
  WhyWeExist, HowItWorks, WhyNotUber, RealStories, WhatWeDont, PlacesWereAt, JoinCTA,
});
