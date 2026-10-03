import {
  convertFileSrc,
} from '@tauri-apps/api/core'

import {
  AlertTriangle,
  CalendarClock,
  CheckCircle2,
  FileText,
  RefreshCcw,
  Save,
  X,
} from 'lucide-react'

import {
  useEffect,
  useMemo,
  useState,
} from 'react'

import {
  backend,
} from '../lib/backend'

import {
  useAppStore,
} from '../lib/store'

import type {
  ContentItem,
  WorkflowStatus,
} from '../types'

import {
  StatusBadge,
} from './StatusBadge'

const statuses: {
  value: WorkflowStatus
  label: string
}[] = [
  {
    value:
      'EN_CONFIRMACION',
    label:
      'En confirmación',
  },
  {
    value:
      'CON_CORRECCION',
    label:
      'Con corrección',
  },
  {
    value:
      'LISTO_POR_PROGRAMAR',
    label:
      'Listo / por programar',
  },
  {
    value:
      'PROGRAMADO',
    label:
      'Programado',
  },
]

function Preview({
  item,
}: {
  item: ContentItem
}) {
  const [
    index,
    setIndex,
  ] =
    useState(0)

  useEffect(
    () =>
      setIndex(0),
    [
      item.id,
      item.version,
    ],
  )

  if (
    !item.media.length
  ) {
    return (
      <div className="preview-empty">
        No hay medio para previsualizar.
      </div>
    )
  }

  const media =
    item.media[
      Math.min(
        index,
        item.media.length - 1,
      )
    ]

  const src =
    convertFileSrc(
      media.path,
    )

  return (
    <div className="detail-preview">
      {
        media.kind
        === 'video'
        ? (
          <video
            key={
              `${media.id}-${item.version}`
            }
            controls
            playsInline
            preload="metadata"
            src={src}
          />
        )
        : (
          <img
            key={
              `${media.id}-${item.version}`
            }
            src={src}
            alt={item.title}
          />
        )
      }

      {
        item.media.length
        > 1
        && (
          <div className="preview-strip">
            {
              item.media.map(
                (
                  asset,
                  i,
                ) => (
                  <button
                    key={asset.id}
                    className={
                      i === index
                        ? 'preview-dot active'
                        : 'preview-dot'
                    }
                    onClick={() =>
                      setIndex(i)
                    }
                  >
                    {i + 1}
                  </button>
                ),
              )
            }
          </div>
        )
      }
    </div>
  )
}

