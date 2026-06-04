// ═══════════════════════════════════════════════════════════════════════════
// Vaahana Web — Icon library
// ═══════════════════════════════════════════════════════════════════════════
// Line-icons, 24×24 viewBox, stroke 1.5, currentColor.
// Usage: <Icon name="home" size={20} />

const ICON_PATHS = {
  // Nav
  home:        'M3 10.5L12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1v-9.5z',
  map:         'M9 3l6 3 5-2v15l-5 2-6-3-5 2V5l5-2zM9 3v15M15 6v15',
  car:         'M5 17h14M5 17v-5l2-5h10l2 5v5M5 17v2h2v-2M17 17v2h2v-2M7.5 13.5h1M15.5 13.5h1',
  user:        'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21c0-4 4-6 8-6s8 2 8 6',
  users:       'M9 12a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM17 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM2 21c0-3 3-5 7-5s7 2 7 5M16 16c3 0 6 1.5 6 4',
  receipt:     'M6 3h12v18l-3-2-3 2-3-2-3 2V3zM9 8h6M9 12h6M9 16h3',
  shield:      'M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3z',
  shieldCheck: 'M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3zM8.5 12l2.5 2.5L16 10',
  gauge:       'M12 13l4-4M3 13a9 9 0 0 1 18 0M6 13a6 6 0 0 1 12 0',
  dollar:      'M12 3v18M16 7H9a2.5 2.5 0 1 0 0 5h6a2.5 2.5 0 1 1 0 5H8',
  chart:       'M3 3v18h18M7 15l4-4 3 3 5-6',
  bell:        'M6 16V11a6 6 0 1 1 12 0v5l1.5 2.5h-15L6 16zM10 20a2 2 0 0 0 4 0',
  file:        'M7 3h7l4 4v14H7V3zM14 3v4h4',
  fileText:    'M7 3h7l4 4v14H7V3zM14 3v4h4M10 12h5M10 16h5M10 8h2',
  flag:        'M5 3v18M5 4c6-3 10 3 15 0v10c-5 3-9-3-15 0',
  settings:    'M12 9.5a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5zM19 12a7 7 0 0 0-.1-1l2-1.5-2-3.5-2.5 1a7 7 0 0 0-1.8-1L14 3h-4l-.6 3a7 7 0 0 0-1.8 1L5 6l-2 3.5L5 11a7 7 0 0 0 0 2l-2 1.5L5 18l2.5-1a7 7 0 0 0 1.8 1l.7 3h4l.6-3a7 7 0 0 0 1.8-1l2.5 1 2-3.5L19 13a7 7 0 0 0 .1-1z',
  layers:      'M12 3l9 5-9 5-9-5 9-5zM3 13l9 5 9-5M3 17l9 5 9-5',
  terminal:    'M4 4h16v16H4V4zM7 9l3 3-3 3M12 15h5',
  briefcase:   'M4 8h16v12H4V8zM8 8V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v3',
  broadcast:   'M12 10a2 2 0 1 1 0 4 2 2 0 0 1 0-4zM7 7a7 7 0 0 0 0 10M17 7a7 7 0 0 1 0 10M4 4a11 11 0 0 0 0 16M20 4a11 11 0 0 1 0 16',
  tag:         'M3 12V4h8l10 10-8 8L3 12zM8 8a1 1 0 1 0 0-2 1 1 0 0 0 0 2z',

  // Actions
  search:      'M10.5 3a7.5 7.5 0 1 1 0 15 7.5 7.5 0 0 1 0-15zM21 21l-5.5-5.5',
  filter:      'M3 5h18l-7 9v6l-4-2v-4L3 5z',
  download:    'M12 3v12M6 11l6 6 6-6M4 21h16',
  upload:      'M12 21V9M6 13l6-6 6 6M4 3h16',
  plus:        'M12 5v14M5 12h14',
  x:           'M6 6l12 12M6 18L18 6',
  check:       'M4 12l5 5L20 6',
  chevronD:    'M6 9l6 6 6-6',
  chevronR:    'M9 6l6 6-6 6',
  chevronL:    'M15 6l-6 6 6 6',
  arrowR:      'M5 12h14M13 5l7 7-7 7',
  arrowL:      'M19 12H5M11 5l-7 7 7 7',
  arrowUR:     'M7 17L17 7M7 7h10v10',
  external:    'M7 7h10v10M7 17L17 7',
  more:        'M5 12a1 1 0 1 0 2 0 1 1 0 0 0-2 0zM11 12a1 1 0 1 0 2 0 1 1 0 0 0-2 0zM17 12a1 1 0 1 0 2 0 1 1 0 0 0-2 0z',
  edit:        'M4 20h4l10-10-4-4L4 16v4zM14 6l4 4',
  copy:        'M8 8h10v12H8V8zM5 5h10v3M5 5v10h3',
  trash:       'M5 6h14M10 6V4h4v2M8 6l1 14h6l1-14',
  eye:         'M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7zM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
  eyeOff:      'M3 3l18 18M10.5 6.1A10.5 10.5 0 0 1 22 12s-1 2-3 4M6 6s-3 2.5-4 6c0 0 3.5 7 10 7 2 0 3.5-.5 5-1.3',
  link:        'M10 14a4 4 0 0 0 5.6 0l3-3a4 4 0 0 0-5.6-5.6l-1.5 1.5M14 10a4 4 0 0 0-5.6 0l-3 3a4 4 0 0 0 5.6 5.6l1.5-1.5',
  mail:        'M3 6h18v12H3V6zM3 7l9 6 9-6',
  phone:       'M4 4h4l2 5-3 2a12 12 0 0 0 6 6l2-3 5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 2 6a2 2 0 0 1 2-2z',
  sparkle:     'M12 3l1.5 4.5L18 9l-4.5 1.5L12 15l-1.5-4.5L6 9l4.5-1.5L12 3zM19 14l.5 1.5L21 16l-1.5.5L19 18l-.5-1.5L17 16l1.5-.5L19 14zM5 17l.4 1.2L6.5 18.5l-1.1.3L5 20l-.4-1.2L3.5 18.5l1.1-.3L5 17z',

  // Status
  alert:       'M12 3l10 18H2L12 3zM12 10v5M12 18v.5',
  info:        'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 11v5M12 8v.5',
  clock:       'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 7v5l3 2',
  pause:       'M8 5v14M16 5v14',
  play:        'M6 4l14 8-14 8V4z',
  lock:        'M6 11h12v10H6V11zM8 11V7a4 4 0 1 1 8 0v4',
  unlock:      'M6 11h12v10H6V11zM8 11V7a4 4 0 0 1 7-2',
  star:        'M12 3l2.6 5.8L21 9.5l-4.7 4.3L17.5 20 12 16.8 6.5 20l1.2-6.2L3 9.5l6.4-.7L12 3z',
  heart:       'M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.5-7 10-7 10z',
  bookmark:    'M6 3h12v18l-6-4-6 4V3z',
  calendar:    'M5 5h14v16H5V5zM5 10h14M9 3v4M15 3v4',
  pin:         'M12 3a7 7 0 0 0-7 7c0 5 7 11 7 11s7-6 7-11a7 7 0 0 0-7-7zM12 12a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z',
  image:       'M4 5h16v14H4V5zM4 16l4-4 5 5 3-3 4 4M8 10a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z',
  camera:      'M4 7h3l2-3h6l2 3h3v12H4V7zM12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8z',
  moon:        'M20 14A8 8 0 1 1 10 4a7 7 0 0 0 10 10z',
  sun:         'M12 6v-3M12 21v-3M6 12H3M21 12h-3M6 6l-2-2M20 20l-2-2M6 18l-2 2M20 4l-2 2M12 8a4 4 0 1 1 0 8 4 4 0 0 1 0-8z',
  globe:       'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM3 12h18M12 3c3 4 3 14 0 18M12 3c-3 4-3 14 0 18',
  qr:          'M4 4h6v6H4V4zM4 14h6v6H4v-6zM14 4h6v6h-6V4zM14 14h3v3h-3v-3zM19 14h1v1h-1v-1zM14 19h1v1h-1v-1zM16 17h4v3h-4',
  refresh:     'M3 12a9 9 0 0 1 15-6.7L21 8M21 4v4h-4M21 12a9 9 0 0 1-15 6.7L3 16M3 20v-4h4',
  logo:        'M3 20L12 4l9 16H3zM8 20l4-7 4 7',
};

