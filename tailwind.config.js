import tailwindcssAnimate from 'tailwindcss-animate';

/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  darkMode: ['class', '[data-theme-mode="dark"]'],
  theme: {
    extend: {
      colors: {
        /* 课集 DESIGN.md 原生语义 Token */
        canvas: 'var(--color-canvas)',
        surface: 'var(--color-surface)',
        'table-header': 'var(--color-table-header)',
        ink: 'var(--color-ink)',
        'ink-secondary': 'var(--color-ink-secondary)',
        muted: {
          DEFAULT: 'var(--color-table-header)',
          foreground: 'var(--color-muted)',
        },
        accent: {
          DEFAULT: 'var(--color-selection)',
          foreground: 'var(--color-accent)',
        },
        'brand-accent': 'var(--color-accent)',
        'on-accent': 'var(--color-on-accent)',
        selection: 'var(--color-selection)',
        'sidebar-active': 'var(--color-sidebar-active)',
        'sidebar-text': 'var(--color-sidebar-text)',
        'sidebar-muted': 'var(--color-sidebar-muted)',
        border: 'var(--color-border)',
        'control-border': 'var(--color-control-border)',
        'table-divider': 'var(--color-table-divider)',
        purple: 'var(--color-purple)',
        success: 'var(--color-success)',
        'success-surface': 'var(--color-success-surface)',
        warning: 'var(--color-warning)',
        'warning-surface': 'var(--color-warning-surface)',
        destructive: {
          DEFAULT: 'var(--color-destructive)',
          foreground: 'var(--color-on-accent)',
          surface: 'var(--color-destructive-surface)',
        },

        /* shadcn/ui 标准语义变量桥接（自动随晴空蓝/海盐青/云白墨灰三套明暗主题切换） */
        background: 'var(--color-canvas)',
        foreground: 'var(--color-ink)',
        card: {
          DEFAULT: 'var(--color-surface)',
          foreground: 'var(--color-ink)',
        },
        popover: {
          DEFAULT: 'var(--color-surface)',
          foreground: 'var(--color-ink)',
        },
        primary: {
          DEFAULT: 'var(--color-accent)',
          foreground: 'var(--color-on-accent)',
        },
        secondary: {
          DEFAULT: 'var(--color-table-header)',
          foreground: 'var(--color-ink)',
        },
        input: 'var(--color-control-border)',
        ring: 'var(--color-accent)',
      },
      borderRadius: {
        card: '20px',
        control: '12px',
        lg: '12px',
        md: '9px',
        sm: '6px',
      },
      transitionDuration: {
        feedback: '120ms',
        page: '180ms',
      },
      fontFamily: {
        sans: [
          '-apple-system',
          'BlinkMacSystemFont',
          '"PingFang SC"',
          '"Segoe UI"',
          '"Microsoft YaHei"',
          'sans-serif',
        ],
        mono: [
          'ui-monospace',
          'SFMono-Regular',
          'Menlo',
          'Monaco',
          'Consolas',
          'monospace',
        ],
      },
    },
  },
  plugins: [tailwindcssAnimate],
};
