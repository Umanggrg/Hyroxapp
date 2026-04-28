import type { CSSProperties, ReactNode } from "react";

// PhoneFrame — a clean iPhone 15 Pro chassis as pure SVG + HTML
// overlay. The chassis is SVG so the bezel renders crisply at
// any scale; the screen is an HTML overlay so screen mocks can
// be authored as ordinary React/Tailwind components.
//
// Sizing is controlled by `width`. Aspect ratio is locked to the
// real device (≈1:2.05). Children render inside the screen mask
// so any overflow is clipped to the rounded rectangle, just like
// a real screen would.
//
// `tilt` adds a tiny 3D-ish rotation for hero compositions —
// Apple's marketing pages use this trick everywhere. Default 0.

type PhoneFrameProps = {
  width?: number;
  tilt?: number; // degrees, applied as rotateY
  rotate?: number; // 2D rotation in degrees
  className?: string;
  style?: CSSProperties;
  children?: ReactNode;
};

export function PhoneFrame({
  width = 320,
  tilt = 0,
  rotate = 0,
  className = "",
  style,
  children,
}: PhoneFrameProps) {
  const aspect = 2.05; // height / width
  const height = Math.round(width * aspect);

  // Inner screen padding as a fraction of width — same proportions
  // as a 15 Pro: ~6px bezel on a ~390pt wide device.
  const bezel = Math.round(width * 0.022);
  const cornerOuter = Math.round(width * 0.155);
  const cornerInner = Math.round(width * 0.135);
  const islandWidth = Math.round(width * 0.34);
  const islandHeight = Math.round(width * 0.094);
  const islandTop = Math.round(width * 0.038);

  return (
    <div
      className={`relative ${className}`}
      style={{
        width,
        height,
        transform: `perspective(1400px) rotateY(${tilt}deg) rotate(${rotate}deg)`,
        transformStyle: "preserve-3d",
        ...style,
      }}
    >
      {/* Chassis — outer body. Subtle radial gives the titanium feel. */}
      <svg
        viewBox={`0 0 ${width} ${height}`}
        width={width}
        height={height}
        className="absolute inset-0 drop-shadow-[0_40px_80px_rgba(0,0,0,0.6)]"
        aria-hidden
      >
        <defs>
          <linearGradient id="chassis" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#2a2a2c" />
            <stop offset="50%" stopColor="#0c0c0d" />
            <stop offset="100%" stopColor="#1f1f21" />
          </linearGradient>
          <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="rgba(255,255,255,0.18)" />
            <stop offset="50%" stopColor="rgba(255,255,255,0)" />
            <stop offset="100%" stopColor="rgba(255,255,255,0.08)" />
          </linearGradient>
        </defs>

        {/* Outer body */}
        <rect
          x={0}
          y={0}
          width={width}
          height={height}
          rx={cornerOuter}
          ry={cornerOuter}
          fill="url(#chassis)"
        />
        {/* Glossy rim highlight */}
        <rect
          x={0.5}
          y={0.5}
          width={width - 1}
          height={height - 1}
          rx={cornerOuter - 0.5}
          ry={cornerOuter - 0.5}
          fill="none"
          stroke="url(#rim)"
          strokeWidth={1}
        />
        {/* Side buttons — power on right, vol on left. */}
        <rect
          x={-1}
          y={Math.round(height * 0.18)}
          width={3}
          height={Math.round(height * 0.05)}
          fill="#1a1a1c"
          rx={1.5}
        />
        <rect
          x={-1}
          y={Math.round(height * 0.27)}
          width={3}
          height={Math.round(height * 0.08)}
          fill="#1a1a1c"
          rx={1.5}
        />
        <rect
          x={-1}
          y={Math.round(height * 0.37)}
          width={3}
          height={Math.round(height * 0.08)}
          fill="#1a1a1c"
          rx={1.5}
        />
        <rect
          x={width - 2}
          y={Math.round(height * 0.22)}
          width={3}
          height={Math.round(height * 0.11)}
          fill="#1a1a1c"
          rx={1.5}
        />
      </svg>

      {/* Screen overlay — clipped to inner rounded rect. */}
      <div
        className="absolute overflow-hidden bg-background"
        style={{
          top: bezel,
          left: bezel,
          right: bezel,
          bottom: bezel,
          borderRadius: cornerInner,
        }}
      >
        {children}

        {/* Dynamic Island — sits on top of screen content. */}
        <div
          className="absolute left-1/2 -translate-x-1/2 bg-black rounded-full z-20 ring-1 ring-black/80"
          style={{
            top: islandTop,
            width: islandWidth,
            height: islandHeight,
          }}
        />
      </div>
    </div>
  );
}
