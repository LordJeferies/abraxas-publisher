const comparison = [
  [
    'Revisar contenido',
    '✓',
    '✓',
  ],
  [
    'Calendario',
    '✓',
    '✓',
  ],
  [
    'Copies y notas',
    '✓',
    '✓',
  ],
  [
    'Preview por red',
    '✓',
    '✓',
  ],
  [
    'Crear jobs',
    '✓',
    '✓',
  ],
  [
    'Trabajar desde móvil',
    '—',
    '✓',
  ],
  [
    'Archivos locales del Mac',
    '✓',
    '—',
  ],
  [
    'ffmpeg / ffprobe',
    '✓',
    '—',
  ],
  [
    'Worker / daemon local',
    '✓',
    '—',
  ],
  [
    'Publicar vía cloud',
    'según provider',
    'según provider',
  ],
  [
    'Delegar a Desktop',
    'recibe',
    'crea tarea',
  ],
]

const scenarios = [
  [
    'Estoy en el móvil y quiero aprobar contenido',
    'Abre la PWA → revisa preview, copy, destino y fecha → aprueba. Si el provider puede publicarse desde Cloud/Web y el asset está disponible, puede ejecutarse sin Desktop. Si requiere el Mac, se crea una tarea WAITING_FOR_DESKTOP.',
  ],

  [
    'El archivo está en Google Drive',
    'Web/PWA puede trabajar con referencias cloud cuando esté configurado OAuth Web. Si el provider admite asset remoto o ABRAXAS Cloud puede transferirlo, no es necesario que el Mac suba manualmente el archivo.',
  ],

  [
    'El archivo sólo existe en mi Mac',
    'Web puede planificar y aprobar, pero la ejecución queda DESKTOP_REQUIRED. Publisher Desktop localizará el asset y ejecutará el job.',
  ],

  [
    'No tengo API de una red',
    'No bloquea Publisher. Ese destino queda MANUAL_REQUIRED y aparece en Hoy/Cola cuando llegue su hora.',
  ],

  [
    'Ya lo programé desde Edits, Studio u otra app',
    'Usa “Ya programado fuera”. El target queda SCHEDULED_EXTERNAL y continúa visible en el calendario y auditoría.',
  ],

  [
    '¿Desktop y PWA son la misma app?',
    'Comparten interfaz, modelo y repositorio. Desktop tiene capacidades nativas adicionales; Web/PWA está orientada a movilidad, revisión, planificación, cloud y delegación.',
  ],

  [
    '¿Cómo se sincronizan?',
    'Los cambios cloud-safe se guardan en ABRAXAS Cloud. Desktop reporta heartbeat, descarga jobs que requieren capacidades locales, ejecuta y devuelve receipts. La PWA ve el resultado actualizado.',
  ],

  [
    '¿Qué pasa sin Internet?',
    'La PWA puede cargar su shell y datos cacheados. Los cambios permanecen pendientes hasta recuperar conexión. Nunca se debe asumir que una publicación remota ocurrió durante el modo offline.',
  ],
]

export function HelpView() {
  return (
    <div className="page scrollable help-v132">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            GUÍA
          </span>

          <h1>
            Cómo usar ABRAXAS Publisher
          </h1>

          <p>
            Desktop y Web/PWA son dos superficies del mismo workspace, con responsabilidades diferentes.
          </p>
        </div>
      </header>

      <section className="panel help-architecture">
        <span className="eyebrow">
          ARQUITECTURA
        </span>

        <h2>
          Un workspace · varios dispositivos
        </h2>

        <div className="architecture-diagram">
          <div>
            <strong>
              Web / PWA
            </strong>

            <span>
              revisar · aprobar · calendarizar · delegar
            </span>
          </div>

          <b>
            ↕
          </b>

          <div>
            <strong>
              ABRAXAS Cloud
            </strong>

            <span>
              workspace · jobs · devices · receipts
            </span>
          </div>

          <b>
            ↕
          </b>

          <div>
            <strong>
              Desktop
            </strong>

            <span>
              archivos · ffmpeg · adapters · ejecución local
            </span>
          </div>
        </div>
      </section>

      <section className="panel">
        <span className="eyebrow">
          DESKTOP VS WEB/PWA
        </span>

        <h2>
          Qué puede hacer cada versión
        </h2>

        <div className="help-comparison">
          <div className="help-comparison-head">
            <b>
              Función
            </b>

            <b>
              Desktop
            </b>

            <b>
              Web/PWA
            </b>
          </div>

          {
            comparison.map(
              ([
                feature,
                desktop,
                web,
              ]) => (
                <div key={feature}>
                  <span>
                    {feature}
                  </span>

                  <b>
                    {desktop}
                  </b>

                  <b>
                    {web}
                  </b>
                </div>
              ),
            )
          }
        </div>
      </section>

      <section className="panel">
        <span className="eyebrow">
          EJECUCIÓN
        </span>

        <h2>
          Cómo decide Publisher dónde ejecutar
        </h2>

        <div className="execution-doc-grid">
          <article>
            <strong>
              CLOUD
            </strong>

            <p>
              API compatible + OAuth web/cloud + asset accesible desde Drive/storage/cloud.
            </p>
          </article>

          <article>
            <strong>
              DESKTOP
            </strong>

            <p>
              El job requiere un archivo local, ffmpeg, Keychain, DaVinci u otra capacidad de macOS.
            </p>
          </article>

          <article>
            <strong>
              MANUAL
            </strong>

            <p>
              No existe integración automática o el usuario decide publicar manualmente.
            </p>
          </article>
        </div>
      </section>

      <section className="panel">
        <span className="eyebrow">
          SINCRONIZACIÓN
        </span>

        <h2>
          Web → Desktop
        </h2>

        <ol className="help-steps">
          <li>
            Modificas o apruebas una publicación desde Web/PWA.
          </li>

          <li>
            El cambio se guarda en ABRAXAS Cloud.
          </li>

          <li>
            Si puede ejecutarse en Cloud, el provider adapter continúa allí.
          </li>

          <li>
            Si necesita el Mac, el job queda WAITING_FOR_DESKTOP.
          </li>

          <li>
            Desktop recibe el job cuando está online.
          </li>

          <li>
            Desktop ejecuta, verifica y genera receipt.
          </li>

          <li>
            Cloud actualiza el workspace y la PWA muestra el resultado.
          </li>
        </ol>
      </section>

      <div className="help-grid">
        {
          scenarios.map(
            ([
              title,
              text,
            ]) => (
              <section
                className="panel help-card"
                key={title}
              >
                <h3>
                  {title}
                </h3>

                <p>
                  {text}
                </p>
              </section>
            ),
          )
        }
      </div>
    </div>
  )
}