export function ContentDetail({
  item,
}: {
  item: ContentItem
}) {
  const {
    closeDetail,
    setContents,
  } = useAppStore()

  const [
    status,
    setStatus,
  ] =
    useState(item.status)

  const [
    note,
    setNote,
  ] =
    useState('')

  const [
    message,
    setMessage,
  ] =
    useState('')

  const [
    busy,
    setBusy,
  ] =
    useState(false)

  const [
    times,
    setTimes,
  ] =
    useState<
      Record<
        string,
        string
      >
    >(
      () =>
        Object.fromEntries(
          item.targets.map(
            (t) => [
              t.id,
              t.scheduledAt
                ?.slice(
                  0,
                  16,
                )
              || '',
            ],
          ),
        ),
    )

  const [
    chosen,
    setChosen,
  ] =
    useState<string[]>(
      item.targets.map(
        (t) =>
          t.id,
      ),
    )

  useEffect(
    () => {
      setStatus(item.status)

      setTimes(
        Object.fromEntries(
          item.targets.map(
            (t) => [
              t.id,
              t.scheduledAt
                ?.slice(
                  0,
                  16,
                )
              || '',
            ],
          ),
        ),
      )

      setChosen(
        item.targets.map(
          (t) =>
            t.id,
        ),
      )

      setMessage('')
    },
    [
      item.id,
      item.version,
      item.status,
      item.targets,
    ],
  )

  const allScheduled =
    useMemo(
      () =>
        item.targets.length
        > 0
        && item.targets.every(
          (t) =>
            times[t.id],
        ),
      [
        item.targets,
        times,
      ],
    )

  const refreshAll =
    async () => {
      setContents(
        await backend.listContents(),
      )
    }

  const changeStatus =
    async (
      value: WorkflowStatus,
    ) => {
      setBusy(true)
      setMessage('')

      try {
        await backend.updateWorkflowStatus(
          item.id,
          value,
        )

        setStatus(value)

        await refreshAll()

        setMessage(
          'Estado actualizado.',
        )
      } catch (e) {
        setMessage(String(e))
      } finally {
        setBusy(false)
      }
    }

  const saveNote =
    async () => {
      if (!note.trim()) {
        return
      }

      setBusy(true)
      setMessage('')

      try {
        const next =
            status
            === 'PROGRAMADO'
              ? status
              : 'CON_CORRECCION'

        await backend.saveCorrectionNote(
          item.id,
          note,
          next,
        )

        setStatus(next)
        setNote('')

        await refreshAll()

        setMessage(
          item.sourceKind
          === 'drive'
            ? 'Corrección guardada. Si Drive está conectado, CORRECCION.txt también se sincronizó en la carpeta de Drive.'
            : 'Corrección guardada y CORRECCION.txt actualizado.',
        )
      } catch (e) {
        setMessage(String(e))
      } finally {
        setBusy(false)
      }
    }

  const refresh =
    async () => {
      setBusy(true)
      setMessage('')

      try {
        const result =
          await backend.refreshContent(
            item.id,
          )

        await refreshAll()

        setMessage(
          `${result.message} Versión ${result.currentVersion}.`,
        )
      } catch (e) {
        setMessage(String(e))
      } finally {
        setBusy(false)
      }
    }

  const saveOne =
    async (
      targetId: string,
    ) => {
      const target =
        item.targets.find(
          (x) =>
            x.id
            === targetId,
        )

      if (
        !target
      ) {
        return
      }

      if (
        target.status
        === 'SCHEDULED_REMOTE'
        || target.status
        === 'PUBLISHED'
      ) {
        setMessage(
          'Ese destino ya está bloqueado externamente y no puede modificarse sin cancelación remota.',
        )

        return
      }

      setBusy(true)

      try {
        const value =
          times[targetId]
          || null

        await backend.updateSchedule(
          targetId,
          value
            ? `${value}:00`
            : null,
        )

        await refreshAll()

        setMessage(
          value
            ? 'Precalendarización actualizada.'
            : 'Destino devuelto a Sin calendarizar.',
        )
      } catch (e) {
        setMessage(String(e))
      } finally {
        setBusy(false)
      }
    }

  const applyChosen =
    async () => {
      const changes =
        item.targets
          .filter(
            (t) =>
              chosen.includes(
                t.id,
              ),
          )
          .map(
            (target) => ({
              targetId:
                target.id,
              scheduledAt:
                times[
                  target.id
                ]
                  ? `${times[target.id]}:00`
                  : null,
            }),
          )

      if (
        !changes.length
      ) {
        return
      }

      setBusy(true)

      try {
        await backend.updateSchedules(
          changes,
        )

        await refreshAll()

        setMessage(
          'Cambios aplicados a las redes seleccionadas.',
        )
      } catch (e) {
        setMessage(String(e))
      } finally {
        setBusy(false)
      }
    }

  return (
    <div
      className="detail-backdrop"
      onMouseDown={(e) => {
        if (
          e.target
          === e.currentTarget
        ) {
          closeDetail()
        }
      }}
    >
      <section
        className="detail-sheet"
        role="dialog"
        aria-modal="true"
      >
        <header className="detail-head">
          <div>
            <span className="eyebrow">
              FICHA DE CONTENIDO · v{
                item.version
              }
            </span>

            <h2>
              {item.title}
            </h2>

            <div className="detail-badges">
              <StatusBadge
                status={
                  item.status
                }
              />

              <StatusBadge
                status={
                  item.validationStatus
                }
              />
            </div>
          </div>

          <button
            className="icon-close"
            onClick={
              closeDetail
            }
          >
            <X size={20}/>
          </button>
        </header>

        <div className="detail-grid">
          <div className="detail-left">
            <Preview item={item}/>

            <div className="detail-filemeta">
              <div>
                <span>
                  {
                    item.sourceKind
                  }
                </span>

                <small>
                  {
                    item.folderPath
                  }
                </small>
              </div>

              <button
                className="secondary-btn small"
                onClick={
                  refresh
                }
                disabled={busy}
              >
                <RefreshCcw size={14}/>
                Actualizar contenido
              </button>
            </div>

            {
              item.issues.length
              > 0
              && (
                <div className="detail-issues">
                  <h4>
                    <AlertTriangle size={15}/>
                    Validación
                  </h4>

                  {
                    item.issues.map(
                      (issue) => (
                        <div
                          className={
                            `issue ${issue.severity}`
                          }
                          key={issue.id}
                        >
                          {issue.message}
                        </div>
                      ),
                    )
                  }
                </div>
              )
            }
          </div>

          <div className="detail-right">
            <section className="detail-panel">
              <h3>
                Estado editorial
              </h3>

              <p>
                El Kanban sólo refleja este valor. El estado se cambia aquí.
              </p>

              <select
                className="field full-field"
                value={status}
                disabled={busy}
                onChange={(e) =>
                  changeStatus(
                    e.target.value,
                  )
                }
              >
                {
                  statuses.map(
                    (s) => (
                      <option
                        key={
                          s.value
                        }
                        value={
                          s.value
                        }
                        disabled={
                          s.value
                          === 'PROGRAMADO'
                          && !allScheduled
                        }
                      >
                        {s.label}
                        {
                          s.value
                          === 'PROGRAMADO'
                          && !allScheduled
                            ? ' · requiere fechas'
                            : ''
                        }
                      </option>
                    ),
                  )
                }
              </select>
            </section>

            <section className="detail-panel">
              <h3>
                Corrección / nota
              </h3>

              {
                item.latestNote
                && (
                  <div className="latest-note">
                    <small>
                      {
                        new Date(
                          item.latestNote.createdAt,
                        ).toLocaleString()
                      }
                    </small>

                    <p>
                      {
                        item.latestNote.body
                      }
                    </p>
                  </div>
                )
              }

              <textarea
                className="field note-box"
                value={note}
                onChange={(e) =>
                  setNote(
                    e.target.value,
                  )
                }
                placeholder="Ej.: cambiar portada, corregir subtítulo en 00:23, reemplazar lámina 3…"
              />

              <button
                className="primary-btn wide"
                disabled={
                  busy
                  || !note.trim()
                }
                onClick={
                  saveNote
                }
              >
                <Save size={15}/>
                Guardar corrección
              </button>
            </section>

            <section className="detail-panel">
              <div className="panel-title-row">
                <div>
                  <h3>
                    Precalendarización por red
                  </h3>

                  <p>
                    Puedes cambiar una red o varias a la vez.
                  </p>
                </div>

                <button
                  className="secondary-btn small"
                  onClick={() =>
                    setChosen(
                      item.targets.map(
                        (x) =>
                          x.id,
                      ),
                    )
                  }
                >
                  Seleccionar todas
                </button>
              </div>

              {
                item.targets.map(
                  (target) => {
                    const isLocked =
                      target.status
                      === 'SCHEDULED_REMOTE'
                      || target.status
                      === 'PUBLISHED'

                    return (
                      <div
                        className={
                          isLocked
                            ? 'schedule-edit locked'
                            : 'schedule-edit'
                        }
                        key={
                          target.id
                        }
                      >
                        <label className="schedule-check">
                          <input
                            type="checkbox"
                            checked={
                              chosen.includes(
                                target.id,
                              )
                            }
                            disabled={
                              isLocked
                            }
                            onChange={(e) =>
                              setChosen(
                                (prev) =>
                                  e.target.checked
                                    ? [
                                        ...prev,
                                        target.id,
                                      ]
                                    : prev.filter(
                                        (x) =>
                                          x
                                          !== target.id,
                                      ),
                              )
                            }
                          />

                          <span>
                            <strong>
                              {
                                target.platform
                              }
                            </strong>

                            <small>
                              {
                                target.account
                                || 'Sin cuenta'
                              }
                              {
                                isLocked
                                  ? ' · 🔒 remoto'
                                  : ''
                              }
                            </small>
                          </span>
                        </label>

                        <input
                          className="field"
                          type="datetime-local"
                          disabled={
                            isLocked
                          }
                          value={
                            times[
                              target.id
                            ]
                            || ''
                          }
                          onChange={(e) =>
                            setTimes(
                              (prev) => ({
                                ...prev,
                                [
                                  target.id
                                ]:
                                  e.target.value,
                              }),
                            )
                          }
                        />

                        <button
                          className="secondary-btn small"
                          disabled={
                            busy
                            || isLocked
                          }
                          onClick={() =>
                            saveOne(
                              target.id,
                            )
                          }
                        >
                          <CalendarClock size={14}/>
                          Guardar
                        </button>
                      </div>
                    )
                  },
                )
              }

              <button
                className="primary-btn wide"
                disabled={
                  busy
                  || !chosen.length
                }
                onClick={
                  applyChosen
                }
              >
                Aplicar a redes seleccionadas
              </button>
            </section>

            <section className="detail-panel">
              <h3>
                Archivos detectados
              </h3>

              {
                item.media.map(
                  (media) => (
                    <div
                      className="asset-row"
                      key={media.id}
                    >
                      <FileText size={14}/>

                      <div>
                        <strong>
                          {
                            media.path
                              .split('/')
                              .pop()
                          }
                        </strong>

                        <small>
                          {
                            Math.round(
                              media.sizeBytes
                              / 1024
                              / 1024
                              * 10,
                            )
                            / 10
                          } MB
                          {' · '}
                          {
                            media.sha256
                              ?.slice(
                                0,
                                10,
                              )
                            || 'sin hash'
                          }…
                        </small>
                      </div>
                    </div>
                  ),
                )
              }
            </section>

            {
              message
              && (
                <div className="detail-message">
                  <CheckCircle2 size={15}/>
                  {message}
                </div>
              )
            }
          </div>
        </div>
      </section>
    </div>
  )
}
