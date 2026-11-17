import type { Metadata, Viewport } from 'next'
import './globals.css'

export const metadata: Metadata = {
  metadataBase: new URL('https://app.winopo.es'),
  title: 'WinOpo · preparación de oposiciones',
  description: 'Temario, tests y supuestos con corrección por rúbrica, para preparadores y opositores.',
  manifest: '/manifest.webmanifest',
  robots: { index: true, follow: true },
}

export const viewport: Viewport = {
  themeColor: '#0b62d6',
  width: 'device-width',
  initialScale: 1,
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <body>
        <header className="border-b border-slate-200 bg-white">
          <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-4">
            <a href="/" className="text-lg font-semibold tracking-tight">
              win<span className="text-acento">opo</span>
            </a>
            <nav className="flex items-center gap-4 text-sm">
              <a href="/login" className="hover:text-acento">
                Acceder
              </a>
            </nav>
          </div>
        </header>
        <main className="mx-auto max-w-5xl px-4 py-10">{children}</main>
        <footer className="mx-auto flex max-w-5xl flex-wrap gap-4 px-4 py-8 text-xs text-slate-500">
          <span>WinOpo · winopo.es</span>
          <a href="/legal/aviso-legal" className="hover:text-acento">Aviso legal</a>
          <a href="/legal/privacidad" className="hover:text-acento">Privacidad</a>
        </footer>
      </body>
    </html>
  )
}
