import { useEffect } from 'react'

import { Sidebar } from './components/Sidebar'
import { TopBar } from './components/TopBar'
import { Inspector } from './components/Inspector'
import { ContentDetail } from './components/ContentDetail'

import { HomeView } from './views/HomeView'
import { TodayView } from './views/TodayView'
import { ContentView } from './views/ContentView'
import { KanbanView } from './views/KanbanView'
import { ImportView } from './views/ImportView'
import { CalendarView } from './views/CalendarView'
import { QueueView } from './views/QueueView'
import { ActivityView } from './views/ActivityView'
import { HelpView } from './views/HelpView'
import { SettingsView } from './views/SettingsView'

import { useAppStore } from './lib/store'
import { backend } from './lib/backend'

function MainView() {
  const v = useAppStore(
    (s) => s.view,
  )

  if (v === 'home') return <HomeView/>
  if (v === 'content') return <ContentView/>
  if (v === 'kanban') return <KanbanView/>
  if (v === 'import') return <ImportView/>
  if (v === 'calendar') return <CalendarView/>
  if (v === 'queue') return <QueueView/>
  if (v === 'activity') return <ActivityView/>
  if (v === 'help') return <HelpView/>
  if (v === 'settings') return <SettingsView/>

  return <TodayView/>
}

export default function App() {
  const {
    contents,
    setContents,
    brands,
    setBrands,
    selectedId,
    selectedIds,
    inspectorMode,
    detailOpen,
  } = useAppStore()

  useEffect(() => {
    Promise.all([
      backend.listContents(),
      backend.listBrands(),
    ])
      .then(([content, brandList]) => {
        setContents(content)
        setBrands(brandList)
      })
      .catch(console.error)
  }, [setContents, setBrands])

  useEffect(() => {
    const handler = async (
      event: KeyboardEvent,
    ) => {
      if (!event.metaKey) return

      if (
        event.key.toLowerCase() === 'z'
        && !event.shiftKey
      ) {
        event.preventDefault()

        await backend.undo()
        setContents(
          await backend.listContents(),
        )
      }

      if (
        event.key.toLowerCase() === 'z'
        && event.shiftKey
      ) {
        event.preventDefault()

        await backend.redo()
        setContents(
          await backend.listContents(),
        )
      }
    }

    window.addEventListener(
      'keydown',
      handler,
    )

    return () =>
      window.removeEventListener(
        'keydown',
        handler,
      )
  }, [setContents])

  const selected = contents.filter(
    (c) => selectedIds.includes(c.id),
  )

  const primary = contents.find(
    (c) => c.id === selectedId,
  )

  const docked =
    selected.length > 0
    && inspectorMode === 'docked'

  return (
    <>
      <div
        className={
          docked
            ? 'app-shell with-inspector'
            : 'app-shell no-inspector'
        }
      >
        <Sidebar/>

        <div className="center-shell">
          <TopBar/>
          <main className="main-area">
            <MainView/>
          </main>
        </div>

        {
          selected.length > 0
          && inspectorMode !== 'hidden'
          && (
            <Inspector
              items={selected}
              mode={inspectorMode}
            />
          )
        }
      </div>

      {
        detailOpen
        && primary
        && (
          <ContentDetail
            item={primary}
            brands={brands}
          />
        )
      }
    </>
  )
}
