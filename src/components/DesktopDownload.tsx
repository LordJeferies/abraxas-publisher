import {
  Download,
  Laptop,
} from 'lucide-react'

import {
  isTauriRuntime,
} from '../lib/runtime'

const URL =
  'https://github.com/LordJeferies/abraxas-publisher/releases/latest/download/ABRAXAS-Publisher-macOS.zip'

export function DesktopDownload() {
  if (
    isTauriRuntime()
  ) {
    return null
  }

  return (
    <a
      className="desktop-download-card"
      href={URL}
    >
      <Laptop size={22}/>

      <div>
        <strong>
          Descargar ABRAXAS Publisher para Mac
        </strong>

        <span>
          La versión Desktop comparte este mismo workspace y añade archivos locales, ffmpeg y worker nativo.
        </span>
      </div>

      <Download size={18}/>
    </a>
  )
}
