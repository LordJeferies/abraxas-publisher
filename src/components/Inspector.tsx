import type {
  ContentItem,
  InspectorMode,
} from '../types'

import {
  Dock,
  ExternalLink,
  FileText,
  PanelRightClose,
  PictureInPicture2,
} from 'lucide-react'

import { useAppStore } from '../lib/store'
import { StatusBadge } from './StatusBadge'

export function Inspector({
  items,
  mode,
}: {
  items: ContentItem[]
  mode: InspectorMode
}) {
  const {
    openDetail,
    setInspectorMode,
    clearSelection,
  } = useAppStore()

  if (!items.length) {
    return null
  }

  if (items.length > 1) {
    return (
      <aside
        className={
          mode === 'floating'
            ? 'inspector floating'
            : 'inspector'
        }
      >
        <div className="inspector-tools">
          <strong>
            {items.length} seleccionados
          </strong>

          <div>
            <button
              onClick={() =>
                setInspectorMode('docked')
              }
              title="Acoplar"
            >
              <Dock size={14}/>
            </button>

            <button
              onClick={() =>
                setInspectorMode('floating')
              }
              title="Flotante"
            >
              <PictureInPicture2 size={14}/>
            </button>

            <button
              onClick={() =>
                setInspectorMode('hidden')
              }
              title="Ocultar"
            >
              <PanelRightClose size={14}/>
            </button>
          </div>
        </div>

        <section>
          <h4>
            Selección múltiple
          </h4>

          {
            items.map((item) => (
              <button
                className="multi-inspector-row"
                key={item.id}
                onClick={() =>
                  openDetail(item.id)
                }
              >
                <span>
                  {item.title}
                </span>

                <small>
                  {item.client || 'Sin marca'}
                </small>
              </button>
            ))
          }
        </section>

        <button
          className="secondary-btn wide"
          onClick={clearSelection}
        >
          Limpiar selección
        </button>
      </aside>
    )
  }

  const item = items[0]

  return (
    <aside
      className={
        mode === 'floating'
          ? 'inspector floating'
          : 'inspector'
      }
    >
      <div className="inspector-tools">
        <span>
          Detalles
        </span>

        <div>
          <button
            className={
              mode === 'docked'
                ? 'active'
                : ''
            }
            onClick={() =>
              setInspectorMode('docked')
            }
            title="Acoplar"
          >
            <Dock size={14}/>
          </button>

          <button
            className={
              mode === 'floating'
                ? 'active'
                : ''
            }
            onClick={() =>
              setInspectorMode('floating')
            }
            title="Flotante"
          >
            <PictureInPicture2 size={14}/>
          </button>

          <button
            onClick={() =>
              setInspectorMode('hidden')
            }
            title="Ocultar"
          >
            <PanelRightClose size={14}/>
          </button>
        </div>
      </div>

      <div className="inspector-hero">
        <div>
          <span>
            {item.contentType}
            {' · '}
            v{item.version}
          </span>

          <strong>
            {item.title}
          </strong>

          <small>
            {item.client || 'Sin marca'}
          </small>
        </div>
      </div>

      <section>
        <h4>
          Estado editorial
        </h4>

        <StatusBadge
          status={item.status}
        />

        <div className="validation-line">
          Validación:{' '}
          <StatusBadge
            status={item.validationStatus}
          />
        </div>
      </section>

      {
        item.latestNote
        && (
          <section>
            <h4>
              Última corrección
            </h4>

            <p className="note-preview">
              {item.latestNote.body}
            </p>
          </section>
        )
      }

      <section>
        <h4>
          Origen
        </h4>

        <div className="source-chip">
          {item.sourceKind}
        </div>
      </section>

      <section>
        <h4>
          Destinos
        </h4>

        {
          item.targets.map((t) => (
            <div
              className="target-row"
              key={t.id}
            >
              <span>
                {t.platform}
              </span>

              <small>
                {
                  t.scheduledAt
                    ? new Date(
                        t.scheduledAt,
                      ).toLocaleString()
                    : 'Sin hora'
                }
              </small>
            </div>
          ))
        }
      </section>

      <section>
        <h4>
          Archivos
        </h4>

        {
          item.media.map((m) => (
            <div
              className="file-row"
              key={m.id}
            >
              <FileText size={14}/>

              <span>
                {
                  m.path
                    .split('/')
                    .pop()
                }
              </span>
            </div>
          ))
        }
      </section>

      <button
        className="primary-btn wide"
        onClick={() =>
          openDetail(item.id)
        }
      >
        <ExternalLink size={15}/>
        Abrir ficha
      </button>
    </aside>
  )
}
