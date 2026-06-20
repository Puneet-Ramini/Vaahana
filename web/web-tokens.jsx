// ═══════════════════════════════════════════════════════════════════════════
// Vaahana Web — Tokens (light + dark)
// ═══════════════════════════════════════════════════════════════════════════
// Extends the mobile app's black/white/accent language into a full web system.
// Marketing uses the warm-light palette; admin lets users flip light↔dark.

// Dark-first, matches mobile vaahana.css exactly. iOS systemBlue as the primary
// accent. Light theme is a faithful inverse (same blue, adjusted neutrals) so
// admin can flip day/night without the brand feeling different.
const WebTokens = {
  // Dark — primary / default everywhere. Marketing, admin, driver portal.
  dark: {
    bg:        '#0a0a0a',
    bgAlt:     '#0f0f0f',
    surface:   '#121212',
    surface2:  '#1a1a1a',
    surface3:  '#222222',
    border:    '#262626',
    border2:   '#333333',
    divider:   '#1f1f1f',

    text:      '#f2f2f2',
    text2:     '#c7c7c7',
    muted:     '#8a8a8a',
    subtle:    '#5c5c5c',
    inverse:   '#0a0a0a',

    // Brand — muted indigo. Trustworthy, specific to our voice,
    // not the saffron-cliche and not corporate-tech blue.
    brand:     '#8a9ed6',
    brandHov:  '#a7b8e3',
    brandBg:   'rgba(138,158,214,0.16)',
    onBrand:   '#0a0a0a',

    // Accent on light surfaces — same indigo, darker for contrast
    ink:       '#2f3a5f',
    cream:     '#f4ecd8',
    terracotta:'#c65d3f',

    // Status — SF dark-mode tuned
    blue:      '#0a84ff',  blueBg:   'rgba(10,132,255,0.14)',
    green:     '#30d158',  greenBg:  'rgba(48,209,88,0.14)',
    red:       '#ff453a',  redBg:    'rgba(255,69,58,0.14)',
    amber:     '#ff9f0a',  amberBg:  'rgba(255,159,10,0.14)',
    yellow:    '#ffd60a',  yellowBg: 'rgba(255,214,10,0.14)',
    violet:    '#bf5af2',  violetBg: 'rgba(191,90,242,0.14)',
  },
  // Light — faithful inverse. Same blue. Only used when a user explicitly flips.
  light: {
    // Cream-first warm light. Anchors the diaspora voice.
    bg:        '#f4ecd8',
    bgAlt:     '#ece3c8',
    surface:   '#faf4e2',
    surface2:  '#ece3c8',
    surface3:  '#ddd2b3',
    border:    '#ddd2b3',
    border2:   '#c5b992',
    divider:   '#e5d9bb',

    text:      '#1a1a1a',
    text2:     '#3a3a3a',
    muted:     '#6b6657',
    subtle:    '#9a9382',
    inverse:   '#f4ecd8',

    brand:     '#2f3a5f',
    brandHov:  '#1f2a4c',
    brandBg:   'rgba(47,58,95,0.09)',
    onBrand:   '#ffffff',

    ink:       '#2f3a5f',
    cream:     '#f4ecd8',
    terracotta:'#c65d3f',

    blue:      '#007aff',  blueBg:   'rgba(0,122,255,0.10)',
    green:     '#34c759',  greenBg:  'rgba(52,199,89,0.12)',
    red:       '#ff3b30',  redBg:    'rgba(255,59,48,0.10)',
    amber:     '#ff9500',  amberBg:  'rgba(255,149,0,0.12)',
    yellow:    '#ffcc00',  yellowBg: 'rgba(255,204,0,0.14)',
    violet:    '#af52de',  violetBg: 'rgba(175,82,222,0.10)',
  },
};

