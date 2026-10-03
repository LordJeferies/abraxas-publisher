const scenarios = [
  [
    'Tengo una semana completa',
    'Importar → Este Mac o Google Drive → selecciona la carpeta raíz → revisa el preview → resuelve duplicados → confirma.',
  ],
  [
    'Mis TXT ya tienen fecha',
    'Al importar, DATE y TIME crean una precalendarización local. No significa que la red social ya esté programada.',
  ],
  [
    'El contenido necesita cambios',
    'Abre la ficha → cambia a Con corrección → escribe la nota. Publisher crea CORRECCION.txt.',
  ],
  [
    'Reemplacé un archivo',
    'Abre la ficha → Actualizar contenido. Se compara SHA-256, tamaño y modificación; si cambió, aumenta la versión.',
  ],
  [
    'Quiero cambiar la fecha',
    'Calendario → Día/Semana/Mes → arrastra la publicación. Puedes mover todas las redes, una sola o redes seleccionadas.',
  ],
  [
    'Quiero usar varias marcas',
    'Inicio → Marca → Nueva marca. El selector filtra Contenido, Calendario y Kanban.',
  ],
  [
    'Mi contenido está en Drive',
    'Importar → Google Drive → conecta OAuth Desktop → navega hasta la carpeta → Usar esta carpeta.',
  ],
  [
    'Quiero automatizar sin usar la interfaz',
    'Usa publisherctl o publisher-mcp. Ambos trabajan contra el mismo workspace local.',
  ],
]

export function HelpView() {
  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            GUÍA
          </span>

          <h1>
            Cómo usar Publisher
          </h1>

          <p>
            Elige el escenario que se parece a lo que necesitas hacer.
          </p>
        </div>
      </header>

      <div className="help-grid">
        {
          scenarios.map(
            (
              [
                title,
                text,
              ],
            ) => (
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
