import { useState } from 'react'
import {
  Activity,
  CalendarDays,
  CircleHelp,
  FileStack,
  House,
  ListChecks,
  Menu,
  RefreshCw,
  Send,
  Settings,
  Upload,
  UsersRound,
  X,
} from 'lucide-react'

import { useAppStore } from '../lib/store'
import type { View } from '../lib/store'

type Tab = {
  view: View
  label: string
  icon: typeof House
}

const primaryTabs: Tab[] = [
  { view: 'home', label: 'Inicio', icon: House },
  { view: 'content', label: 'Contenido', icon: FileStack },
  { view: 'calendar', label: 'Calendario', icon: CalendarDays },
  { view: 'publish', label: 'Publicar', icon: Send },
]

const moreTabs: Tab[] = [
  { view: 'queue', label: 'Cola', icon: ListChecks },
  { view: 'accounts', label: 'Cuentas', icon: UsersRound },
  { view: 'import', label: 'Importar', icon: Upload },
  { view: 'activity', label: 'Actividad', icon: Activity },
  { view: 'sync', label: 'Sincronización', icon: RefreshCw },
  { view: 'help', label: 'Cómo usar', icon: CircleHelp },
  { view: 'settings', label: 'Ajustes', icon: Settings },
]

export function MobileNav() {
  const view = useAppStore((state) => state.view)
  const setView = useAppStore((state) => state.setView)
  const [moreOpen, setMoreOpen] = useState(false)

  const go = (next: View) => {
    setView(next)
    setMoreOpen(false)
  }

  return (
    <>
      <nav className="mobile-tabbar" aria-label="Navegación principal">
        {primaryTabs.map(({ view: id, label, icon: Icon }) => (
          <button
            key={id}
            className={view === id ? 'mobile-tab active' : 'mobile-tab'}
            onClick={() => go(id)}
          >
            <Icon size={20} strokeWidth={1.8}/>
            <span>{label}</span>
          </button>
        ))}

        <button
          className={moreOpen ? 'mobile-tab active' : 'mobile-tab'}
          onClick={() => setMoreOpen((value) => !value)}
          aria-expanded={moreOpen}
        >
          <Menu size={20} strokeWidth={1.8}/>
          <span>Más</span>
        </button>
      </nav>

      {moreOpen && (
        <div className="mobile-more-backdrop" onClick={() => setMoreOpen(false)}>
          <section
            className="mobile-more-sheet"
            onClick={(event) => event.stopPropagation()}
            aria-label="Más opciones"
          >
            <header>
              <div>
                <small>ABRAXAS PUBLISHER</small>
                <strong>Más herramientas</strong>
              </div>
              <button
                className="mobile-sheet-close"
                onClick={() => setMoreOpen(false)}
                aria-label="Cerrar"
              >
                <X size={19}/>
              </button>
            </header>

            <div className="mobile-more-grid">
              {moreTabs.map(({ view: id, label, icon: Icon }) => (
                <button key={id} onClick={() => go(id)}>
                  <Icon size={20}/>
                  <span>{label}</span>
                </button>
              ))}
            </div>
          </section>
        </div>
      )}
    </>
  )
}
