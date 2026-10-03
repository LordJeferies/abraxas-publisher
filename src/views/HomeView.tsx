import { FolderOpen, CalendarDays, FileCheck2, CircleHelp, HardDrive, ArrowRight } from 'lucide-react'
import { useAppStore } from '../lib/store'

export function HomeView(){
 const {contents,setView,openDetail}=useAppStore()
 const recent=contents.slice(0,4)
 return <div className="page scrollable welcome-page">
   <section className="welcome-hero"><span className="eyebrow">ABRAXAS PUBLISHER · PLANNING & REVIEW</span><h1>Planifica. Revisa. Programa.</h1><p>Importa una semana de contenido, confirma correcciones y deja el calendario listo antes de conectar las redes.</p>
     <div className="welcome-actions"><button className="primary-btn welcome-primary" onClick={()=>setView('import')}><FolderOpen size={17}/> Importar carpeta</button><button className="secondary-btn" onClick={()=>setView('help')}><CircleHelp size={17}/> Cómo usar la app</button></div>
   </section>
   <div className="welcome-grid">
     <button className="welcome-card" onClick={()=>setView('content')}><FileCheck2/><div><strong>Revisar contenido</strong><span>Preview, notas, estados y versiones.</span></div><ArrowRight size={16}/></button>
     <button className="welcome-card" onClick={()=>setView('calendar')}><CalendarDays/><div><strong>Precalendarizar</strong><span>TXT con fecha entra solo; lo demás queda en la bandeja.</span></div><ArrowRight size={16}/></button>
     <button className="welcome-card" onClick={()=>setView('import')}><HardDrive/><div><strong>Carpetas locales o Drive sincronizado</strong><span>Selecciona cualquier carpeta visible en Finder. Drive API directo queda preparado para la fase cloud.</span></div><ArrowRight size={16}/></button>
   </div>
   <section className="panel recent-panel"><div className="panel-title-row"><h3>Recientes</h3><span>{contents.length} contenidos en workspace</span></div>{recent.length?recent.map(c=><button className="recent-content" key={c.id} onClick={()=>openDetail(c.id)}><div><strong>{c.title}</strong><span>{c.client||'Sin cliente'} · {c.contentType} · v{c.version}</span></div><span>{c.status.replaceAll('_',' ')}</span></button>):<div className="empty-state">Todavía no has importado contenido. Empieza con una carpeta semanal.</div>}</section>
 </div>
}
