import type { ContentItem } from '../types'
import { StatusBadge } from './StatusBadge'
import { FileText, Film, Images, Image as ImageIcon, ExternalLink } from 'lucide-react'
import { useAppStore } from '../lib/store'
export function Inspector({ item }: { item?: ContentItem }) {
 const openDetail=useAppStore(s=>s.openDetail)
 if(!item)return <aside className="inspector empty"><div>Selecciona un contenido para ver sus detalles.</div></aside>
 const MediaIcon=item.contentType==='carousel'?Images:item.contentType==='image'?ImageIcon:Film
 return <aside className="inspector">
   <div className="inspector-hero"><MediaIcon size={28}/><div><span>{item.contentType} · v{item.version}</span><strong>{item.title}</strong></div></div>
   <section><h4>Estado editorial</h4><StatusBadge status={item.status}/><div className="validation-line">Validación: <StatusBadge status={item.validationStatus}/></div></section>
   {item.latestNote&&<section><h4>Última corrección</h4><p className="note-preview">{item.latestNote.body}</p></section>}
   <section><h4>Destinos</h4>{item.targets.map(t=><div className="target-row" key={t.id}><span>{t.platform}</span><small>{t.scheduledAt?new Date(t.scheduledAt).toLocaleString():'Sin hora'}</small></div>)}</section>
   <section><h4>Archivos</h4>{item.media.map(m=><div className="file-row" key={m.id}><FileText size={14}/><span>{m.path.split('/').pop()}</span></div>)}</section>
   <button className="primary-btn wide" onClick={()=>openDetail(item.id)}><ExternalLink size={15}/> Abrir ficha</button>
 </aside>
}
