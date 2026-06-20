// ═══════════════════════════════════════════════════════════════════════════
// Vaahana Web — Design canvas composition
// ═══════════════════════════════════════════════════════════════════════════
// Every page renders inside a browser-chrome window, arranged into sections
// on the design canvas. Navigation is just route state per-artboard.

function PageFrame({ route: initial = 'home', width = 1440, height = 900 }) {
  const [route, setRoute] = React.useState(initial);
  const urlFor = (r) => {
    const map = {
      home: 'vaahana.com', riders: 'vaahana.com/riders', drivers: 'vaahana.com/drivers',
      safety: 'vaahana.com/safety', cities: 'vaahana.com/cities', pricing: 'vaahana.com/pricing',
      community: 'vaahana.com/community', about: 'vaahana.com/about', careers: 'vaahana.com/careers',
      download: 'vaahana.com/download', login: 'vaahana.com/login', help: 'help.vaahana.com',
      trust: 'vaahana.com/trust', admin: 'admin.vaahana.com', driverPortal: 'drive.vaahana.com',
    };
    return map[r] || 'vaahana.com';
  };

  const render = () => {
    switch (route) {
      case 'home':       return <MktHomepage onNav={setRoute} heroVariant="editorial" />;
      case 'riders':     return <MktRiders onNav={setRoute} />;
      case 'drivers':    return <MktDrivers onNav={setRoute} />;
      case 'safety':     return <MktSafety onNav={setRoute} />;
      case 'cities':     return <MktCities onNav={setRoute} />;
      case 'manifesto':  return <MktManifesto onNav={setRoute} />;
      case 'pricing':    return <MktPricing onNav={setRoute} />;
      case 'community':  return <MktCommunity onNav={setRoute} />;
      case 'about':      return <MktAbout onNav={setRoute} />;
      case 'careers':    return <MktCareers onNav={setRoute} />;
      case 'download':   return <MktDownload onNav={setRoute} />;
      case 'login':      return <AuthPage onNav={setRoute} />;
      case 'help':       return <HelpCenter onNav={setRoute} />;
      case 'trust':      return <TrustSafety onNav={setRoute} />;
      case 'admin':      return <AdminShell onNav={setRoute} />;
      case 'driverPortal': return <DriverPortal onNav={setRoute} />;
      default: return <MktHomepage onNav={setRoute} />;
    }
  };

  return (
    <ChromeWindow
      tabs={[{ title: 'Vaahana', active: true }]}
      url={urlFor(route)}
      width={width} height={height}
    >
      {render()}
    </ChromeWindow>
  );
}

function StandaloneFrame({ page, title, width = 1440, height = 900, url }) {
  return (
    <ChromeWindow tabs={[{ title, active: true }]} url={url} width={width} height={height}>
      {page}
    </ChromeWindow>
  );
}

