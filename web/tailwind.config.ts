import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        tinta: '#16202b',
        acento: '#0b62d6',
        fondo: '#f7f9fc',
      },
    },
  },
  plugins: [],
};

export default config;
