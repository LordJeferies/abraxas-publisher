import { convertFileSrc } from '@tauri-apps/api/core'
import { X, RefreshCcw, Save, CalendarClock, FileText, CheckCircle2, AlertTriangle } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import { backend } from '../lib/backend'
import { useAppStore } from '../lib/store'
import type { ContentItem, WorkflowStatus } from '../types'
import { StatusBadge } from './StatusBadge'

const statuses: {value:WorkflowStatus; label:string}[] = [
  {value:'EN_CONFIRMACION',label:'En confirmación'},
  {value:'CON_CORRECCION',label:'Con corrección'},
  {value:'LISTO_POR_PROGRAMAR',label:'Listo / por programar'},
  {value:'PROGRAMADO',label:'Programado'},
]

function Preview({item}:{item:ContentItem}){
  const [index,setIndex]=useState(0)
  useEffect(()=>setIndex(0),[item.id,item.version])
  if(!item.media.length)return <div className="preview-empty">No hay medio para previsualizar.</div>
  const m=item.media[Math.min(index,item.media.length-1)]
  const src=convertFileSrc(m.path)
  return <div className="detail-preview">
    {m.kind==='video'?<video key={`${m.id}-${item.version}`} controls playsInline preload="metadata" src={src}/>:<img key={`${m.id}-${item.version}`} src={src} alt={item.title}/>}
    {item.media.length>1&&<div className="preview-strip">{item.media.map((asset,i)=><button key={asset.id} className={i===index?'preview-dot active':'preview-dot'} onClick={()=>setIndex(i)}>{i+1}</button>)}</div>}
  </div>
}

export function ContentDetail({item}:{item:ContentItem}){
  const {closeDetail,setContents}=useAppStore()
  const [status,setStatus]=useState<WorkflowStatus>(item.status as WorkflowStatus)
  const [note,setNote]=useState('')
  const [message,setMessage]=useState('')
  const [busy,setBusy]=useState(false)
  const [times,setTimes]=useState<Record<string,string>>(()=>Object.fromEntries(item.targets.map(t=>[t.id,t.scheduledAt?.slice(0,16)||''])))
  useEffect(()=>{setStatus(item.status as WorkflowStatus);setTimes(Object.fromEntries(item.targets.map(t=>[t.id,t.scheduledAt?.slice(0,16)||''])));setMessage('')},[item.id,item.version,item.status,item.targets])
  const allScheduled=useMemo(()=>item.targets.length>0&&item.targets.every(t=>times[t.id]),[item.targets,times])
  const refreshAll=async()=>setContents(await backend.listContents())
  const changeStatus=async(v:WorkflowStatus)=>{setBusy(true);setMessage('');try{await backend.updateWorkflowStatus(item.id,v);setStatus(v);await refreshAll();setMessage('Estado actualizado.')}catch(e){setMessage(String(e))}finally{setBusy(false)}}
  const saveNote=async()=>{if(!note.trim())return;setBusy(true);setMessage('');try{const next:WorkflowStatus=status==='PROGRAMADO'?status:'CON_CORRECCION';await backend.saveCorrectionNote(item.id,note,next);setStatus(next);setNote('');await refreshAll();setMessage('Corrección guardada y CORRECCION.txt actualizado en la carpeta.')}catch(e){setMessage(String(e))}finally{setBusy(false)}}
  const refresh=async()=>{setBusy(true);setMessage('');try{const r=await backend.refreshContent(item.id);await refreshAll();setMessage(r.message+` Versión ${r.currentVersion}.`)}catch(e){setMessage(String(e))}finally{setBusy(false)}}
  const saveSchedule=async(targetId:string)=>{setBusy(true);setMessage('');try{const value=times[targetId]||null;await backend.updateSchedule(targetId,value?`${value}:00`:null);await refreshAll();setMessage(value?'Precalendarización actualizada.':'Destino devuelto a Sin calendarizar.')}catch(e){setMessage(String(e))}finally{setBusy(false)}}
  return <div className="detail-backdrop" onMouseDown={e=>{if(e.target===e.currentTarget)closeDetail()}}>
    <section className="detail-sheet" role="dialog" aria-modal="true">
      <header className="detail-head"><div><span className="eyebrow">FICHA DE CONTENIDO · v{item.version}</span><h2>{item.title}</h2><div className="detail-badges"><StatusBadge status={item.status}/><StatusBadge status={item.validationStatus}/></div></div><button className="icon-close" onClick={closeDetail}><X size={20}/></button></header>
      <div className="detail-grid">
        <div className="detail-left"><Preview item={item}/><div className="detail-filemeta"><span>{item.folderPath}</span><button className="secondary-btn small" onClick={refresh} disabled={busy}><RefreshCcw size={14}/> Actualizar contenido</button></div>
          {item.issues.length>0&&<div className="detail-issues"><h4><AlertTriangle size={15}/> Validación</h4>{item.issues.map(i=><div className={`issue ${i.severity}`} key={i.id}>{i.message}</div>)}</div>}
        </div>
        <div className="detail-right">
          <section className="detail-panel"><h3>Estado editorial</h3><p>El Kanban refleja este estado, pero sólo se cambia desde esta ficha.</p><select className="field full-field" value={status} disabled={busy} onChange={e=>changeStatus(e.target.value as WorkflowStatus)}>{statuses.map(s=><option key={s.value} value={s.value} disabled={s.value==='PROGRAMADO'&&!allScheduled}>{s.label}{s.value==='PROGRAMADO'&&!allScheduled?' · requiere fechas':''}</option>)}</select></section>
          <section className="detail-panel"><h3>Corrección / nota</h3>{item.latestNote&&<div className="latest-note"><small>{new Date(item.latestNote.createdAt).toLocaleString()}</small><p>{item.latestNote.body}</p></div>}<textarea className="field note-box" value={note} onChange={e=>setNote(e.target.value)} placeholder="Ej.: cambiar portada, corregir subtítulo en 00:23, reemplazar lámina 3…"/><button className="primary-btn wide" disabled={busy||!note.trim()} onClick={saveNote}><Save size={15}/> Guardar corrección</button><small className="helper">Se crea/actualiza <b>CORRECCION.txt</b> en la misma carpeta, mediante escritura atómica.</small></section>
          <section className="detail-panel"><h3>Precalendarización</h3>{item.targets.map(t=><div className="schedule-edit" key={t.id}><div><strong>{t.platform}</strong><small>{t.account||'Sin cuenta'}</small></div><input className="field" type="datetime-local" value={times[t.id]||''} onChange={e=>setTimes(x=>({...x,[t.id]:e.target.value}))}/><button className="secondary-btn small" onClick={()=>saveSchedule(t.id)} disabled={busy}><CalendarClock size={14}/> Guardar</button></div>)}</section>
          <section className="detail-panel"><h3>Archivos detectados</h3>{item.media.map(m=><div className="asset-row" key={m.id}><FileText size={14}/><div><strong>{m.path.split('/').pop()}</strong><small>{Math.round(m.sizeBytes/1024/1024*10)/10} MB · {m.sha256?.slice(0,10)||'sin hash'}…</small></div></div>)}</section>
          {message&&<div className="detail-message"><CheckCircle2 size={15}/>{message}</div>}
        </div>
      </div>
    </section>
  </div>
}
