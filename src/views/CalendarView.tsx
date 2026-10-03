import { useMemo, useState } from 'react'
import { ChevronLeft, ChevronRight, Inbox, Clock3 } from 'lucide-react'
import { backend } from '../lib/backend'
import { useAppStore } from '../lib/store'

function ymd(d:Date){const y=d.getFullYear();const m=String(d.getMonth()+1).padStart(2,'0');const day=String(d.getDate()).padStart(2,'0');return `${y}-${m}-${day}`}
function mondayOf(date:Date){const d=new Date(date);const day=(d.getDay()+6)%7;d.setHours(12,0,0,0);d.setDate(d.getDate()-day);return d}
function weekDays(anchor:Date){const m=mondayOf(anchor);return Array.from({length:7},(_,i)=>{const d=new Date(m);d.setDate(m.getDate()+i);return d})}

export function CalendarView(){
 const {contents,setContents,openDetail}=useAppStore();const[anchor,setAnchor]=useState(()=>new Date())
 const days=useMemo(()=>weekDays(anchor),[anchor]);const all=contents.flatMap(c=>c.targets.map(t=>({content:c,target:t})))
 const unscheduled=all.filter(x=>!x.target.scheduledAt)
 const refresh=async()=>setContents(await backend.listContents())
 const drop=async(targetId:string,date:string|null)=>{if(!targetId)return;const t=all.find(x=>x.target.id===targetId)?.target;if(!t)return;if(!date){await backend.updateSchedule(targetId,null);await refresh();return}const prior=t.scheduledAt?.slice(11,16)||'10:00';await backend.updateSchedule(targetId,`${date}T${prior}:00`);await refresh()}
 const shift=(n:number)=>{const d=new Date(anchor);d.setDate(d.getDate()+n*7);setAnchor(d)}
 return <div className="page calendar-page"><header className="page-header compact"><div><span className="eyebrow">PRECALENDARIZACIÓN</span><h1>Calendario</h1><p>Arrastra entre días o devuelve un destino a Sin calendarizar.</p></div><div className="calendar-nav"><button className="secondary-btn small" onClick={()=>shift(-1)}><ChevronLeft size={15}/></button><button className="secondary-btn small" onClick={()=>setAnchor(new Date())}>Esta semana</button><button className="secondary-btn small" onClick={()=>shift(1)}><ChevronRight size={15}/></button></div></header>
 <div className="week-label">{days[0].toLocaleDateString(undefined,{day:'numeric',month:'short'})} — {days[6].toLocaleDateString(undefined,{day:'numeric',month:'short',year:'numeric'})}<span className="local-pill">Local · no publicado</span></div>
 <div className="week-grid">{days.map(d=>{const key=ymd(d);const items=all.filter(x=>x.target.scheduledAt?.slice(0,10)===key).sort((a,b)=>String(a.target.scheduledAt).localeCompare(String(b.target.scheduledAt)));return <div className="day-col" key={key} onDragOver={e=>e.preventDefault()} onDrop={e=>drop(e.dataTransfer.getData('targetId'),key)}><div className="day-head"><span>{d.toLocaleDateString(undefined,{weekday:'short'})}</span><strong>{d.getDate()}</strong></div><div className="day-stack">{items.map(x=><button draggable onDragStart={e=>e.dataTransfer.setData('targetId',x.target.id)} className="calendar-item" key={x.target.id} onClick={()=>openDetail(x.content.id)}><span><Clock3 size={12}/>{x.target.scheduledAt?.slice(11,16)}</span><strong>{x.content.title}</strong><small>{x.target.platform} · {x.content.status.replaceAll('_',' ')}</small></button>)}</div></div>})}</div>
 <section className="unscheduled-rail" onDragOver={e=>e.preventDefault()} onDrop={e=>drop(e.dataTransfer.getData('targetId'),null)}><div className="rail-title"><Inbox size={17}/><div><strong>Sin calendarizar</strong><span>{unscheduled.length} destinos todavía sin fecha</span></div></div><div className="unscheduled-list">{unscheduled.map(x=><button draggable onDragStart={e=>e.dataTransfer.setData('targetId',x.target.id)} className="unscheduled-card" key={x.target.id} onClick={()=>openDetail(x.content.id)}><strong>{x.content.title}</strong><span>{x.target.platform}</span></button>)}{!unscheduled.length&&<div className="rail-empty">Todo tiene una fecha local.</div>}</div></section>
 </div>
}
