import { useAppStore } from '../lib/store'
import type { WorkflowStatus } from '../types'
import { StatusBadge } from '../components/StatusBadge'
const columns:{id:WorkflowStatus;title:string;hint:string}[]=[
 {id:'EN_CONFIRMACION',title:'En confirmación',hint:'Pendiente de validar editorialmente'},
 {id:'CON_CORRECCION',title:'Con corrección',hint:'Tiene cambios solicitados'},
 {id:'LISTO_POR_PROGRAMAR',title:'Listo / por programar',hint:'Aprobado, falta cerrar programación'},
 {id:'PROGRAMADO',title:'Programado',hint:'Cerrado en el flujo editorial'},
]
export function KanbanView(){const {contents,openDetail}=useAppStore();return <div className="page kanban-page"><header className="page-header compact"><div><span className="eyebrow">ESTADOS EDITORIALES</span><h1>Kanban</h1><p>Vista informativa. Para cambiar un estado, abre la ficha.</p></div></header><div className="kanban-grid">{columns.map(col=>{const items=contents.filter(c=>c.status===col.id);return <section className="kanban-column" key={col.id}><div className="kanban-head"><div><h3>{col.title}</h3><span>{col.hint}</span></div><b>{items.length}</b></div><div className="kanban-stack">{items.map(c=><button className="kanban-card" key={c.id} onClick={()=>openDetail(c.id)}><div className="kanban-card-top"><strong>{c.title}</strong><span>v{c.version}</span></div><small>{c.client||'Sin cliente'} · {c.contentType}</small><div className="kanban-meta"><StatusBadge status={c.validationStatus}/>{c.latestNote&&<span>nota</span>}</div></button>)}{!items.length&&<div className="kanban-empty">Sin contenidos</div>}</div></section>})}</div></div>}
