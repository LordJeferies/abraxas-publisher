import {
  CalendarDays,
  Cloud,
  MonitorSmartphone,
  Sparkles,
} from 'lucide-react'

export function WelcomeScreen({
  onEnter,
}: {
  onEnter: () => void
}) {
  return (
    <div className="welcome-screen">
      <div className="welcome-card">
        <div className="welcome-mark">
          <Sparkles size={24}/>
        </div>

        <p className="welcome-eyebrow">
          ABRAXAS PUBLISHER
        </p>

        <h1>
          Tu centro para revisar, organizar y publicar contenido.
        </h1>

        <p className="welcome-lead">
          Mac y Web comparten el mismo espacio. Puedes seguir trabajando mientras las tareas largas avanzan en segundo plano.
        </p>

        <div className="welcome-feature-grid">
          <article>
            <Cloud size={18}/>
            <strong>Cloud</strong>
            <span>Sincronización y trabajo desde el móvil.</span>
          </article>

          <article>
            <CalendarDays size={18}/>
            <strong>Planificación</strong>
            <span>Revisión, estados, calendario y cola.</span>
          </article>

          <article>
            <MonitorSmartphone size={18}/>
            <strong>Desktop + PWA</strong>
            <span>La Mac añade archivos locales y herramientas nativas.</span>
          </article>
        </div>

        <button
          className="welcome-enter-button"
          onClick={onEnter}
        >
          Entrar a Publisher
        </button>

        <small>
          Las operaciones largas muestran progreso arriba. Sólo se bloqueará la interfaz cuando sea estrictamente necesario.
        </small>
      </div>
    </div>
  )
}
