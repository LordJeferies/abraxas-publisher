import { Search, Plus, Command, CircleHelp } from 'lucide-react'
import { GlassSurface } from './GlassSurface'
import { useAppStore } from '../lib/store'
export function TopBar(){const setView=useAppStore(s=>s.setView);return <div className="topbar-host"><div className="topbar-bg"/><GlassSurface className="topbar"><button className="search-box search-button" onClick={()=>setView('content')}><Search size={16}/><span>Buscar y revisar contenido…</span><kbd><Command size={11}/>K</kbd></button><button className="ghost-icon-btn" onClick={()=>setView('help')} title="Cómo usar"><CircleHelp size={17}/></button><button className="primary-btn" onClick={()=>setView('import')}><Plus size={16}/> Importar</button></GlassSurface></div>}
