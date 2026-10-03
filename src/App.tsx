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

function MainView(){const v=useAppStore(s=>s.view);if(v==='home')return <HomeView/>;if(v==='content')return <ContentView/>;if(v==='kanban')return <KanbanView/>;if(v==='import')return <ImportView/>;if(v==='calendar')return <CalendarView/>;if(v==='queue')return <QueueView/>;if(v==='activity')return <ActivityView/>;if(v==='help')return <HelpView/>;if(v==='settings')return <SettingsView/>;return <TodayView/>}

export default function App(){
 const {contents,setContents,selectedId,detailOpen}=useAppStore()
 useEffect(()=>{backend.listContents().then(setContents).catch(()=>{})},[setContents])
 const selected=contents.find(c=>c.id===selectedId)
 return <><div className="app-shell"><Sidebar/><div className="center-shell"><TopBar/><main className="main-area"><MainView/></main></div><Inspector item={selected}/></div>{detailOpen&&selected&&<ContentDetail item={selected}/>}</>
}
