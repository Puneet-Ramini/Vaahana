// Stub files for pages not yet built — render a "Coming soon" placeholder
// that still uses the design system. Keeps Vaahana Web.html rendering cleanly.

function StubPage({ title, onNav, navKey }) {
  return (
    <div className="vw-root vw-web-scroll" data-theme="dark" style={{ width: '100%', height: '100%' }}>
      <MktNav active={navKey} onNav={onNav} />
      <section style={{ padding: '160px 32px', textAlign: 'center', minHeight: 'calc(100vh - 64px)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ maxWidth: 640 }}>
          <span className="vw-eyebrow">Next up</span>
          <h1 className="vw-h1" style={{ marginTop: 20, fontSize: 56, letterSpacing: '-2px' }}>{title}</h1>
          <p className="vw-lead" style={{ marginTop: 24 }}>
            This page is scaffolded and ready for content. The design system, shared nav, footer, primitives, and token layer
            are all wired — only the page composition remains.
          </p>
          <Btn variant="primary" size="lg" iconR="arrowR" style={{ marginTop: 32 }} onClick={() => onNav && onNav('home')}>
            Back to homepage
          </Btn>
        </div>
      </section>
      <MktFooter onNav={onNav} />
    </div>
  );
}

function MktPricing({ onNav })   { return <StubPage title="Pricing — community-capped, zone-based" onNav={onNav} navKey="pricing" />; }
function MktAbout({ onNav })     { return <StubPage title="About — our story" onNav={onNav} />; }
function MktCareers({ onNav })   { return <StubPage title="Careers — join Vaahana" onNav={onNav} />; }
function MktDownload({ onNav })  { return <StubPage title="Download the app" onNav={onNav} />; }
function AuthPage({ onNav })     { return <StubPage title="Sign in / Sign up" onNav={onNav} />; }
function DriverPortal({ onNav }) { return <StubPage title="Driver portal" onNav={onNav} />; }
function AdminShell({ onNav })   { return <StubPage title="Admin dashboard" onNav={onNav} />; }
function HelpCenter({ onNav })   { return <StubPage title="Help center" onNav={onNav} />; }
function TrustSafety({ onNav })  { return <StubPage title="Trust & policies" onNav={onNav} />; }

Object.assign(window, {
  StubPage, MktPricing, MktAbout, MktCareers, MktDownload,
  AuthPage, DriverPortal, AdminShell, HelpCenter, TrustSafety,
});