// CSS injection — per-theme scoped via data-theme on the frame
const WebTokensCSS = `
  :root {
    /* Fraunces — the display serif. Soft, editorial, a little bit alive. */
    --vw-serif: "Fraunces", "Source Serif Pro", "Iowan Old Style", Georgia, serif;
    --vw-sans:  -apple-system, BlinkMacSystemFont, "Inter", "SF Pro Text", "Helvetica Neue", sans-serif;
    --vw-mono:  "JetBrains Mono", "SF Mono", Menlo, ui-monospace, monospace;

    /* Type scale — web-specific, bigger than mobile */
    --t-display: 72px;   --t-display-lh: 1.02;   --t-display-ls: -2.4px;
    --t-h1: 52px;        --t-h1-lh: 1.05;        --t-h1-ls: -1.6px;
    --t-h2: 38px;        --t-h2-lh: 1.1;         --t-h2-ls: -1px;
    --t-h3: 26px;        --t-h3-lh: 1.2;         --t-h3-ls: -0.6px;
    --t-h4: 20px;        --t-h4-lh: 1.3;         --t-h4-ls: -0.3px;
    --t-lead: 19px;      --t-lead-lh: 1.5;
    --t-body: 16px;      --t-body-lh: 1.55;
    --t-small: 14px;     --t-small-lh: 1.5;
    --t-xs: 12px;        --t-xs-lh: 1.5;
    --t-micro: 11px;     --t-micro-lh: 1.4;

    /* Radius */
    --r-sm: 6px;
    --r-md: 10px;
    --r-lg: 14px;
    --r-xl: 20px;
    --r-2xl: 28px;

    /* Spacing — 4px base */
    --s-1: 4px;  --s-2: 8px;  --s-3: 12px;  --s-4: 16px;
    --s-5: 20px; --s-6: 24px; --s-7: 32px;  --s-8: 40px;
    --s-9: 56px; --s-10: 72px; --s-11: 96px; --s-12: 128px;
  }

  /* Apply tokens from a data-theme attr */
  [data-theme="light"] {
    --vw-bg: ${WebTokens.light.bg};
    --vw-bg-alt: ${WebTokens.light.bgAlt};
    --vw-surface: ${WebTokens.light.surface};
    --vw-surface-2: ${WebTokens.light.surface2};
    --vw-surface-3: ${WebTokens.light.surface3};
    --vw-border: ${WebTokens.light.border};
    --vw-border-2: ${WebTokens.light.border2};
    --vw-divider: ${WebTokens.light.divider};
    --vw-text: ${WebTokens.light.text};
    --vw-text-2: ${WebTokens.light.text2};
    --vw-muted: ${WebTokens.light.muted};
    --vw-subtle: ${WebTokens.light.subtle};
    --vw-inverse: ${WebTokens.light.inverse};
    --vw-brand: ${WebTokens.light.brand};
    --vw-brand-hov: ${WebTokens.light.brandHov};
    --vw-on-brand: ${WebTokens.light.onBrand};
    --vw-blue: ${WebTokens.light.blue};
    --vw-blue-bg: ${WebTokens.light.blueBg};
    --vw-green: ${WebTokens.light.green};
    --vw-green-bg: ${WebTokens.light.greenBg};
    --vw-red: ${WebTokens.light.red};
    --vw-red-bg: ${WebTokens.light.redBg};
    --vw-amber: ${WebTokens.light.amber};
    --vw-amber-bg: ${WebTokens.light.amberBg};
    --vw-violet: ${WebTokens.light.violet};
    --vw-violet-bg: ${WebTokens.light.violetBg};
    --vw-brand-bg: ${WebTokens.light.brandBg};
    --vw-yellow: ${WebTokens.light.yellow};
    --vw-yellow-bg: ${WebTokens.light.yellowBg};
  }
  [data-theme="dark"] {
    --vw-bg: ${WebTokens.dark.bg};
    --vw-bg-alt: ${WebTokens.dark.bgAlt};
    --vw-surface: ${WebTokens.dark.surface};
    --vw-surface-2: ${WebTokens.dark.surface2};
    --vw-surface-3: ${WebTokens.dark.surface3};
    --vw-border: ${WebTokens.dark.border};
    --vw-border-2: ${WebTokens.dark.border2};
    --vw-divider: ${WebTokens.dark.divider};
    --vw-text: ${WebTokens.dark.text};
    --vw-text-2: ${WebTokens.dark.text2};
    --vw-muted: ${WebTokens.dark.muted};
    --vw-subtle: ${WebTokens.dark.subtle};
    --vw-inverse: ${WebTokens.dark.inverse};
    --vw-brand: ${WebTokens.dark.brand};
    --vw-brand-hov: ${WebTokens.dark.brandHov};
    --vw-on-brand: ${WebTokens.dark.onBrand};
    --vw-blue: ${WebTokens.dark.blue};
    --vw-blue-bg: ${WebTokens.dark.blueBg};
    --vw-green: ${WebTokens.dark.green};
    --vw-green-bg: ${WebTokens.dark.greenBg};
    --vw-red: ${WebTokens.dark.red};
    --vw-red-bg: ${WebTokens.dark.redBg};
    --vw-amber: ${WebTokens.dark.amber};
    --vw-amber-bg: ${WebTokens.dark.amberBg};
    --vw-violet: ${WebTokens.dark.violet};
    --vw-violet-bg: ${WebTokens.dark.violetBg};
    --vw-brand-bg: ${WebTokens.dark.brandBg};
    --vw-yellow: ${WebTokens.dark.yellow};
    --vw-yellow-bg: ${WebTokens.dark.yellowBg};
  }

  .vw-root { font-family: var(--vw-sans); color: var(--vw-text); background: var(--vw-bg); }
  .vw-root * { box-sizing: border-box; }

  /* Type utilities */
  .vw-display { font-family: var(--vw-serif); font-weight: 400; font-size: var(--t-display); line-height: var(--t-display-lh); letter-spacing: var(--t-display-ls); }
  .vw-h1 { font-family: var(--vw-serif); font-weight: 400; font-size: var(--t-h1); line-height: var(--t-h1-lh); letter-spacing: var(--t-h1-ls); }
  .vw-h2 { font-family: var(--vw-serif); font-weight: 400; font-size: var(--t-h2); line-height: var(--t-h2-lh); letter-spacing: var(--t-h2-ls); }
  .vw-h3 { font-weight: 600; font-size: var(--t-h3); line-height: var(--t-h3-lh); letter-spacing: var(--t-h3-ls); }
  .vw-h4 { font-weight: 600; font-size: var(--t-h4); line-height: var(--t-h4-lh); letter-spacing: var(--t-h4-ls); }
  .vw-lead { font-size: var(--t-lead); line-height: var(--t-lead-lh); color: var(--vw-text-2); }
  .vw-body { font-size: var(--t-body); line-height: var(--t-body-lh); }
  .vw-small { font-size: var(--t-small); line-height: var(--t-small-lh); }
  .vw-xs { font-size: var(--t-xs); line-height: var(--t-xs-lh); }
  .vw-micro { font-size: var(--t-micro); line-height: var(--t-micro-lh); }
  .vw-mono { font-family: var(--vw-mono); font-feature-settings: "tnum","ss01"; }
  .vw-eyebrow { font-size: 11px; font-weight: 600; letter-spacing: 0.12em; text-transform: uppercase; color: var(--vw-muted); font-family: var(--vw-mono); }
  .vw-num { font-family: var(--vw-mono); font-feature-settings: "tnum"; }

  .vw-muted { color: var(--vw-muted); }
  .vw-text-2 { color: var(--vw-text-2); }
  .vw-subtle { color: var(--vw-subtle); }

  /* Use Google Fonts — the serif is what gives the marketing its editorial feel */
  @import url("https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,300;0,9..144,400;0,9..144,500;0,9..144,600;1,9..144,400;1,9..144,500&family=JetBrains+Mono:wght@400;500;600&family=Inter:wght@400;500;600;700&display=swap");
`;

// Inject immediately
(function injectWebTokensCSS(){
  if (document.getElementById('vw-tokens-css')) return;
  const style = document.createElement('style');
  style.id = 'vw-tokens-css';
  style.textContent = WebTokensCSS;
  document.head.appendChild(style);
})();

window.WebTokens = WebTokens;
window.WebTokensCSS = WebTokensCSS;
