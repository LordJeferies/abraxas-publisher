import {
  Activity,
  CalendarDays,
  Columns3,
  FileStack,
  House,
  LayoutDashboard,
  ListChecks,
  Send,
  Settings,
  Upload,
  UsersRound,
  CircleHelp,
} from 'lucide-react'

import {
  useAppStore,
} from '../lib/store'

import type {
  View,
} from '../lib/store'

type Item = [
  View,
  typeof House,
  string,
]

const contentItems:
  Item[] = [
    [
      'content',
      FileStack,
      'Biblioteca',
    ],
    [
      'kanban',
      Columns3,
      'Estados',
    ],
    [
      'calendar',
      CalendarDays,
      'Calendario',
    ],
  ]

const publishingItems:
  Item[] = [
    [
      'publish',
      Send,
      'Preparar publicación',
    ],
    [
      'queue',
      ListChecks,
      'Cola',
    ],
  ]

const operationsItems:
  Item[] = [
    [
      'accounts',
      UsersRound,
      'Cuentas',
    ],
    [
      'import',
      Upload,
      'Importar',
    ],
    [
      'activity',
      Activity,
      'Actividad',
    ],
  ]

function NavGroup({
  label,
  items,
}: {
  label: string
  items: Item[]
}) {
  const view =
    useAppStore(
      (s) => s.view,
    )

  const setView =
    useAppStore(
      (s) => s.setView,
    )

  return (
    <div className="nav-group">
      <small className="nav-group-label">
        {label}
      </small>

      {
        items.map(
          ([
            id,
            Icon,
            text,
          ]) => (
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
                {text}
              </span>
            </button>
          ),
        )
      }
    </div>
  )
}

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
            Publisher · v1.3
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
            brands.map(
              (brand) => (
                <option
                  key={brand.id}
                  value={brand.name}
                >
                  {brand.name}
                </option>
              ),
            )
          }
        </select>
      </div>

      <nav>
        <div className="nav-group">
          <small className="nav-group-label">
            INICIO
          </small>

          <button
            className={
              view === 'home'
                ? 'nav-item active'
                : 'nav-item'
            }
            onClick={() =>
              setView('home')
            }
          >
            <House size={17}/>
            Inicio
          </button>

          <button
            className={
              view === 'today'
                ? 'nav-item active'
                : 'nav-item'
            }
            onClick={() =>
              setView('today')
            }
          >
            <LayoutDashboard size={17}/>
            Hoy
          </button>
        </div>

        <NavGroup
          label="CONTENIDO"
          items={
            contentItems
          }
        />

        <NavGroup
          label="PUBLICACIÓN"
          items={
            publishingItems
          }
        />

        <NavGroup
          label="OPERACIONES"
          items={
            operationsItems
          }
        />
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
          Cómo usar
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
          Ajustes
        </button>
      </nav>

      <div className="sidebar-foot publishing-ready">
        <Send size={14}/>
        Publishing Center
      </div>
    </aside>
  )
}
