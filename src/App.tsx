import { useEffect, useState } from 'react'

import './progress.css'

import { Sidebar } from './components/Sidebar'
import { TopBar } from './components/TopBar'
import { Inspector } from './components/Inspector'
import { ContentDetail } from './components/ContentDetail'
import { GlobalProgress } from './components/GlobalProgress'
import { WelcomeScreen } from './components/WelcomeScreen'

import { HomeView } from './views/HomeView'
import { TodayView } from './views/TodayView'
import { ContentView } from './views/ContentView'
import { KanbanView } from './views/KanbanView'
import { ImportView } from './views/ImportView'
import { CalendarView } from './views/CalendarView'
import { QueueView } from './views/QueueView'
import { PublishView } from './views/PublishView'
import { AccountsView } from './views/AccountsView'
import { SyncView } from './views/SyncView'
import { ActivityView } from './views/ActivityView'
import { HelpView } from './views/HelpView'
import { SettingsView } from './views/SettingsView'

import { useAppStore } from './lib/store'
import { backend } from './lib/backend'
import { runProgressTask } from './lib/progress'

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
  if (v === 'publish') return <PublishView/>
  if (v === 'accounts') return <AccountsView/>
  if (v === 'sync') return <SyncView/>
  if (v === 'activity') return <ActivityView/>
  if (v === 'help') return <HelpView/>
  if (v === 'settings') return <SettingsView/>

  return <TodayView/>
}

export default function App() {
  const [welcomeOpen, setWelcomeOpen] =
    useState(true)

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
    const load = () =>
      runProgressTask(
        'Preparando Publisher',
        async () => {
          const [content, brandList] =
            await Promise.all([
              backend.listContents(),
              backend.listBrands(),
            ])

          setContents(content)
          setBrands(brandList)
        },
        {
          detail: 'Cargando contenido y marcas',
          blocking: false,
        },
      ).catch(console.error)

    load()

    window.addEventListener(
      'abraxas-portable-updated',
      load,
    )

    return () =>
      window.removeEventListener(
        'abraxas-portable-updated',
        load,
      )
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

        await runProgressTask(
          'Deshaciendo cambio',
          async () => {
            await backend.undo()
            setContents(
              await backend.listContents(),
            )
          },
        )
      }

      if (
        event.key.toLowerCase() === 'z'
        && event.shiftKey
      ) {
        event.preventDefault()

        await runProgressTask(
          'Rehaciendo cambio',
          async () => {
            await backend.redo()
            setContents(
              await backend.listContents(),
            )
          },
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
      <GlobalProgress/>

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
          />
        )
      }

      {
        welcomeOpen
        && (
          <WelcomeScreen
            onEnter={() => setWelcomeOpen(false)}
          />
        )
      }
    </>
  )
}