function Icon({ name, size = 20, color = 'currentColor', strokeWidth = 1.5, style, className }) {
  const d = ICON_PATHS[name];
  if (!d) return <span style={{ width: size, height: size, ...style }} />;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
      stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round"
      className={className} style={{ display: 'inline-block', flexShrink: 0, verticalAlign: 'middle', ...style }}>
      <path d={d} />
    </svg>
  );
}

// Vaahana logo mark — a confident filled glyph. Two converging strokes
// form a "V" that reads as a road opening into the horizon (वाहन = vehicle).
// The inner stroke is lighter — rider + driver, two paths, one journey.
function Logo({ size = 28, color = 'currentColor', accent }) {
  const a = accent || color;
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" fill="none" style={{ display: 'inline-block', flexShrink: 0 }}>
      {/* Outer V — solid */}
      <path d="M3 6L16 28L29 6" stroke={color} strokeWidth="2.8" strokeLinecap="round" strokeLinejoin="round" fill="none"/>
      {/* Inner V — the second path */}
      <path d="M11 6L16 17L21 6" stroke={a} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" fill="none" opacity="0.55"/>
    </svg>
  );
}

// Wordmark — "vaahana" set tight in the sans, paired with the mark.
// Sans + lowercase + negative tracking reads modern and confident;
// the serif was drifting editorial/heritage and fighting the UI.
function Wordmark({ size = 22, color = 'currentColor', accent, showMark = true }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 9, color, lineHeight: 1 }}>
      {showMark && <Logo size={size} color={color} accent={accent} />}
      <span style={{
        fontFamily: 'var(--vw-sans)',
        fontSize: size * 0.82,
        fontWeight: 600,
        letterSpacing: '-0.035em',
        fontFeatureSettings: '"ss01", "cv11"',
      }}>
        vaahana
      </span>
    </span>
  );
}

Object.assign(window, { Icon, Logo, Wordmark, ICON_PATHS });
