import {
  Activity,
  CalendarDays,
  FileStack,
  Inbox,
  LayoutDashboard,
  Settings,
  Upload,
  ListChecks,
  Columns3,
  CircleHelp,
  House,
} from 'lucide-react'

import { useAppStore } from '../lib/store'

const items = [
  ['home', House, 'Inicio'],
  ['today', LayoutDashboard, 'Hoy'],
  ['content', FileStack, 'Contenido'],
  ['kanban', Columns3, 'Estados'],
  ['calendar', CalendarDays, 'Calendario'],
  ['queue', ListChecks, 'Cola'],
  ['import', Upload, 'Importar'],
  ['activity', Activity, 'Actividad'],
] as const

export function Sidebar() {
  const {
    view,
    setView,
    brands,
    selectedBrand,
    setSelectedBrand,
  } = useAppStore()

  return (
    <aside className="sidebar">
      <div className="brand-row">
        <div className="brand-mark">
          A
        </div>

        <div>
          <strong>
            ABRAXAS
          </strong>

          <span>
            Publisher · v1.2
          </span>
        </div>
      </div>

      <div className="brand-switcher">
        <small>
          MARCA
        </small>

        <select
          value={selectedBrand}
          onChange={(e) =>
            setSelectedBrand(
              e.target.value,
            )
          }
        >
          <option value="ALL">
            Todas
          </option>

          {
            brands.map((b) => (
              <option
                key={b.id}
                value={b.name}
              >
                {b.name}
              </option>
            ))
          }
        </select>
      </div>

      <nav>
        {
          items.map(
            ([id, Icon, label]) => (
              <button
                key={id}
                className={
                  view === id
                    ? 'nav-item active'
                    : 'nav-item'
                }
                onClick={() =>
                  setView(id)
                }
              >
                <Icon
                  size={17}
                  strokeWidth={1.8}
                />

                <span>
                  {label}
                </span>
              </button>
            ),
          )
        }
      </nav>

      <div className="sidebar-spacer"/>

      <nav>
        <button
          className={
            view === 'help'
              ? 'nav-item active'
              : 'nav-item'
          }
          onClick={() =>
            setView('help')
          }
        >
          <CircleHelp size={17}/>
          <span>Cómo usar</span>
        </button>

        <button
          className={
            view === 'settings'
              ? 'nav-item active'
              : 'nav-item'
          }
          onClick={() =>
            setView('settings')
          }
        >
          <Settings size={17}/>
          <span>Ajustes</span>
        </button>
      </nav>

      <div className="sidebar-foot">
        <Inbox size={15}/>
        <span>
          Local · Sin publicar
        </span>
      </div>
    </aside>
  )
}
