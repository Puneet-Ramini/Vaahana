// ═══════════════════════════════════════════════════════════════════════════
// Vaahana Web — Primitives
// ═══════════════════════════════════════════════════════════════════════════
// Token-driven atoms. Theme-agnostic — they read CSS vars so a [data-theme]
// ancestor flips them.

// ──────────────────────────────────────────────────────────────────────────
// Button
// ──────────────────────────────────────────────────────────────────────────
const vwButtonStyles = {
  base: {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    fontFamily: 'var(--vw-sans)',
    fontWeight: 500,
    fontSize: 14,
    letterSpacing: '-0.01em',
    border: '1px solid transparent',
    borderRadius: 8,
    cursor: 'pointer',
    transition: 'all .15s ease',
    whiteSpace: 'nowrap',
    textDecoration: 'none',
    userSelect: 'none',
  },
  sizes: {
    xs: { height: 26, padding: '0 10px', fontSize: 12, borderRadius: 6, gap: 6 },
    sm: { height: 32, padding: '0 12px', fontSize: 13, borderRadius: 8 },
    md: { height: 38, padding: '0 16px', fontSize: 14 },
    lg: { height: 46, padding: '0 22px', fontSize: 15, borderRadius: 10 },
    xl: { height: 56, padding: '0 28px', fontSize: 16, borderRadius: 12, fontWeight: 600 },
  },
  variants: {
    primary: {
      background: 'var(--vw-brand)',
      color: 'var(--vw-on-brand)',
      borderColor: 'var(--vw-brand)',
    },
    secondary: {
      background: 'var(--vw-surface)',
      color: 'var(--vw-text)',
      borderColor: 'var(--vw-border-2)',
    },
    ghost: {
      background: 'transparent',
      color: 'var(--vw-text-2)',
      borderColor: 'transparent',
    },
    soft: {
      background: 'var(--vw-surface-2)',
      color: 'var(--vw-text)',
      borderColor: 'transparent',
    },
    danger: {
      background: 'var(--vw-red)',
      color: '#fff',
      borderColor: 'var(--vw-red)',
    },
    link: {
      background: 'transparent',
      color: 'var(--vw-text)',
      borderColor: 'transparent',
      padding: 0,
      height: 'auto',
      textDecoration: 'underline',
      textUnderlineOffset: 4,
      textDecorationColor: 'var(--vw-border-2)',
    },
  },
};

function Btn({ variant = 'primary', size = 'md', iconL, iconR, children, style, onClick, href, ...p }) {
  const s = { ...vwButtonStyles.base, ...vwButtonStyles.sizes[size], ...vwButtonStyles.variants[variant], ...style };
  const content = (
    <>
      {iconL && <Icon name={iconL} size={size === 'xs' ? 13 : size === 'xl' ? 18 : 15} />}
      {children}
      {iconR && <Icon name={iconR} size={size === 'xs' ? 13 : size === 'xl' ? 18 : 15} />}
    </>
  );
  if (href) return <a href={href} style={s} onClick={onClick} {...p}>{content}</a>;
  return <button style={s} onClick={onClick} {...p}>{content}</button>;
}

// ──────────────────────────────────────────────────────────────────────────
// Badge / Chip / Pill
// ──────────────────────────────────────────────────────────────────────────
function Badge({ tone = 'default', dot, soft = true, children, style }) {
  const tones = {
    default: { bg: 'var(--vw-surface-2)', fg: 'var(--vw-text-2)', dot: 'var(--vw-muted)' },
    neutral: { bg: 'var(--vw-surface-3)', fg: 'var(--vw-text)', dot: 'var(--vw-text)' },
    green:   { bg: 'var(--vw-green-bg)', fg: 'var(--vw-green)', dot: 'var(--vw-green)' },
    blue:    { bg: 'var(--vw-blue-bg)',  fg: 'var(--vw-blue)',  dot: 'var(--vw-blue)' },
    red:     { bg: 'var(--vw-red-bg)',   fg: 'var(--vw-red)',   dot: 'var(--vw-red)' },
    amber:   { bg: 'var(--vw-amber-bg)', fg: 'var(--vw-amber)', dot: 'var(--vw-amber)' },
    violet:  { bg: 'var(--vw-violet-bg)',fg: 'var(--vw-violet)',dot: 'var(--vw-violet)' },
    dark:    { bg: 'var(--vw-text)', fg: 'var(--vw-inverse)', dot: 'var(--vw-inverse)' },
  };
  const t = tones[tone] || tones.default;
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      height: 22, padding: '0 9px',
      background: soft ? t.bg : t.fg,
      color: soft ? t.fg : t.bg,
      borderRadius: 999,
      fontSize: 11,
      fontWeight: 500,
      fontFamily: 'var(--vw-sans)',
      letterSpacing: '-0.005em',
      whiteSpace: 'nowrap',
      ...style,
    }}>
      {dot && <span style={{ width: 6, height: 6, borderRadius: '50%', background: t.dot, flexShrink: 0 }} />}
      {children}
    </span>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Card
