// ═══════════════════════════════════════════════════════════════════════════
// Marketing — For Riders (honest voice, Apr 2026)
// No claimed insurance, no SOS team, no in-app chat. WhatsApp coordination.
// ═══════════════════════════════════════════════════════════════════════════

function MktRiders({ onNav }) {
  return (
    <div className="vw-root vw-web-scroll" data-theme="dark" style={{ width: '100%', height: '100%' }}>
      <MktNav active="riders" onNav={onNav} />

      {/* Hero */}
      <section style={{ padding: '112px 32px 80px', background: 'var(--vw-bg)' }}>
        <div style={{ maxWidth: 1100, margin: '0 auto' }}>
          <span className="vw-eyebrow">For riders</span>
          <h1 style={{
            fontFamily: 'var(--vw-serif)', marginTop: 24, fontSize: 76, letterSpacing: '-2.6px', lineHeight: 1.0, fontWeight: 400,
          }}>
            Ride home<br/>
            with <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>someone you'd recognize</em><br/>
            at the temple.
          </h1>
          <p className="vw-lead" style={{ marginTop: 28, maxWidth: 620, fontSize: 19 }}>
            Post where you're going. Someone in your community — your campus, your city — replies on WhatsApp. You ride
            together. That's it. No in-app chat, no surge pricing, no stranger at the curb.
          </p>
          <div style={{ display: 'flex', gap: 12, marginTop: 36 }}>
            <Btn variant="primary" size="xl" iconR="arrowR" onClick={() => onNav && onNav('download')}>Open the app</Btn>
            <Btn variant="ghost" size="xl" onClick={() => onNav && onNav('manifesto')}>Read the manifesto</Btn>
          </div>
        </div>
      </section>

      {/* Three honest steps — phone-screen placeholders */}
      <section style={{ padding: '0 32px 96px', background: 'var(--vw-bg)' }}>
        <div style={{ maxWidth: 1200, margin: '0 auto', display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 32 }}>
          {[
            { n: '01', title: 'Post the ride you need.', tint: 'morning',
              body: 'From, to, when. Add a note if you want — "flexible on time," "one bag only," whatever.' },
            { n: '02', title: 'Get a reply on WhatsApp.', tint: 'dusk',
              body: 'Usually within the hour in active cities. You see their name, photo, how long they\'ve been on Vaahana.' },
            { n: '03', title: 'Agree on the rest yourselves.', tint: 'plum',
              body: 'Pickup spot, timing, cost-sharing if any. Vaahana stays out of the conversation.' },
          ].map(s => (
            <div key={s.n}>
              <div style={{ aspectRatio: '9/16', borderRadius: 28, overflow: 'hidden', background: 'var(--vw-text)', padding: 10 }}>
                <Photo tint={s.tint} style={{ width: '100%', height: '100%', borderRadius: 20 }} label={`${s.n} · ${s.title.toLowerCase().replace(/[.,]/g,'').slice(0,24)}`}/>
              </div>
              <div style={{ marginTop: 24 }}>
                <div style={{ fontSize: 11, fontFamily: 'var(--vw-mono)', color: 'var(--vw-brand)', letterSpacing: '0.1em' }}>{s.n}</div>
                <div style={{ fontSize: 21, fontWeight: 500, fontFamily: 'var(--vw-serif)', letterSpacing: '-0.3px', marginTop: 8, lineHeight: 1.25 }}>{s.title}</div>
                <div style={{ fontSize: 14.5, color: 'var(--vw-text-2)', marginTop: 10, lineHeight: 1.6 }}>{s.body}</div>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* What a ride post looks like — editorial mock */}
      <section style={{ padding: '120px 32px', background: 'var(--vw-bg-alt)', borderTop: '1px solid var(--vw-divider)', borderBottom: '1px solid var(--vw-divider)' }}>
        <div style={{ maxWidth: 1100, margin: '0 auto', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 80, alignItems: 'center' }}>
          <div>
            <span className="vw-eyebrow">What you see</span>
            <h2 className="vw-h2" style={{ marginTop: 16, fontSize: 42, letterSpacing: '-1.2px' }}>
              Every ride shows a real person. Not a rating, not a car model — <em style={{ fontStyle: 'italic' }}>a person.</em>
            </h2>
            <p className="vw-lead" style={{ marginTop: 20, fontSize: 16 }}>
              Their name, photo, how long they've been on Vaahana, which campus they captain or belong to, and their WhatsApp
              link. You decide if you want to ride with them.
            </p>
            <ul style={{ listStyle: 'none', padding: 0, marginTop: 28, display: 'flex', flexDirection: 'column', gap: 14 }}>
              {[
                'Full name, photo, community affiliation',
                'Route, day, and approximate time',
                'WhatsApp button — the only "contact" button',
                'A note from them about the ride',
                'How many other riders have taken their rides',
              ].map((t, i) => (
                <li key={i} style={{ display: 'flex', gap: 12, fontSize: 14.5, alignItems: 'flex-start' }}>
                  <Icon name="check" size={18} color="var(--vw-brand)" strokeWidth={2.25} />
                  <span style={{ color: 'var(--vw-text-2)', lineHeight: 1.55 }}>{t}</span>
                </li>
              ))}
            </ul>
          </div>

          {/* Ride post card */}
          <Card padding={0}>
            <Photo tint="dusk" style={{ borderRadius: 0, height: 180 }} label="Edison NJ → Newark Airport (EWR)" />
            <div style={{ padding: 28 }}>
              <div style={{ display:'flex', alignItems:'center', gap: 14 }}>
                <Avatar name="Rohan Sharma" size={56} />
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 18, fontWeight: 600 }}>Rohan Sharma</div>
                  <div style={{ fontSize: 12.5, color: 'var(--vw-muted)', marginTop: 3, fontFamily: 'var(--vw-mono)' }}>
                    MIT · on Vaahana since Jan 2025
                  </div>
                </div>
              </div>

              <Divider style={{ margin: '22px 0' }} />

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20, fontSize: 13 }}>
                <div>
                  <div style={{ fontSize: 11, color: 'var(--vw-muted)', fontFamily: 'var(--vw-mono)', letterSpacing:'0.08em' }}>ROUTE</div>
                  <div style={{ fontWeight: 500, marginTop: 6, fontSize: 14 }}>Edison NJ → EWR</div>
                  <div style={{ color: 'var(--vw-muted)', marginTop: 3, fontSize: 12 }}>~28 min drive</div>
                </div>
                <div>
                  <div style={{ fontSize: 11, color: 'var(--vw-muted)', fontFamily: 'var(--vw-mono)', letterSpacing:'0.08em' }}>WHEN</div>
                  <div style={{ fontWeight: 500, marginTop: 6, fontSize: 14 }}>Sat · Apr 25</div>
                  <div style={{ color: 'var(--vw-muted)', marginTop: 3, fontSize: 12 }}>~5 PM, flexible</div>
                </div>
              </div>

              <div style={{ marginTop: 22, padding: 16, background: 'var(--vw-surface-2)', borderRadius: 10, fontSize: 14, color: 'var(--vw-text-2)', lineHeight: 1.55, fontStyle: 'italic', fontFamily: 'var(--vw-serif)' }}>
                "Flying home for my cousin's wedding. 2 seats open. Happy to split gas if you want."
              </div>

              <Divider style={{ margin: '22px 0' }} />

              <Btn variant="primary" size="lg" style={{ width: '100%', justifyContent: 'center' }} iconR="arrowR">
                Reach out on WhatsApp
              </Btn>
            </div>
          </Card>
        </div>
      </section>

      {/* Rider reality — what to expect */}
      <section style={{ padding: '120px 32px', background: 'var(--vw-bg)' }}>
        <div style={{ maxWidth: 1000, margin: '0 auto' }}>
          <span className="vw-eyebrow">Being a rider</span>
          <h2 className="vw-h2" style={{ marginTop: 16, fontSize: 44, letterSpacing: '-1.2px', maxWidth: 720 }}>
            A few things to know before you post.
          </h2>
          <div style={{ marginTop: 56, display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 0, border: '1px solid var(--vw-divider)', borderRadius: 14, overflow: 'hidden' }}>
            {[
              ['Not instant.', 'Most ride posts get a reply the same day. Some sit a day or two, especially in smaller cities. Post early.'],
              ['Cost-sharing is optional.', 'Some drivers ask for gas money. Some don\'t. It\'s up to the two of you — Vaahana doesn\'t set prices.'],
              ['You don\'t have to accept.', 'If the first reply doesn\'t feel right, you don\'t ride. No obligation. No penalty.'],
              ['Captains can help.', 'Every active city has a captain — a real person who knows the drivers. Their WhatsApp is on the city page.'],
            ].map(([t, b], i) => (
              <div key={i} style={{
                padding: 32,
                borderRight: i % 2 === 0 ? '1px solid var(--vw-divider)' : 'none',
                borderBottom: i < 2 ? '1px solid var(--vw-divider)' : 'none',
              }}>
                <div style={{ fontFamily: 'var(--vw-serif)', fontSize: 24, fontWeight: 500, letterSpacing: '-0.3px', lineHeight: 1.2 }}>{t}</div>
                <div style={{ fontSize: 14.5, color: 'var(--vw-text-2)', lineHeight: 1.6, marginTop: 12 }}>{b}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Rider FAQ */}
      <section style={{ padding: '120px 32px', background: 'var(--vw-bg-alt)', borderTop: '1px solid var(--vw-divider)', borderBottom: '1px solid var(--vw-divider)' }}>
        <div style={{ maxWidth: 860, margin: '0 auto' }}>
          <div style={{ marginBottom: 48 }}>
            <span className="vw-eyebrow">Questions we get a lot</span>
            <h2 className="vw-h2" style={{ marginTop: 16, fontSize: 40, letterSpacing: '-1.1px' }}>Before you post a ride.</h2>
          </div>
          <div style={{ borderTop: '1px solid var(--vw-divider)' }}>
            {[
              ['How do I know the driver is safe?',
               'You don\'t, in the absolute sense. You know their name, photo, community, and how long they\'ve been on Vaahana. You can message them on WhatsApp before riding. You can also ask the city captain — they usually know the driver personally. If that level of assurance isn\'t enough for a given ride, don\'t take it. We\'d rather you be honest with yourself than pretend an algorithm did it for you.'],
              ['Do I have to pay for a ride?',
               'Vaahana doesn\'t charge you — the app is free. Drivers and riders can agree to share gas money or not. That\'s off-platform, between the two of you. Many rides are free, especially among friends or campus-mates.'],
              ['What if the driver cancels last minute?',
               'It happens. Post the ride again. The captain can often help find someone else last-minute through the campus WhatsApp group.'],
              ['Can I use Vaahana if I\'m not South Asian?',
               'Yes. It\'s open to anyone. The diaspora focus is about where Vaahana started and where the communities are strongest — not about who can use it.'],
              ['What cities are active?',
               'Six right now: Rutgers/Edison, MIT/Cambridge, Northeastern, UT Austin, Stanford, and UT Dallas. See the Cities page for numbers.'],
              ['Is there an in-app chat?',
               'No. You talk on WhatsApp. Fewer apps, fewer places for a conversation to disappear.'],
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
            Open the app. <em style={{ fontStyle: 'italic', color: 'var(--vw-brand)' }}>Post the ride.</em>
          </h2>
          <p className="vw-lead" style={{ marginTop: 20 }}>That's the whole thing.</p>
          <div style={{ marginTop: 32, display: 'flex', gap: 12, justifyContent: 'center' }}>
            <Btn variant="primary" size="xl" iconR="arrowR" onClick={() => onNav && onNav('download')}>Open the app</Btn>
            <Btn variant="ghost" size="xl" onClick={() => onNav && onNav('drivers')}>Drive instead</Btn>
          </div>
        </div>
      </section>

      <MktFooter onNav={onNav} />
    </div>
  );
}

Object.assign(window, { MktRiders });
