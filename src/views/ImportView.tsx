import { open } from '@tauri-apps/plugin-dialog'
import { FolderOpen, ShieldCheck, TriangleAlert } from 'lucide-react'
import { backend } from '../lib/backend'
import { useAppStore } from '../lib/store'
import { useState } from 'react'
import type { ScanResult } from '../types'

export function ImportView() {
  const { setContents, loading, setLoading, setView } = useAppStore()
  const [result,setResult] = useState<ScanResult|null>(null)
  const [error,setError] = useState<string|null>(null)
  const pick = async () => {
    const selected = await open({ directory:true, multiple:false, title:'Selecciona la carpeta de contenido' })
    if (!selected || Array.isArray(selected)) return
    setLoading(true); setError(null)
    try {
      const r = await backend.importFolder(selected)
      setResult(r); setContents(r.contents)
    } catch (e) { setError(String(e)) }
    finally { setLoading(false) }
  }
  return <div className="page scrollable">
    <header className="page-header"><div><span className="eyebrow">INGESTA · MAC / DRIVE SINCRONIZADO</span><h1>Importar carpeta</h1><p>Selecciona una carpeta local o una carpeta de Google Drive visible en Finder. ABRAXAS detecta Reel, imagen y carrusel leyendo medios y TXT.</p></div></header>
    <button className="drop-zone" onClick={pick} disabled={loading}><FolderOpen size={34}/><strong>{loading?'Analizando…':'Seleccionar carpeta'}</strong><span>No se publica nada. Si la carpeta está sincronizada con Drive, funciona como cualquier carpeta del Mac.</span></button>
    {error && <div className="banner error"><TriangleAlert size={17}/>{error}</div>}
    {result && <div className="import-summary">
      <div className="summary-top"><ShieldCheck size={21}/><div><strong>{result.importedCount} contenidos importados</strong><span>{result.rootPath}</span></div></div>
      <div className="summary-metrics"><span><b>{result.importedCount}</b> total</span><span><b>{result.warnings}</b> warnings</span><span><b>{result.errors}</b> errores</span></div>
      <button className="primary-btn wide" onClick={()=>setView('content')}>Ver contenido</button>
    </div>}
  </div>
}