// ──────────────────────────────────────────────────────────────────────────
function Card({ children, style, padding = 24, hover = false, muted = false }) {
  return (
    <div style={{
      background: muted ? 'var(--vw-surface-2)' : 'var(--vw-surface)',
      border: '1px solid var(--vw-border)',
      borderRadius: 14,
      padding,
      transition: 'border-color .15s',
      ...(hover && { cursor: 'pointer' }),
      ...style,
    }}>
      {children}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Input / Field
// ──────────────────────────────────────────────────────────────────────────
function Input({ iconL, iconR, size = 'md', placeholder, type = 'text', value, onChange, suffix, style, ...p }) {
  const heights = { sm: 32, md: 40, lg: 48 };
  return (
    <label style={{
      display: 'inline-flex', alignItems: 'center', gap: 10,
      height: heights[size],
      padding: '0 12px',
      background: 'var(--vw-surface)',
      border: '1px solid var(--vw-border-2)',
      borderRadius: 8,
      color: 'var(--vw-text)',
      width: '100%',
      transition: 'border-color .15s',
      ...style,
    }}>
      {iconL && <Icon name={iconL} size={16} color="var(--vw-muted)" />}
      <input
        type={type}
        placeholder={placeholder}
        defaultValue={value}
        onChange={onChange}
        style={{
          flex: 1, border: 'none', outline: 'none', background: 'transparent',
          color: 'inherit', fontSize: size === 'sm' ? 13 : 14, fontFamily: 'inherit',
          minWidth: 0,
        }}
        {...p}
      />
      {suffix && <span style={{ fontSize: 12, color: 'var(--vw-muted)' }}>{suffix}</span>}
      {iconR && <Icon name={iconR} size={16} color="var(--vw-muted)" />}
    </label>
  );
}

function Field({ label, hint, error, children, style }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6, ...style }}>
      {label && <label style={{ fontSize: 13, fontWeight: 500, color: 'var(--vw-text-2)' }}>{label}</label>}
      {children}
      {(hint || error) && (
        <span style={{ fontSize: 12, color: error ? 'var(--vw-red)' : 'var(--vw-muted)' }}>
          {error || hint}
        </span>
      )}
    </div>
  );
}

// Toggle / switch
function Toggle({ on, onChange, size = 'md' }) {
  const sz = size === 'sm' ? { w: 30, h: 18, dot: 14 } : { w: 38, h: 22, dot: 18 };
  return (
    <button onClick={() => onChange && onChange(!on)} style={{
      width: sz.w, height: sz.h, borderRadius: 999, padding: 2,
      background: on ? 'var(--vw-brand)' : 'var(--vw-border-2)',
      border: 'none', cursor: 'pointer', position: 'relative',
      transition: 'background .15s',
    }}>
      <div style={{
        width: sz.dot, height: sz.dot, borderRadius: '50%', background: '#fff',
        transform: `translateX(${on ? sz.w - sz.dot - 4 : 0}px)`,
        transition: 'transform .18s cubic-bezier(.2,.7,.4,1)',
        boxShadow: '0 1px 3px rgba(0,0,0,0.2)',
      }} />
    </button>
  );
}

