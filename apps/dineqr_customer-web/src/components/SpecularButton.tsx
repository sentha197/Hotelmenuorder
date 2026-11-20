import {
  useEffect,
  useRef,
  type CSSProperties,
  type ElementType,
  type HTMLAttributes,
  type ReactNode,
} from 'react';
import './SpecularButton.css';

export type SpecularButtonProps = Omit<HTMLAttributes<HTMLElement>, 'color'> & {
  children?: ReactNode;
  /**
   * The element to render. `button` by default; use `span` when the
   * button sits inside another control (a `<button>` cannot hold one).
   */
  as?: ElementType;
  type?: 'button' | 'submit' | 'reset';
  disabled?: boolean;
  size?: 'sm' | 'md' | 'lg';
  /** Corner radius in px (999 for a pill). Defaults to the element's own. */
  radius?: number;
  /** Body colour and its opacity. Leave unset to keep the element's CSS. */
  tint?: string;
  tintOpacity?: number;
  /** Label colour. Leave unset to keep the element's CSS. */
  textColor?: string;
  /** Colour of the travelling light (any CSS colour, `var(--x)` included). */
  lineColor?: string;
  /** Colour of the faint hairline the light runs along. */
  baseColor?: string;
  /** Light strength with the pointer close by, and when it is not. */
  intensity?: number;
  idleIntensity?: number;
  /** Radius of the light's bright core, then the length of its fade, in px. */
  shineSize?: number;
  shineFade?: number;
  /** Width of the edge line, in px. */
  thickness?: number;
  /** Strength of the bloom outside the edge (0 for none). */
  glow?: number;
  /** Keep the light circling on its own (touch screens have no hover). */
  autoAnimate?: boolean;
  /** Laps per 4 seconds: 0.5 is one lap every 8 s. */
  speed?: number;
  /** Pull the light toward a pointer within `proximity` px of the edge. */
  followMouse?: boolean;
  proximity?: number;
  /** Stop drawing (e.g. a carousel slide that is not shown). */
  paused?: boolean;
};

/** How far the canvas reaches past the element, for the bloom (px). */
const BLEED = 24;

const VERTEX = `#version 300 es
in vec2 a_pos;
void main() { gl_Position = vec4(a_pos, 0.0, 1.0); }`;

// A rounded-rectangle edge: a faint base line all round, and a light that
// brightens the line near u_light and blooms a little outside it.
const FRAGMENT = `#version 300 es
precision highp float;
uniform vec2 u_canvas;   // canvas size, device px
uniform vec2 u_half;     // element half size, device px
uniform float u_radius;
uniform vec2 u_light;    // light position, device px from the element centre
uniform float u_strength;
uniform float u_core;
uniform float u_fade;
uniform float u_thick;
uniform float u_glow;
uniform float u_dpr;
uniform vec3 u_line;
uniform vec3 u_base;
out vec4 outColor;

float roundRect(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  vec2 p = gl_FragCoord.xy - u_canvas * 0.5;
  p.y = -p.y;
  float d = roundRect(p, u_half, u_radius);
  float halfLine = u_thick * 0.5;
  float line = 1.0 - smoothstep(halfLine, halfLine + u_dpr, abs(d + halfLine));

  float far = max(distance(p, u_light) - u_core, 0.0) / u_fade;
  float shine = exp(-far * far) * u_strength;

  float bloom = d > 0.0 ? exp(-d / (6.0 * u_dpr * max(u_glow, 0.001))) * u_glow * 0.55 : 0.0;

  // Where the light is strongest its colour runs to white, like a highlight.
  // (Eased, so the idle strength used on touch screens still reads clearly.)
  vec3 lit = mix(u_line, vec3(1.0), smoothstep(0.45, 1.5, shine) * 0.6);
  float lineLight = 1.0 - exp(-shine * 2.4);
  vec3 onLine = mix(u_base, lit, lineLight);
  float lineAlpha = line * mix(0.45, 1.0, lineLight);
  float bloomAlpha = clamp(bloom * (1.0 - exp(-shine * 1.8)), 0.0, 1.0);
  float a = clamp(lineAlpha + bloomAlpha * (1.0 - lineAlpha), 0.0, 1.0);
  vec3 col = a > 0.0 ? (onLine * lineAlpha + u_line * bloomAlpha * (1.0 - lineAlpha)) / a : vec3(0.0);
  outColor = vec4(col, a);
}`;

