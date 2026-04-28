import type { CSSProperties, ReactNode } from "react";

// WatchFrame — Apple Watch Series 9 / Ultra-style chassis. Same
// approach as PhoneFrame: SVG chassis with an HTML screen
// overlay. Aspect ratio is locked to the 45mm display.

type WatchFrameProps = {
  width?: number;
  rotate?: number;
  className?: string;
  style?: CSSProperties;
  children?: ReactNode;
};

export function WatchFrame({
  width = 200,
  rotate = 0,
  className = "",
  style,
  children,
}: WatchFrameProps) {
  const aspect = 1.18;
  const height = Math.round(width * aspect);
  const bezel = Math.round(width * 0.06);
  const cornerOuter = Math.round(width * 0.24);
  const cornerInner = Math.round(width * 0.18);

  return (
    <div
      className={`relative ${className}`}
      style={{
        width,
        height,
        transform: `rotate(${rotate}deg)`,
        ...style,
      }}
    >
      <svg
        viewBox={`0 0 ${width} ${height}`}
        width={width}
        height={height}
        className="absolute inset-0 drop-shadow-[0_30px_60px_rgba(0,0,0,0.6)]"
        aria-hidden
      >
        <defs>
          <linearGradient id="watchChassis" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#2a2a2c" />
            <stop offset="60%" stopColor="#0d0d0e" />
            <stop offset="100%" stopColor="#1f1f21" />
          </linearGradient>
        </defs>
        <rect
          x={0}
          y={0}
          width={width}
          height={height}
          rx={cornerOuter}
          ry={cornerOuter}
          fill="url(#watchChassis)"
        />
        {/* Digital crown */}
        <rect
          x={width - 3}
          y={Math.round(height * 0.32)}
          width={5}
          height={Math.round(height * 0.1)}
          fill="#1a1a1c"
          rx={2}
        />
        {/* Side button */}
        <rect
          x={width - 2}
          y={Math.round(height * 0.5)}
          width={3}
          height={Math.round(height * 0.08)}
          fill="#1a1a1c"
          rx={1.5}
        />
      </svg>
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
      </div>
    </div>
  );
}
