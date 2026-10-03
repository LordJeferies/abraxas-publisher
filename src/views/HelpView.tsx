import { FolderOpen, HardDrive, CalendarDays, MessageSquareText, Columns3, RefreshCcw, ListChecks } from 'lucide-react'
import { useAppStore } from '../lib/store'
const scenarios=[
 ['Tengo una carpeta con toda la semana',FolderOpen,'Importa la carpeta raíz. Cada subcarpeta se convierte en una ficha de contenido.'],
 ['Los archivos están en Google Drive',HardDrive,'En Mac puedes seleccionar una carpeta sincronizada por Google Drive. El adapter Drive API directo está documentado para la capa web/cloud sin duplicar la lógica editorial.'],
 ['Mis TXT ya tienen fecha y hora',CalendarDays,'DATE + TIME precalendariza automáticamente el destino. No significa que la red social ya lo haya aceptado.'],
 ['Hay que corregir un contenido',MessageSquareText,'Abre la ficha, escribe la nota y guarda. Se crea CORRECCION.txt en la carpeta y la ficha pasa a Con corrección.'],
 ['Quiero revisar el estado general',Columns3,'Estados muestra el Kanban informativo. Los estados sólo cambian desde la ficha para evitar movimientos accidentales.'],
 ['Reemplacé un archivo corregido',RefreshCcw,'En la ficha pulsa Actualizar contenido. La app compara hash y fecha, relee metadata y aumenta la versión si detecta cambios.'],
 ['Quiero revisar antes de conectar redes',ListChecks,'Usa Cola → Simular lote. La versión actual no llama APIs sociales.'],
] as const
export function HelpView(){const setView=useAppStore(s=>s.setView);return <div className="page scrollable"><header className="page-header"><div><span className="eyebrow">GUÍA INCORPORADA</span><h1>Cómo usar Publisher</h1><p>Elige el escenario que se parece a lo que necesitas hacer.</p></div></header><div className="help-grid">{scenarios.map(([title,Icon,body])=><article className="help-card" key={title}><Icon size={22}/><h3>{title}</h3><p>{body}</p></article>)}</div><section className="panel help-flow"><h3>Flujo recomendado</h3><div className="flow-row"><span>1 · Importar</span><b>→</b><span>2 · Confirmar / corregir</span><b>→</b><span>3 · Precalendarizar</span><b>→</b><span>4 · Simular</span><b>→</b><span>Paso 2 · conectar redes</span></div><button className="primary-btn" onClick={()=>setView('import')}>Empezar por Importar</button></section></div>}
