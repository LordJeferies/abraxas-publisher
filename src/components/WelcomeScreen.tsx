import {
  ArrowRight,
  CalendarDays,
  Cloud,
  MonitorSmartphone,
  Sparkles,
} from 'lucide-react'

import '../welcome.css'

export function WelcomeScreen({
  onEnter,
}: {
  onEnter: () => void
}) {
  return (
    <div className="welcome-screen-v2">
      <div className="welcome-orb welcome-orb-a"/>
      <div className="welcome-orb welcome-orb-b"/>

      <section className="welcome-panel-v2">
        <header className="welcome-topline">
          <div className="welcome-brand-lockup">
            <span className="welcome-logo-v2">
              <Sparkles size={18}/>
            </span>

            <div>
              <strong>ABRAXAS</strong>
              <span>Publisher</span>
            </div>
          </div>

          <span className="welcome-version-pill">
            DESKTOP + WEB
          </span>
        </header>

        <div className="welcome-copy-v2">
          <p className="welcome-kicker-v2">
            TU CENTRO DE PUBLICACIÓN
          </p>

          <h1>
            Revisa. Organiza.
            <br/>
            Publica sin perder el control.
          </h1>

          <p>
            Un mismo workspace para contenido, correcciones,
            calendario, cuentas y cola de publicación — desde la Mac o el móvil.
          </p>
        </div>

        <div className="welcome-feature-row-v2">
          <article>
            <span><Cloud size={17}/></span>
            <div>
              <strong>Cloud</strong>
              <small>Sincroniza y continúa desde el móvil.</small>
            </div>
          </article>

          <article>
            <span><CalendarDays size={17}/></span>
            <div>
              <strong>Planifica</strong>
              <small>Revisión, estados, calendario y cola.</small>
            </div>
          </article>

          <article>
            <span><MonitorSmartphone size={17}/></span>
            <div>
              <strong>Desktop + PWA</strong>
              <small>La Mac añade archivos y herramientas nativas.</small>
            </div>
          </article>
        </div>

        <footer className="welcome-actions-v2">
          <button
            className="welcome-primary-v2"
            onClick={onEnter}
          >
            Entrar a Publisher
            <ArrowRight size={16}/>
          </button>

          <p>
            Las tareas largas muestran progreso arriba y siguen en segundo plano.
          </p>
        </footer>
      </section>
    </div>
  )
}