function WebApp() {
  return (
    <DesignCanvas>
      <DCSection id="overview" title="Vaahana Web" subtitle="Marketing site, auth, admin dashboard, help center — full system">
        <DCArtboard id="system-note" label="System notes" width={400} height={900}>
          <div style={{ padding: 36, fontFamily: 'var(--vw-sans)', background: 'var(--vw-bg)', color: 'var(--vw-text)', width: '100%', height: '100%' }} data-theme="dark" className="vw-root">
            <Wordmark size={28} />
            <div style={{ marginTop: 32, fontFamily: 'var(--vw-mono)', fontSize: 11, letterSpacing: '0.08em', color: 'var(--vw-muted)' }}>VAAHANA WEB · V1 · DESIGN BRIEF</div>
            <h2 className="vw-h3" style={{ marginTop: 16 }}>The full web surface.</h2>
            <p style={{ marginTop: 16, fontSize: 14, lineHeight: 1.6, color: 'var(--vw-text-2)' }}>
              Every page in the Vaahana product outside the mobile app: marketing, auth, admin, help center, driver portal.
              Built on a shared token layer (light + dark), a line-icon library, and ~20 shared primitives.
            </p>
            <div style={{ marginTop: 32, padding: 20, background: 'var(--vw-surface-2)', borderRadius: 12, fontSize: 13, lineHeight: 1.6 }}>
              <div style={{ fontWeight: 600, marginBottom: 8 }}>Delivered in v1</div>
              <ul style={{ paddingLeft: 18, margin: 0, color: 'var(--vw-text-2)' }}>
                <li>Full homepage (long-scroll composition)</li>
                <li>Homepage hero — 3 variations</li>
                <li>For riders page</li>
                <li>For drivers page</li>
                <li>Safety &amp; trust page</li>
                <li>Token system (light/dark)</li>
                <li>Icon library, primitives</li>
              </ul>
              <div style={{ fontWeight: 600, margin: '16px 0 8px' }}>Scaffolded (stub pages)</div>
              <ul style={{ paddingLeft: 18, margin: 0, color: 'var(--vw-muted)' }}>
                <li>Cities, Pricing, Community, About</li>
                <li>Careers, Download, Help, Trust</li>
                <li>Auth, Driver portal, Admin (11 sub-screens)</li>
              </ul>
            </div>
            <div style={{ marginTop: 24, fontSize: 12, color: 'var(--vw-muted)', lineHeight: 1.55 }}>
              All placeholder pages route correctly and use the production shell. Filling them in is page-composition
              work — the design system decisions are locked.
            </div>
          </div>
        </DCArtboard>

        <DCArtboard id="homepage" label="Homepage · editorial hero" width={1440} height={900}>
          <StandaloneFrame title="Vaahana" url="vaahana.com" page={<MktHomepage heroVariant="editorial" />} />
        </DCArtboard>

        <DCArtboard id="homepage-split" label="Homepage · split hero (alt)" width={1440} height={900}>
          <StandaloneFrame title="Vaahana" url="vaahana.com" page={<MktHomepage heroVariant="split" />} />
        </DCArtboard>

        <DCArtboard id="homepage-center" label="Homepage · centered hero (alt)" width={1440} height={900}>
          <StandaloneFrame title="Vaahana" url="vaahana.com" page={<MktHomepage heroVariant="center" />} />
        </DCArtboard>
      </DCSection>

      <DCSection id="marketing" title="Marketing pages" subtitle="Product + trust pages">
        <DCArtboard id="riders" label="For riders" width={1440} height={900}>
          <StandaloneFrame title="For riders" url="vaahana.com/riders" page={<MktRiders />} />
        </DCArtboard>
        <DCArtboard id="drivers" label="For drivers" width={1440} height={900}>
          <StandaloneFrame title="For drivers" url="vaahana.com/drivers" page={<MktDrivers />} />
        </DCArtboard>
        <DCArtboard id="safety" label="Safety & trust" width={1440} height={900}>
          <StandaloneFrame title="Safety" url="vaahana.com/safety" page={<MktSafety />} />
        </DCArtboard>
      </DCSection>

      <DCSection id="stubs" title="Scaffolded pages" subtitle="Token layer + nav + footer wired. Content pass pending.">
        <DCArtboard id="cities" label="Cities" width={1440} height={700}>
          <StandaloneFrame title="Cities" url="vaahana.com/cities" page={<MktCities />} />
        </DCArtboard>
        <DCArtboard id="pricing" label="Pricing" width={1440} height={700}>
          <StandaloneFrame title="Pricing" url="vaahana.com/pricing" page={<MktPricing />} />
        </DCArtboard>
        <DCArtboard id="community" label="Community" width={1440} height={700}>
          <StandaloneFrame title="Community" url="vaahana.com/community" page={<MktCommunity />} />
        </DCArtboard>
        <DCArtboard id="about" label="About" width={1440} height={700}>
          <StandaloneFrame title="About" url="vaahana.com/about" page={<MktAbout />} />
        </DCArtboard>
        <DCArtboard id="download" label="Download" width={1440} height={700}>
          <StandaloneFrame title="Download" url="vaahana.com/download" page={<MktDownload />} />
        </DCArtboard>
        <DCArtboard id="login" label="Auth (stub)" width={1440} height={700}>
          <StandaloneFrame title="Sign in" url="vaahana.com/login" page={<AuthPage />} />
        </DCArtboard>
        <DCArtboard id="admin" label="Admin (stub)" width={1440} height={700}>
          <StandaloneFrame title="Admin" url="admin.vaahana.com" page={<AdminShell />} />
        </DCArtboard>
        <DCArtboard id="help" label="Help center (stub)" width={1440} height={700}>
          <StandaloneFrame title="Help" url="help.vaahana.com" page={<HelpCenter />} />
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<WebApp />);
