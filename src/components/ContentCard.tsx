import { Film, Images, Image as ImageIcon, CalendarClock, MessageSquareText, RefreshCcw } from 'lucide-react'
import type { ContentItem } from '../types'
import { StatusBadge } from './StatusBadge'
function Icon({ type }: { type: string }) { if(type==='carousel')return <Images size={30}/>;if(type==='image')return <ImageIcon size={30}/>;return <Film size={30}/> }
export function ContentCard({ item, selected, onSelect }: { item: ContentItem; selected: boolean; onSelect: () => void }) {
 return <button className={selected?'content-card selected':'content-card'} onClick={onSelect}>
   <div className={`thumb thumb-${item.contentType}`}><Icon type={item.contentType}/><span>{item.contentType} · v{item.version}</span></div>
   <div className="content-card-body"><div className="card-title">{item.title}</div><div className="platform-row">{item.targets.map(t=><span key={t.id}>{t.platform.slice(0,2).toUpperCase()}</span>)}</div>
   <div className="card-foot"><StatusBadge status={item.status}/><span className="card-icons">{item.latestNote&&<MessageSquareText size={14}/>} {item.targets.some(t=>t.scheduledAt)&&<CalendarClock size={14}/>}<RefreshCcw size={12}/></span></div></div>
 </button>
}
