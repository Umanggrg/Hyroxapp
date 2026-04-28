import type { Config } from "tailwindcss";

// Mirrors Trakr's app design tokens (CLAUDE.md §5).
// Keeping this in lock-step with the iOS Color extensions
// means the website and the app feel like the same product.
const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        background: "#0A0A0B",
        surface: "#141416",
        "surface-elevated": "#1C1C1F",
        "text-primary": "#F5F5F7",
        "text-secondary": "#8E8E93",
        "text-tertiary": "#636366",
        accent: "#FF3B30",
        "accent-dim": "rgba(255, 59, 48, 0.6)",
        success: "#32D74B",
        warning: "#FF9F0A",
        divider: "#2C2C2E",
      },
      fontFamily: {
        sans: [
          "-apple-system",
          "BlinkMacSystemFont",
          "SF Pro Text",
          "Inter",
          "system-ui",
          "sans-serif",
        ],
        mono: [
          "SF Mono",
          "ui-monospace",
          "Menlo",
          "Monaco",
          "Cascadia Code",
          "monospace",
        ],
        rounded: [
          "SF Pro Rounded",
          "-apple-system",
          "BlinkMacSystemFont",
          "system-ui",
          "sans-serif",
        ],
      },
      letterSpacing: {
        caps: "0.08em",
      },
      borderRadius: {
        card: "16px",
        pill: "999px",
      },
      boxShadow: {
        glow: "0 0 60px -20px rgba(255, 59, 48, 0.45)",
        card: "0 1px 0 0 rgba(255,255,255,0.04) inset, 0 12px 30px -10px rgba(0,0,0,0.6)",
      },
      backgroundImage: {
        "hero-radial":
          "radial-gradient(ellipse 80% 60% at 50% 0%, rgba(255,59,48,0.14) 0%, rgba(255,59,48,0) 70%)",
        "card-edge":
          "linear-gradient(180deg, rgba(255,255,255,0.04) 0%, rgba(255,255,255,0) 50%)",
      },
      keyframes: {
        pulseDot: {
          "0%, 100%": { opacity: "1" },
          "50%": { opacity: "0.4" },
        },
        riseIn: {
          "0%": { opacity: "0", transform: "translateY(12px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
      },
      animation: {
        pulseDot: "pulseDot 1.6s ease-in-out infinite",
        riseIn: "riseIn 0.7s ease-out both",
      },
    },
  },
  plugins: [],
};

export default config;
