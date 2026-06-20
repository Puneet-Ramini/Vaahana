// ═══════════════════════════════════════════════════════════════════════════
// Marketing — For Drivers (honest voice, Apr 2026)
// No "92% take-home," no "$1M insurance," no "38,200 drivers." Just the truth:
// you drive where you're already going, someone rides with you, you agree on
// cost-sharing off-platform. Vaahana takes nothing.
// ═══════════════════════════════════════════════════════════════════════════

function MktDrivers({ onNav }) {
  return (
    <div className="vw-root vw-web-scroll" data-theme="dark" style={{ width: '100%', height: '100%' }}>
      <MktNav active="drivers" onNav={onNav} />

      {/* Hero */}
      <section style={{ padding: '112px 32px 80px', background: 'var(--vw-bg)' }}>
        <div style={{ maxWidth: 1200, margin: '0 auto', display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: 80, alignItems: 'center' }}>
          <div>
            <span className="vw-eyebrow" style={{ display:'inline-flex', alignItems:'center', gap: 8 }}>
              <span style={{ width:6,height:6,borderRadius:'50%',background:'var(--vw-green)' }}/>
              Open to drivers in all 6 active cities
            </span>
            <h1 style={{
              fontFamily: 'var(--vw-serif)', marginTop: 24, fontSize: 72, letterSpacing: '-2.4px', lineHeight: 1.0, fontWeight: 400,
            }}>
              You're driving there<br/>
              <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>anyway.</em><br/>
              Take someone with you.
            </h1>
            <p className="vw-lead" style={{ marginTop: 28, maxWidth: 540, fontSize: 19 }}>
              Post the routes you already drive — weekend trips home, Sunday temple runs, airport drops. Someone in your
              community reaches out. You agree on the rest yourselves. Vaahana takes <em style={{ fontStyle: 'italic', color: 'var(--vw-text)', fontWeight: 500 }}>zero</em> — no platform fee, no cut.
            </p>
            <div style={{ display: 'flex', gap: 12, marginTop: 36 }}>
              <Btn variant="primary" size="xl" iconR="arrowR">Start driving</Btn>
              <Btn variant="ghost" size="xl" onClick={() => onNav && onNav('manifesto')}>Read the manifesto</Btn>
            </div>
          </div>

          {/* Driver profile card — the thing that lives on your ride posts */}
          <Card padding={0} style={{ overflow: 'hidden' }}>
            <Photo tint="plum" style={{ borderRadius: 0, height: 180 }} label="Your ride posts · as others see them" />
            <div style={{ padding: 28 }}>
              <div style={{ display:'flex', alignItems:'center', gap: 14 }}>
                <Avatar name="Vikram Patel" size={56} />
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 18, fontWeight: 600 }}>Vikram Patel</div>
                  <div style={{ fontSize: 12.5, color: 'var(--vw-muted)', marginTop: 3, fontFamily: 'var(--vw-mono)' }}>
                    MIT → Edison corridor · driving since Feb 2025
                  </div>
                </div>
              </div>

              <Divider style={{ margin: '22px 0' }} />

              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16, fontFamily: 'var(--vw-mono)', fontSize: 12, color: 'var(--vw-muted)' }}>
                <div>
                  <div style={{ letterSpacing: '0.08em' }}>RIDES GIVEN</div>
                  <div style={{ color: 'var(--vw-text)', fontSize: 20, marginTop: 6, fontWeight: 500 }}>34</div>
                </div>
                <div>
                  <div style={{ letterSpacing: '0.08em' }}>SINCE</div>
                  <div style={{ color: 'var(--vw-text)', fontSize: 20, marginTop: 6, fontWeight: 500 }}>2025</div>
                </div>
                <div>
                  <div style={{ letterSpacing: '0.08em' }}>CAMPUS</div>
                  <div style={{ color: 'var(--vw-text)', fontSize: 20, marginTop: 6, fontWeight: 500 }}>MIT</div>
                </div>
              </div>

              <div style={{ marginTop: 22, padding: 16, background: 'var(--vw-surface-2)', borderRadius: 10, fontSize: 13.5, color: 'var(--vw-text-2)', lineHeight: 1.55, fontStyle: 'italic', fontFamily: 'var(--vw-serif)' }}>
                "Going home to Jersey every other weekend. Can usually take 2. Happy to drop at EWR on the way."
              </div>
            </div>
          </Card>
        </div>
      </section>

      {/* Three-step reality */}
      <section style={{ padding: '120px 32px', background: 'var(--vw-bg-alt)', borderTop: '1px solid var(--vw-divider)', borderBottom: '1px solid var(--vw-divider)' }}>
        <div style={{ maxWidth: 1200, margin: '0 auto' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.5fr', gap: 72, marginBottom: 56 }}>
            <div>
              <span className="vw-eyebrow">How driving works</span>
              <h2 className="vw-h2" style={{ marginTop: 16, fontSize: 42, letterSpacing: '-1.2px' }}>
                Three honest steps.
              </h2>
            </div>
            <p className="vw-lead" style={{ alignSelf: 'end', fontSize: 16, maxWidth: 520 }}>
              We don't dispatch you. We don't assign. You decide who to drive, when, for how much — or for free.
            </p>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 32 }}>
            {[
              { n: '01', t: 'Post your route.', b: 'Where you\'re going, when, how many seats. Free text for the rest — "can swing by Metuchen," "one bag only," whatever.' },
              { n: '02', t: 'Riders reach out on WhatsApp.', b: 'You see their name and campus. You pick who rides. You can say no, no reason needed.' },
              { n: '03', t: 'Agree on cost-sharing yourselves.', b: 'Gas money. A coffee. Nothing. It\'s between you. Vaahana isn\'t in the loop, doesn\'t take a cut.' },
            ].map(s => (
              <div key={s.n}>
                <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 12, color: 'var(--vw-brand)', letterSpacing: '0.1em' }}>{s.n}</div>
                <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 24, fontWeight: 500, letterSpacing: '-0.3px', marginTop: 10, lineHeight: 1.2 }}>{s.t}</div>
                <div style={{ fontSize: 14.5, color: 'var(--vw-text-2)', marginTop: 14, lineHeight: 1.6 }}>{s.b}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Money, honestly */}
      <section style={{ padding: '120px 32px', background: 'var(--vw-bg)' }}>
        <div style={{ maxWidth: 900, margin: '0 auto' }}>
          <div style={{ marginBottom: 48 }}>
            <span className="vw-eyebrow">Money, honestly</span>
            <h2 className="vw-h2" style={{ marginTop: 16, fontSize: 44, letterSpacing: '-1.3px', maxWidth: 720 }}>
              What Vaahana takes: <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>nothing.</em><br/>
              What you take: up to you.
            </h2>
          </div>
          <div style={{ border: '1px solid var(--vw-divider)', borderRadius: 16, overflow: 'hidden' }}>
            {[
              ['Vaahana\'s cut of your ride', '$0', 'The app is free to post. We don\'t process payments. We don\'t see what you agreed to.'],
              ['Typical cost-share for an airport run', '$0–$25', 'Based on what riders tell us. Many rides are free — especially within campus or family networks.'],
              ['What we do charge for', 'Nothing', 'We\'re running on friends-and-family funding. No ads either. Eventually: maybe a membership. Not today.'],
              ['Are you an employee of Vaahana?', 'No', 'You\'re not a gig worker. You\'re a community member offering a ride. We issue no 1099s. No commercial insurance. Personal auto policy applies.'],
            ].map(([label, v, note], i, arr) => (
              <div key={label} style={{
                padding: '28px 32px',
                borderBottom: i < arr.length - 1 ? '1px solid var(--vw-divider)' : 'none',
                display: 'grid', gridTemplateColumns: '1fr 140px 1fr', gap: 28, alignItems: 'start',
              }}>
                <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 19, fontWeight: 500, letterSpacing: '-0.2px', lineHeight: 1.3 }}>{label}</div>
                <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 22, fontWeight: 500, color: 'var(--vw-text)' }}>{v}</div>
                <div style={{ fontSize: 13.5, color: 'var(--vw-text-2)', lineHeight: 1.55 }}>{note}</div>
              </div>
            ))}
          </div>
          <div style={{ marginTop: 24, padding: 20, background: 'var(--vw-surface-2)', borderRadius: 12, display: 'flex', gap: 14 }}>
            <Icon name="info" size={18} color="var(--vw-muted)" style={{ marginTop: 2, flexShrink: 0 }} />
            <div style={{ fontSize: 13.5, color: 'var(--vw-text-2)', lineHeight: 1.6 }}>
              Things we don't do: tax withholding, commercial auto insurance, liability coverage. You're driving the same way
              you drove your cousin to the airport last year — that's the legal and financial framing.
            </div>
          </div>
        </div>
      </section>

      {/* What we ask of drivers — the honest bar */}
      <section style={{ padding: '120px 32px', background: 'var(--vw-bg-alt)', borderTop: '1px solid var(--vw-divider)', borderBottom: '1px solid var(--vw-divider)' }}>
        <div style={{ maxWidth: 1200, margin: '0 auto' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.5fr', gap: 72, alignItems: 'start' }}>
            <div>
              <span className="vw-eyebrow">What we ask</span>
              <h2 className="vw-h2" style={{ marginTop: 16, fontSize: 40, letterSpacing: '-1.1px' }}>
                The bar is community, not corporate.
              </h2>
              <p className="vw-lead" style={{ marginTop: 20, fontSize: 15.5 }}>
                We're not background-checking or fingerprinting you. We're asking a captain to know your name.
              </p>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
              {[
                { t: 'A valid driver\'s license.', b: 'That\'s it for paperwork. We don\'t run a DMV pull.' },
                { t: 'An insured vehicle.', b: 'Your personal auto policy. We don\'t inspect it; we trust you.' },
                { t: 'Someone to vouch for you.', b: 'A city captain, or two existing Vaahana users from your campus. They confirm you\'re you.' },
                { t: 'A real profile.', b: 'Your name (not a handle), a photo of your face, your campus or community. Your WhatsApp for riders to reach you.' },
                { t: 'The willingness to say no.', b: 'If a rider doesn\'t feel right, don\'t take them. We\'d rather a ride not happen than happen poorly.' },
              ].map((r, i, arr) => (
                <div key={r.t} style={{
                  padding: '24px 0',
                  borderTop: '1px solid var(--vw-divider)',
                  borderBottom: i === arr.length - 1 ? '1px solid var(--vw-divider)' : 'none',
                  display: 'grid', gridTemplateColumns: '40px 1fr', gap: 20, alignItems: 'start',
                }}>
                  <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 12, color: 'var(--vw-muted)', letterSpacing: '0.08em', paddingTop: 4 }}>
                    {String(i+1).padStart(2,'0')}
                  </div>
                  <div>
                    <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 22, fontWeight: 500, letterSpacing: '-0.3px', lineHeight: 1.25 }}>{r.t}</div>
                    <div style={{ fontSize: 14.5, color: 'var(--vw-text-2)', marginTop: 8, lineHeight: 1.6 }}>{r.b}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* Driver quotes */}
      <section style={{ padding: '120px 32px', background: 'var(--vw-bg)' }}>
        <div style={{ maxWidth: 1200, margin: '0 auto' }}>
          <div style={{ maxWidth: 720, marginBottom: 56 }}>
            <span className="vw-eyebrow">Drivers, in their own words</span>
            <h2 className="vw-h2" style={{ marginTop: 16, fontSize: 42, letterSpacing: '-1.2px' }}>Why they drive on Vaahana.</h2>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 28 }}>
            {[
              { q: "I drive home to Jersey every other weekend. Now I bring two students with me. They chip in for gas. That's it. It's easy.",
                n: 'Vikram P.', r: 'MIT → Edison NJ', tint: 'forest' },
              { q: "My parents always drove other kids to school. I'm just the next version of that — with an app that helps me find them.",
                n: 'Sunita I.', r: 'Rutgers · temple routes', tint: 'dusk' },
              { q: "I wasn't sure at first. Then my cousin vouched for me. The first rider was a junior from back home. It felt right.",
                n: 'Arjun D.', r: 'UT Austin → UT Dallas', tint: 'plum' },
            ].map(s => (
              <div key={s.n} style={{
                background: 'var(--vw-surface)',
                border: '1px solid var(--vw-divider)',
                borderRadius: 16, padding: 32,
                display: 'flex', flexDirection: 'column', gap: 24, minHeight: 340,
              }}>
                <div style={{
                  fontFamily: 'var(--vw-serif)', fontSize: 20, lineHeight: 1.45,
                  fontStyle: 'italic', letterSpacing: '-0.2px',
                }}>"{s.q}"</div>
                <div style={{ marginTop: 'auto', display: 'flex', alignItems: 'center', gap: 12 }}>
                  <Avatar name={s.n} size={40} />
                  <div>
                    <div style={{ fontSize: 14, fontWeight: 600 }}>{s.n}</div>
                    <div style={{ fontFamily: 'var(--vw-mono)', fontSize: 11, color: 'var(--vw-muted)', marginTop: 2 }}>{s.r}</div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Driver FAQ */}
      <section style={{ padding: '120px 32px', background: 'var(--vw-bg-alt)', borderTop: '1px solid var(--vw-divider)' }}>
        <div style={{ maxWidth: 860, margin: '0 auto' }}>
          <div style={{ marginBottom: 48 }}>
            <span className="vw-eyebrow">Driver FAQ</span>
            <h2 className="vw-h2" style={{ marginTop: 16, fontSize: 40, letterSpacing: '-1.1px' }}>What drivers ask us most.</h2>
          </div>
          <div style={{ borderTop: '1px solid var(--vw-divider)' }}>
            {[
              ['Do I need commercial insurance?',
               'No. We don\'t require it. Your personal auto policy is what covers your car. We\'re honest about this: if you want the legal protection of commercial rideshare insurance, Vaahana isn\'t that — we\'re closer to a favor economy with an app on top.'],
              ['How much can I make?',
               'We don\'t want to answer this because it implies Vaahana is a gig job. It isn\'t. Most drivers break even on gas or come out a little ahead. Some drive for free. If you\'re looking for hourly income, Uber is a better fit.'],
              ['How do payouts work?',
               'There are no payouts. Cost-sharing is between you and the rider — Venmo, Zelle, cash. Whatever you agree on. Vaahana never touches the money.'],
              ['Can I decline a rider?',
               'Any reason, no reason. You see their profile before agreeing to anything.'],
              ['What cities can I drive in?',
               'All six active ones. If you\'re not in one of them, you can sign up anyway — we\'ll let you know when your city launches.'],
              ['What if something goes wrong on a ride?',
               'Call 911 if it\'s an emergency. For everything else, email founder@vaahana.com — we usually reply the same day. We don\'t have a 24/7 team. We\'re not pretending to.'],
            ].map(([q, a], i) => (
              <details key={i} style={{ borderBottom: '1px solid var(--vw-divider)', padding: '22px 0' }}>
                <summary style={{ cursor: 'pointer', listStyle: 'none', display: 'flex', justifyContent: 'space-between', fontSize: 17, fontWeight: 500, fontFamily: 'var(--vw-serif)', letterSpacing: '-0.2px', gap: 20 }}>
                  <span>{q}</span>
                  <Icon name="plus" size={18} color="var(--vw-muted)" style={{ flexShrink: 0, marginTop: 4 }} />
                </summary>
                <div style={{ marginTop: 14, fontSize: 15, color: 'var(--vw-text-2)', lineHeight: 1.65, maxWidth: 640 }}>{a}</div>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section style={{ padding: '120px 32px', background: 'var(--vw-bg)', textAlign: 'center' }}>
        <div style={{ maxWidth: 720, margin: '0 auto' }}>
          <h2 style={{ fontFamily: 'var(--vw-serif)', fontSize: 56, letterSpacing: '-1.6px', lineHeight: 1.05, fontWeight: 400 }}>
            You're driving there anyway.<br/>
            <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>Start a ride.</em>
          </h2>
          <div style={{ marginTop: 32, display: 'flex', gap: 12, justifyContent: 'center' }}>
            <Btn variant="primary" size="xl" iconR="arrowR">Start driving</Btn>
            <Btn variant="ghost" size="xl" onClick={() => onNav && onNav('cities')}>See active cities</Btn>
          </div>
          <div style={{ marginTop: 24, fontSize: 13, color: 'var(--vw-muted)' }}>
            Questions? <span style={{ color: 'var(--vw-brand)' }}>founder@vaahana.com</span>
          </div>
        </div>
      </section>

      <MktFooter onNav={onNav} />
    </div>
  );
}

Object.assign(window, { MktDrivers });