// Checkbox (square, filled brand when on)
function Check({ checked, onChange, label }) {
  return (
    <label style={{ display: 'inline-flex', alignItems: 'center', gap: 10, cursor: 'pointer', fontSize: 14, color: 'var(--vw-text-2)' }}>
      <span style={{
        width: 18, height: 18, borderRadius: 5,
        background: checked ? 'var(--vw-brand)' : 'var(--vw-surface)',
        border: `1.5px solid ${checked ? 'var(--vw-brand)' : 'var(--vw-border-2)'}`,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        color: 'var(--vw-on-brand)',
        transition: 'all .15s', flexShrink: 0,
      }}>
        {checked && <Icon name="check" size={12} strokeWidth={2.5} />}
      </span>
      <input type="checkbox" checked={!!checked} onChange={onChange || (()=>{})} style={{ display: 'none' }} />
      {label}
    </label>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Tabs (underline)
// ──────────────────────────────────────────────────────────────────────────
function Tabs({ items, value, onChange, variant = 'underline', style }) {
  if (variant === 'underline') {
    return (
      <div style={{ display: 'flex', gap: 24, borderBottom: '1px solid var(--vw-border)', ...style }}>
        {items.map(it => (
          <button key={it.id || it} onClick={() => onChange(it.id || it)} style={{
            padding: '10px 0',
            border: 'none', background: 'transparent',
            borderBottom: `2px solid ${value === (it.id || it) ? 'var(--vw-text)' : 'transparent'}`,
            color: value === (it.id || it) ? 'var(--vw-text)' : 'var(--vw-muted)',
            fontSize: 13, fontWeight: 500, cursor: 'pointer',
            marginBottom: -1,
            display: 'inline-flex', alignItems: 'center', gap: 6,
          }}>
            {it.label || it}
            {it.count != null && <Badge tone="default">{it.count}</Badge>}
          </button>
        ))}
      </div>
    );
  }
  // pill
  return (
    <div style={{
      display: 'inline-flex', gap: 2, padding: 3,
      background: 'var(--vw-surface-2)',
      border: '1px solid var(--vw-border)',
      borderRadius: 10,
      ...style,
    }}>
      {items.map(it => (
        <button key={it.id || it} onClick={() => onChange(it.id || it)} style={{
          padding: '6px 12px',
          border: 'none',
          background: value === (it.id || it) ? 'var(--vw-surface)' : 'transparent',
          color: value === (it.id || it) ? 'var(--vw-text)' : 'var(--vw-muted)',
          borderRadius: 7,
          fontSize: 13, fontWeight: 500, cursor: 'pointer',
          boxShadow: value === (it.id || it) ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
          fontFamily: 'inherit',
        }}>
          {it.label || it}
        </button>
      ))}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Avatar
// ──────────────────────────────────────────────────────────────────────────
const AV_COLORS = [
  ['#FFE0B2','#D84315'], ['#C8E6C9','#1B5E20'], ['#BBDEFB','#0D47A1'],
  ['#F8BBD0','#880E4F'], ['#D1C4E9','#4527A0'], ['#FFECB3','#E65100'],
  ['#B2DFDB','#004D40'], ['#FFCDD2','#B71C1C'],
];
function Avatar({ name = '', src, size = 32, ring = false, style }) {
  const initials = name.split(' ').filter(Boolean).slice(0, 2).map(s => s[0]).join('').toUpperCase() || '·';
  const hash = name.split('').reduce((a, c) => a + c.charCodeAt(0), 0);
  const [bg, fg] = AV_COLORS[hash % AV_COLORS.length];
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%',
      background: src ? `url(${src}) center/cover` : bg,
      color: fg, flexShrink: 0,
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      fontSize: size * 0.38, fontWeight: 600, fontFamily: 'var(--vw-sans)',
      letterSpacing: '-0.02em',
      ...(ring && { boxShadow: '0 0 0 2px var(--vw-surface), 0 0 0 3px var(--vw-border-2)' }),
      ...style,
    }}>
      {!src && initials}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Divider
// ──────────────────────────────────────────────────────────────────────────
function Divider({ orientation = 'horizontal', style }) {
  return (
    <div style={{
      ...(orientation === 'horizontal'
        ? { width: '100%', height: 1, background: 'var(--vw-border)' }
        : { width: 1, height: '100%', background: 'var(--vw-border)' }),
      ...style,
    }} />
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Section wrapper — centered max-width container for marketing pages
// ──────────────────────────────────────────────────────────────────────────
function Section({ children, padY = 96, padX = 48, bg, style, maxWidth = 1200, full = false }) {
  return (
    <section style={{ background: bg || 'transparent', padding: `${padY}px ${padX}px`, ...style }}>
      <div style={{ maxWidth: full ? 'none' : maxWidth, margin: '0 auto', width: '100%' }}>
        {children}
      </div>
    </section>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Table primitives
// ──────────────────────────────────────────────────────────────────────────
function Table({ children, style }) {
  return (
    <div style={{ width: '100%', overflowX: 'auto', ...style }}>
      <table style={{
        width: '100%', borderCollapse: 'separate', borderSpacing: 0,
        fontFamily: 'var(--vw-sans)',
      }}>
        {children}
      </table>
    </div>
  );
}
function Th({ children, style, align = 'left', width }) {
  return (
    <th style={{
      textAlign: align, padding: '10px 14px',
      borderBottom: '1px solid var(--vw-border)',
      background: 'var(--vw-bg-alt)',
      fontSize: 11, fontWeight: 600, letterSpacing: '0.04em',
      color: 'var(--vw-muted)',
      textTransform: 'uppercase',
      whiteSpace: 'nowrap',
      width,
      ...style,
    }}>{children}</th>
  );
}
function Td({ children, style, align = 'left', mono = false }) {
  return (
    <td style={{
      padding: '12px 14px',
      borderBottom: '1px solid var(--vw-divider)',
      fontSize: 13,
      color: 'var(--vw-text)',
      textAlign: align,
      fontFamily: mono ? 'var(--vw-mono)' : 'inherit',
      verticalAlign: 'middle',
      ...style,
    }}>{children}</td>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Stat / KPI card
// ──────────────────────────────────────────────────────────────────────────
function Stat({ label, value, delta, icon, spark }) {
  const positive = delta && !String(delta).startsWith('-');
  return (
    <Card padding={20}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 12 }}>
        <div style={{ fontSize: 12, color: 'var(--vw-muted)', fontWeight: 500, letterSpacing: '0.02em' }}>{label}</div>
        {icon && <Icon name={icon} size={16} color="var(--vw-subtle)" />}
      </div>
      <div style={{ fontSize: 28, fontWeight: 500, letterSpacing: '-0.03em', fontFamily: 'var(--vw-sans)', fontFeatureSettings: '"tnum"' }}>
        {value}
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 10 }}>
        {delta && (
          <span style={{ fontSize: 12, fontWeight: 500, color: positive ? 'var(--vw-green)' : 'var(--vw-red)', fontFamily: 'var(--vw-mono)' }}>
            {positive ? '↑' : '↓'} {String(delta).replace(/^-/, '')}
          </span>
        )}
        {spark}
      </div>
    </Card>
  );
}

// Mini sparkline SVG for stat cards
function Spark({ data, color = 'var(--vw-text)', width = 80, height = 24 }) {
  if (!data || !data.length) return null;
  const max = Math.max(...data), min = Math.min(...data);
  const range = max - min || 1;
  const step = width / (data.length - 1);
  const pts = data.map((v, i) => `${i * step},${height - ((v - min) / range) * (height - 4) - 2}`).join(' ');
  return (
    <svg width={width} height={height} style={{ display: 'block' }}>
      <polyline points={pts} fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Kbd
// ──────────────────────────────────────────────────────────────────────────
function Kbd({ children }) {
  return (
    <kbd style={{
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      minWidth: 20, height: 20, padding: '0 6px',
      fontFamily: 'var(--vw-mono)', fontSize: 11,
      background: 'var(--vw-surface-2)',
      border: '1px solid var(--vw-border-2)',
      borderBottomWidth: 2,
      borderRadius: 4,
      color: 'var(--vw-muted)',
    }}>{children}</kbd>
  );
}

Object.assign(window, {
  Btn, Badge, Card, Input, Field, Toggle, Check, Tabs, Avatar, Divider,
  Section, Table, Th, Td, Stat, Spark, Kbd,
});