/** The rgb (0-1) of any CSS colour, resolved against [host] (so `var()` works). */
function rgbOf(host: HTMLElement, value: string): [number, number, number] {
  const probe = document.createElement('span');
  probe.style.display = 'none';
  probe.style.color = value;
  host.appendChild(probe);
  const parts = getComputedStyle(probe).color.match(/[\d.]+/g) ?? [];
  probe.remove();
  const [r = 255, g = 255, b = 255] = parts.map(Number);
  return [r / 255, g / 255, b / 255];
}

/** The point at [t] (0-1, clockwise from the top-left) along a rounded rectangle's edge. */
function pointOnEdge(t: number, hw: number, hh: number, r: number): [number, number] {
  const sw = Math.max(2 * (hw - r), 0);
  const sh = Math.max(2 * (hh - r), 0);
  const arc = (Math.PI / 2) * r;
  const segments = [sw, arc, sh, arc, sw, arc, sh, arc];
  let left = (((t % 1) + 1) % 1) * segments.reduce((a, b) => a + b, 0);
  const cx = hw - r;
  const cy = hh - r;
  for (let i = 0; i < 8; i++) {
    const len = segments[i] ?? 0;
    if (left > len && i < 7) {
      left -= len;
      continue;
    }
    const f = len > 0 ? left / len : 0;
    const corner = (from: number, ox: number, oy: number): [number, number] => {
      const a = from + f * (Math.PI / 2);
      return [ox + Math.cos(a) * r, oy + Math.sin(a) * r];
    };
    switch (i) {
      case 0: return [-cx + f * sw, -hh];
      case 1: return corner(-Math.PI / 2, cx, -cy);
      case 2: return [hw, -cy + f * sh];
      case 3: return corner(0, cx, cy);
      case 4: return [cx - f * sw, hh];
      case 5: return corner(Math.PI / 2, -cx, cy);
      case 6: return [-hw, cy - f * sh];
      default: return corner(Math.PI, -cx, -cy);
    }
  }
  return [-cx, -hh];
}

/** The edge point nearest [x, y] (element-centred px). */
function nearestOnEdge(x: number, y: number, hw: number, hh: number, r: number): [number, number] {
  const cx = Math.max(hw - r, 0);
  const cy = Math.max(hh - r, 0);
  const qx = Math.min(Math.max(x, -cx), cx);
  const qy = Math.min(Math.max(y, -cy), cy);
  let dx = x - qx;
  let dy = y - qy;
  if (dx === 0 && dy === 0) {
    // Inside the straight part: push out to the closest side.
    const toX = cx + r - Math.abs(x);
    const toY = cy + r - Math.abs(y);
    return toX < toY ? [Math.sign(x || 1) * hw, y] : [x, Math.sign(y || 1) * hh];
  }
  const len = Math.hypot(dx, dy);
  dx /= len;
  dy /= len;
  return [qx + dx * r, qy + dy * r];
}

/**
 * A button with a light that runs around its edge, drawn with WebGL2 on a
 * canvas that reaches [BLEED] px past the button (for the bloom) and never
 * takes pointer events. Without WebGL2 it is a plain button. It draws only
 * while on screen and not [paused]; with reduced motion the light stays put.
 */
export function SpecularButton({
  children,
  as: Tag = 'button',
  type,
  size = 'md',
  radius,
  tint,
  tintOpacity = 1,
  textColor,
  lineColor = 'var(--vibrant-orange, #ff7a3d)',
  baseColor = '#f5d0c2',
  intensity = 1.3,
  idleIntensity = 0.5,
  shineSize = 12,
  shineFade = 40,
  thickness = 2,
  glow = 1,
  autoAnimate = true,
  speed = 0.5,
  followMouse = true,
  proximity = 140,
  paused = false,
  className = '',
  style,
  ...rest
}: SpecularButtonProps) {
  const host = useRef<HTMLElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  // Read by the render loop, so changing a prop does not rebuild the GL state.
  const settings = useRef({ radius, lineColor, baseColor, intensity, idleIntensity, shineSize, shineFade, thickness, glow, autoAnimate, speed, followMouse, proximity });
  settings.current = { radius, lineColor, baseColor, intensity, idleIntensity, shineSize, shineFade, thickness, glow, autoAnimate, speed, followMouse, proximity };

  useEffect(() => {
    const el = host.current;
    const cv = canvas.current;
    if (!el || !cv || paused) return;

    let gl: WebGL2RenderingContext | null = null;
    try {
      gl = cv.getContext('webgl2', { premultipliedAlpha: false, antialias: false });
    } catch {
      gl = null;
    }
    if (!gl) {
      cv.hidden = true;
      return;
    }
    cv.hidden = false;

    const compile = (kind: number, source: string) => {
      const shader = gl.createShader(kind)!;
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      return shader;
    };
    const program = gl.createProgram()!;
    gl.attachShader(program, compile(gl.VERTEX_SHADER, VERTEX));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAGMENT));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      cv.hidden = true;
      return;
    }
    gl.useProgram(program);
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const pos = gl.getAttribLocation(program, 'a_pos');
    gl.enableVertexAttribArray(pos);
    gl.vertexAttribPointer(pos, 2, gl.FLOAT, false, 0, 0);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    const u = (name: string) => gl.getUniformLocation(program, name);
    const loc = {
      canvas: u('u_canvas'), half: u('u_half'), radius: u('u_radius'), light: u('u_light'),
      strength: u('u_strength'), core: u('u_core'), fade: u('u_fade'), thick: u('u_thick'),
      glow: u('u_glow'), dpr: u('u_dpr'), line: u('u_line'), base: u('u_base'),
    };

    const reduced = window.matchMedia?.('(prefers-reduced-motion: reduce)');
    let width = 0;
    let height = 0;
    let cssRadius = 0;
    let colours = { line: rgbOf(el, settings.current.lineColor), base: rgbOf(el, settings.current.baseColor), key: '' };
    const measure = () => {
      width = el.offsetWidth;
      height = el.offsetHeight;
      cssRadius = parseFloat(getComputedStyle(el).borderTopLeftRadius) || 0;
    };
    measure();

    let pointer: { x: number; y: number } | null = null;
    const onPointer = (e: PointerEvent) => {
      if (!settings.current.followMouse) return;
      pointer = { x: e.clientX, y: e.clientY };
      wake();
    };
    const onLeave = () => {
      pointer = null;
    };

    let visible = true;
    let frame = 0;
    let last = performance.now();
    let phase = 0;
    let near = 0;
    let lightX = 0;
    let lightY = 0;
    let lost = false;

    const draw = (now: number) => {
      frame = 0;
      if (lost || !visible) return;
      const s = settings.current;
      const dt = Math.min((now - last) / 1000, 0.1);
      last = now;
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const cw = Math.round((width + BLEED * 2) * dpr);
      const ch = Math.round((height + BLEED * 2) * dpr);
      if (cv.width !== cw || cv.height !== ch) {
        cv.width = cw;
        cv.height = ch;
      }
      const key = `${s.lineColor}|${s.baseColor}`;
      if (colours.key !== key) colours = { line: rgbOf(el, s.lineColor), base: rgbOf(el, s.baseColor), key };

      const hw = width / 2;
      const hh = height / 2;
      const r = Math.min(s.radius ?? cssRadius, hw, hh);
      const still = reduced?.matches ?? false;
      if (s.autoAnimate && !still) phase += (dt * s.speed) / 4;
      let [tx, ty] = still ? pointOnEdge(0.06, hw, hh, r) : pointOnEdge(phase, hw, hh, r);

      // A pointer close by pulls the light to the nearest point of the edge.
      let target = 0;
      if (s.followMouse && pointer) {
        const box = el.getBoundingClientRect();
        const px = pointer.x - (box.left + hw);
        const py = pointer.y - (box.top + hh);
        const [ex, ey] = nearestOnEdge(px, py, hw, hh, r);
        const gap = Math.hypot(px - ex, py - ey);
        const inside = Math.abs(px) <= hw && Math.abs(py) <= hh;
        target = inside ? 1 : Math.max(0, 1 - gap / Math.max(s.proximity, 1));
        if (target > 0) {
          tx += (ex - tx) * target;
          ty += (ey - ty) * target;
        }
      }
      near += (target - near) * Math.min(dt * 8, 1);
      const ease = lightX === 0 && lightY === 0 ? 1 : Math.min(dt * 14, 1);
      lightX += (tx - lightX) * ease;
      lightY += (ty - lightY) * ease;

      gl.viewport(0, 0, cw, ch);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.uniform2f(loc.canvas, cw, ch);
      gl.uniform2f(loc.half, hw * dpr, hh * dpr);
      gl.uniform1f(loc.radius, r * dpr);
      gl.uniform2f(loc.light, lightX * dpr, lightY * dpr);
      gl.uniform1f(loc.strength, s.idleIntensity + (s.intensity - s.idleIntensity) * near);
      gl.uniform1f(loc.core, s.shineSize * dpr);
      gl.uniform1f(loc.fade, Math.max(s.shineFade, 1) * dpr);
      gl.uniform1f(loc.thick, s.thickness * dpr);
      gl.uniform1f(loc.glow, s.glow);
      gl.uniform1f(loc.dpr, dpr);
      gl.uniform3f(loc.line, ...colours.line);
      gl.uniform3f(loc.base, ...colours.base);
      gl.drawArrays(gl.TRIANGLES, 0, 3);

      // Keep going while the light moves; otherwise sleep until something changes.
      const settling = Math.abs(target - near) > 0.002 || Math.abs(tx - lightX) + Math.abs(ty - lightY) > 0.05;
      if ((s.autoAnimate && !still) || settling) wake();
    };
    function wake() {
      if (!frame && visible && !lost) {
        last = performance.now();
        frame = requestAnimationFrame((t) => {
          last = Math.min(last, t);
          draw(t);
        });
      }
    }

    const resize = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(() => {
      measure();
      wake();
    });
    resize?.observe(el);
    const io = typeof IntersectionObserver === 'undefined' ? null : new IntersectionObserver(([entry]) => {
      visible = entry?.isIntersecting ?? true;
      if (visible) wake();
    });
    io?.observe(el);
    const onLost = (e: Event) => {
      e.preventDefault();
      lost = true;
      cv.hidden = true;
    };
    cv.addEventListener('webglcontextlost', onLost);
    const onMotion = () => wake();
    reduced?.addEventListener?.('change', onMotion);
    window.addEventListener('pointermove', onPointer, { passive: true });
    window.addEventListener('pointerdown', onPointer, { passive: true });
    document.documentElement.addEventListener('pointerleave', onLeave);
    wake();

    return () => {
      cancelAnimationFrame(frame);
      resize?.disconnect();
      io?.disconnect();
      cv.removeEventListener('webglcontextlost', onLost);
      reduced?.removeEventListener?.('change', onMotion);
      window.removeEventListener('pointermove', onPointer);
      window.removeEventListener('pointerdown', onPointer);
      document.documentElement.removeEventListener('pointerleave', onLeave);
      gl.deleteBuffer(buffer);
      gl.deleteProgram(program);
      // Give the context back now: browsers allow only a few at once.
      gl.getExtension('WEBGL_lose_context')?.loseContext();
    };
  }, [paused]);

  const vars: Record<string, string | number> = {};
  if (radius !== undefined) vars['--sb-radius'] = `${radius}px`;
  if (tint !== undefined) vars['--sb-tint'] = tint;
  if (tint !== undefined) vars['--sb-tint-opacity'] = tintOpacity;
  if (textColor !== undefined) vars['--sb-text'] = textColor;

  return (
    <Tag
      ref={host}
      className={`specular-btn specular-btn--${size} ${className}`.trim()}
      style={{ ...vars, ...style } as CSSProperties}
      {...(Tag === 'button' ? { type: type ?? 'button' } : {})}
      {...rest}
    >
      {/* A new canvas each time drawing resumes: a released context cannot be reused. */}
      {!paused && <canvas ref={canvas} className="specular-btn__canvas" aria-hidden hidden />}
      <span className="specular-btn__label">{children}</span>
    </Tag>
  );
}
