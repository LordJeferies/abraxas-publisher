import {
  useMemo,
  useState,
} from 'react'

import type {
  Dispatch,
  SetStateAction,
} from 'react'

import {
  DndContext,
  DragEndEvent,
  useDraggable,
  useDroppable,
} from '@dnd-kit/core'

import {
  CSS,
} from '@dnd-kit/utilities'

import {
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  Clock3,
  Inbox,
  Search,
  X,
} from 'lucide-react'

import {
  backend,
} from '../lib/backend'

import {
  useAppStore,
} from '../lib/store'

import type {
  ContentItem,
  PublicationTarget,
} from '../types'

type CalendarMode =
  | 'day'
  | 'week'
  | 'month'

const CALENDAR_MODES: CalendarMode[] = [
  'day',
  'week',
  'month',
]

type PendingMove = {
  contentId: string
  targetId: string
  date: string | null
}

function ymd(
  date: Date,
) {
  const y =
    date.getFullYear()

  const m =
    String(
      date.getMonth() + 1,
    ).padStart(
      2,
      '0',
    )

  const d =
    String(
      date.getDate(),
    ).padStart(
      2,
      '0',
    )

  return `${y}-${m}-${d}`
}

function mondayOf(
  date: Date,
) {
  const d =
    new Date(date)

  const delta =
    (d.getDay() + 6)
    % 7

  d.setHours(
    12,
    0,
    0,
    0,
  )

  d.setDate(
    d.getDate()
    - delta,
  )

  return d
}

function addDays(
  date: Date,
  days: number,
) {
  const d =
    new Date(date)

  d.setDate(
    d.getDate() + days,
  )

  return d
}

function weekDays(
  anchor: Date,
) {
  const start =
    mondayOf(anchor)

  return Array.from(
    {
      length: 7,
    },
    (_, i) =>
      addDays(
        start,
        i,
      ),
  )
}

function monthDays(
  anchor: Date,
) {
  const first =
    new Date(
      anchor.getFullYear(),
      anchor.getMonth(),
      1,
      12,
    )

  const start =
    mondayOf(first)

  return Array.from(
    {
      length: 42,
    },
    (_, i) =>
      addDays(
        start,
        i,
      ),
  )
}

function locked(
  target: PublicationTarget,
) {
  return (
    target.status
    === 'SCHEDULED_REMOTE'
    || target.status
    === 'PUBLISHED'
  )
}

function scheduleForDate(
  target: PublicationTarget,
  date: string | null,
) {
  if (!date) {
    return null
  }

  const previousTime =
    target.scheduledAt
      ?.slice(
        11,
        19,
      )
    || '10:00:00'

  return (
    `${date}T${previousTime}`
  )
}

function DraggableTarget({
  item,
  target,
  openDetail,
}: {
  item: ContentItem
  target: PublicationTarget
  openDetail: (id: string) => void
}) {
  const isLocked =
    locked(target)

  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    isDragging,
  } = useDraggable({
    id: target.id,
    disabled: isLocked,
    data: {
      contentId: item.id,
    },
  })

  const style = {
    transform:
      CSS.Transform.toString(
        transform,
      ),
    opacity:
      isDragging
        ? .4
        : 1,
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={
        isLocked
          ? 'calendar-item locked'
          : 'calendar-item'
      }
      {...attributes}
      {...listeners}
      onDoubleClick={() =>
        openDetail(item.id)
      }
    >
      <span className="calendar-time">
        {
          isLocked
          && '🔒 '
        }

        <Clock3 size={11}/>

        {
          target.scheduledAt
            ?.slice(
              11,
              16,
            )
          || 'Sin hora'
        }
      </span>

      <strong>
        {item.title}
      </strong>

      <small>
        {target.platform}
        {' · '}
        {
          item.client
          || 'Sin marca'
        }
      </small>
    </div>
  )
}

function DropZone({
  id,
  className,
  children,
}: {
  id: string
  className: string
  children: React.ReactNode
}) {
  const {
    setNodeRef,
    isOver,
  } = useDroppable({
    id,
  })

  return (
    <div
      ref={setNodeRef}
      className={
        `${className}${
          isOver
            ? ' drop-over'
            : ''
        }`
      }
    >
      {children}
    </div>
  )
}


function MovePublicationModal({
  pending,
  contents,
  moveScope,
  setMoveScope,
  selectedPlatforms,
  setSelectedPlatforms,
  onCancel,
  onApply,
}: {
  pending: PendingMove
  contents: ContentItem[]
  moveScope: 'all' | 'one' | 'selected'
  setMoveScope: (
    value: 'all' | 'one' | 'selected'
  ) => void
  selectedPlatforms: string[]
  setSelectedPlatforms: Dispatch<
    SetStateAction<string[]>
  >
  onCancel: () => void
  onApply: () => void
}) {
  const content = contents.find(
    (item) => item.id === pending.contentId,
  )

  const dragged = content?.targets.find(
    (target) => target.id === pending.targetId,
  )

  if (!content || !dragged) {
    return null
  }

  return (
    <div className="modal-backdrop">
      <section className="move-modal">
        <span className="eyebrow">
          MOVER PUBLICACIÓN
        </span>

        <h3>{content.title}</h3>

        <p>
          {pending.date
            ? `Nueva fecha: ${pending.date}`
            : 'Quitar fecha y devolver a Sin calendarizar'}
        </p>

        <label className="radio-row">
          <input
            type="radio"
            checked={moveScope === 'all'}
            onChange={() => setMoveScope('all')}
          />
          Todas las redes
        </label>

        <label className="radio-row">
          <input
            type="radio"
            checked={moveScope === 'one'}
            onChange={() => setMoveScope('one')}
          />
          Sólo {dragged.platform}
        </label>

        <label className="radio-row">
          <input
            type="radio"
            checked={moveScope === 'selected'}
            onChange={() => setMoveScope('selected')}
          />
          Elegir redes
        </label>

        {moveScope === 'selected' && (
          <div className="platform-checks">
            {content.targets.map((target) => (
              <label key={target.id}>
                <input
                  type="checkbox"
                  checked={selectedPlatforms.includes(
                    target.platform,
                  )}
                  onChange={(event) => {
                    setSelectedPlatforms((previous) => {
                      if (event.target.checked) {
                        return Array.from(
                          new Set([
                            ...previous,
                            target.platform,
                          ]),
                        )
                      }

                      return previous.filter(
                        (platform) =>
                          platform !== target.platform,
                      )
                    })
                  }}
                />

                {target.platform}
                {locked(target) ? ' 🔒' : ''}
              </label>
            ))}
          </div>
        )}

        <div className="modal-actions">
          <button
            className="secondary-btn"
            onClick={onCancel}
          >
            Cancelar
          </button>

          <button
            className="primary-btn"
            onClick={onApply}
          >
            Confirmar cambio
          </button>
        </div>
      </section>
    </div>
  )
}

export function CalendarView() {
  const {
    contents,
    setContents,
    openDetail,
    selectedBrand,
  } = useAppStore()

  const [
    anchor,
    setAnchor,
  ] =
    useState(
      () => new Date(),
    )

  const [
    mode,
    setMode,
  ] =
    useState<CalendarMode>(
      'week',
    )

  const [
    pending,
    setPending,
  ] =
    useState<PendingMove | null>(
      null,
    )

  const [
    moveScope,
    setMoveScope,
  ] =
    useState<
      'all'
      | 'one'
      | 'selected'
    >(
      'all',
    )

  const [
    selectedPlatforms,
    setSelectedPlatforms,
  ] =
    useState<string[]>([])

  const [
    query,
    setQuery,
  ] =
    useState('')

  const [
    platformFilter,
    setPlatformFilter,
  ] =
    useState('ALL')

  const [
    typeFilter,
    setTypeFilter,
  ] =
    useState('ALL')

  const [
    statusFilter,
    setStatusFilter,
  ] =
    useState('ALL')

  const [
    message,
    setMessage,
  ] =
    useState('')

  const visibleContents =
    useMemo(
      () =>
        contents.filter(
          (content) =>
            selectedBrand
            === 'ALL'
            || content.client
            === selectedBrand,
        ),
      [
        contents,
        selectedBrand,
      ],
    )

  const all =
    useMemo(
      () =>
        visibleContents
          .flatMap(
            (content) =>
              content.targets
                .map(
                  (target) => ({
                    content,
                    target,
                  }),
                ),
          ),
      [
        visibleContents,
      ],
    )

  const unscheduled =
    useMemo(
      () =>
        all.filter(
          ({
            content,
            target,
          }) => {
            if (
              target.scheduledAt
            ) {
              return false
            }

            if (
              platformFilter
              !== 'ALL'
              && target.platform
              !== platformFilter
            ) {
              return false
            }

            if (
              typeFilter
              !== 'ALL'
              && content.contentType
              !== typeFilter
            ) {
              return false
            }

            if (
              statusFilter
              !== 'ALL'
              && content.status
              !== statusFilter
            ) {
              return false
            }

            const haystack =
              [
                content.title,
                content.client,
                content.contentType,
                target.platform,
              ]
                .join(' ')
                .toLowerCase()

            return haystack.includes(
              query
                .trim()
                .toLowerCase(),
            )
          },
        ),
      [
        all,
        query,
        platformFilter,
        typeFilter,
        statusFilter,
      ],
    )

  const refresh =
    async () => {
      setContents(
        await backend.listContents(),
      )
    }

  const requestMove =
    (
      targetId: string,
      date: string | null,
    ) => {
      const entry =
        all.find(
          (x) =>
            x.target.id
            === targetId,
        )

      if (!entry) {
        return
      }

      if (
        locked(
          entry.target,
        )
      ) {
        setMessage(
          'Esta publicación ya está programada o publicada externamente. Primero debes cancelarla mediante su provider.',
        )

        return
      }

      setMoveScope(
        'all',
      )

      setSelectedPlatforms(
        entry.content.targets.map(
          (t) =>
            t.platform,
        ),
      )

      setPending({
        contentId:
          entry.content.id,
        targetId,
        date,
      })
    }

  const onDragEnd =
    (
      event: DragEndEvent,
    ) => {
      const targetId =
        String(
          event.active.id,
        )

      const overId =
        event.over
          ? String(
              event.over.id,
            )
          : ''

      if (!overId) {
        return
      }

      if (
        overId
        === 'unscheduled'
      ) {
        requestMove(
          targetId,
          null,
        )

        return
      }

      if (
        overId.startsWith(
          'date:',
        )
      ) {
        requestMove(
          targetId,
          overId.slice(5),
        )
      }
    }

  const applyMove =
    async () => {
      if (!pending) {
        return
      }

      const content =
        visibleContents.find(
          (c) =>
            c.id
            === pending.contentId,
        )

      if (!content) {
        return
      }

      const dragged =
        content.targets.find(
          (t) =>
            t.id
            === pending.targetId,
        )

      if (!dragged) {
        return
      }

      let targets:
        PublicationTarget[]

      if (
        moveScope === 'one'
      ) {
        targets = [dragged]
      } else if (
        moveScope
        === 'selected'
      ) {
        targets =
          content.targets
            .filter(
              (target) =>
                selectedPlatforms
                  .includes(
                    target.platform,
                  ),
            )
      } else {
        targets =
          content.targets
      }

      const blocked =
        targets.filter(
          locked,
        )

      if (
        blocked.length
      ) {
        setMessage(
          `No se movió nada. ${
            blocked.map(
              (x) =>
                x.platform,
            ).join(', ')
          } ya está bloqueado por programación remota.`,
        )

        setPending(null)
        return
      }

      await backend.updateSchedules(
        targets.map(
          (target) => ({
            targetId:
              target.id,
            scheduledAt:
              scheduleForDate(
                target,
                pending.date,
              ),
          }),
        ),
      )

      await refresh()

      setPending(null)

      setMessage(
        pending.date
          ? 'Fecha de precalendarización actualizada.'
          : 'Destino devuelto a Sin calendarizar.',
      )
    }

  const shift =
    (
      direction: number,
    ) => {
      const d =
        new Date(anchor)

      if (
        mode === 'day'
      ) {
        d.setDate(
          d.getDate()
          + direction,
        )
      } else if (
        mode === 'week'
      ) {
        d.setDate(
          d.getDate()
          + direction * 7,
        )
      } else {
        d.setMonth(
          d.getMonth()
          + direction,
        )
      }

      setAnchor(d)
    }

  const renderItemsForDate =
    (
      date: Date,
    ) => {
      const key =
        ymd(date)

      return all
        .filter(
          (x) =>
            x.target
              .scheduledAt
              ?.slice(
                0,
                10,
              )
            === key,
        )
        .sort(
          (a, b) =>
            String(
              a.target
                .scheduledAt,
            )
              .localeCompare(
                String(
                  b.target
                    .scheduledAt,
                ),
              ),
        )
        .map(
          ({
            content,
            target,
          }) => (
            <DraggableTarget
              key={target.id}
              item={content}
              target={target}
              openDetail={
                openDetail
              }
            />
          ),
        )
    }

  const week =
    weekDays(anchor)

  const month =
    monthDays(anchor)

  const currentMonth =
    anchor.getMonth()

  const platforms =
    Array.from(
      new Set(
        all.map(
          (x) =>
            x.target.platform,
        ),
      ),
    ).sort()

  const types =
    Array.from(
      new Set(
        visibleContents.map(
          (x) =>
            x.contentType,
        ),
      ),
    ).sort()

  return (
    <DndContext
      onDragEnd={
        onDragEnd
      }
    >
      <div className="page calendar-page">
        <header className="page-header compact">
          <div>
            <span className="eyebrow">
              PRECALENDARIZACIÓN
            </span>

            <h1>
              Calendario
            </h1>

            <p>
              Cada red tiene su propia fecha. Mueve todas, una o una selección.
            </p>
          </div>

          <div className="calendar-toolbar">
            <div className="segmented-control">
              {
                CALENDAR_MODES.map(
                  (value) => (
                    <button
                      key={value}
                      className={
                        mode
                        === value
                          ? 'active'
                          : ''
                      }
                      onClick={() =>
                        setMode(
                          value,
                        )
                      }
                    >
                      {
                        value === 'day'
                          ? 'Día'
                          : value
                            === 'week'
                            ? 'Semana'
                            : 'Mes'
                      }
                    </button>
                  ),
                )
              }
            </div>

            <button
              className="secondary-btn small"
              onClick={() =>
                shift(-1)
              }
            >
              <ChevronLeft size={15}/>
            </button>

            <button
              className="secondary-btn small"
              onClick={() =>
                setAnchor(
                  new Date(),
                )
              }
            >
              Hoy
            </button>

            <button
              className="secondary-btn small"
              onClick={() =>
                shift(1)
              }
            >
              <ChevronRight size={15}/>
            </button>
          </div>
        </header>

        {
          message
          && (
            <div className="calendar-message">
              <span>
                {message}
              </span>

              <button
                onClick={() =>
                  setMessage('')
                }
              >
                <X size={14}/>
              </button>
            </div>
          )
        }

        {
          mode === 'day'
          && (
            <div className="day-view">
              <DropZone
                id={
                  `date:${ymd(anchor)}`
                }
                className="day-view-drop"
              >
                <header>
                  <CalendarDays size={18}/>

                  <div>
                    <strong>
                      {
                        anchor.toLocaleDateString(
                          undefined,
                          {
                            weekday:
                              'long',
                            day:
                              'numeric',
                            month:
                              'long',
                            year:
                              'numeric',
                          },
                        )
                      }
                    </strong>
                  </div>
                </header>

                <div className="day-view-items">
                  {
                    renderItemsForDate(
                      anchor,
                    )
                  }
                </div>
              </DropZone>
            </div>
          )
        }

        {
          mode === 'week'
          && (
            <div className="week-grid">
              {
                week.map(
                  (date) => {
                    const key =
                      ymd(date)

                    return (
                      <DropZone
                        key={key}
                        id={
                          `date:${key}`
                        }
                        className="day-col"
                      >
                        <div className="day-head">
                          <span>
                            {
                              date.toLocaleDateString(
                                undefined,
                                {
                                  weekday:
                                    'short',
                                },
                              )
                            }
                          </span>

                          <strong>
                            {
                              date.getDate()
                            }
                          </strong>
                        </div>

                        <div className="day-stack">
                          {
                            renderItemsForDate(
                              date,
                            )
                          }
                        </div>
                      </DropZone>
                    )
                  },
                )
              }
            </div>
          )
        }

        {
          mode === 'month'
          && (
            <div className="month-grid">
              {
                month.map(
                  (date) => {
                    const key =
                      ymd(date)

                    return (
                      <DropZone
                        key={key}
                        id={
                          `date:${key}`
                        }
                        className={
                          date.getMonth()
                          === currentMonth
                            ? 'month-cell'
                            : 'month-cell outside'
                        }
                      >
                        <header>
                          <strong>
                            {
                              date.getDate()
                            }
                          </strong>
                        </header>

                        <div className="month-items">
                          {
                            renderItemsForDate(
                              date,
                            )
                          }
                        </div>
                      </DropZone>
                    )
                  },
                )
              }
            </div>
          )
        }

        <DropZone
          id="unscheduled"
          className="unscheduled-rail"
        >
          <div className="rail-title">
            <Inbox size={17}/>

            <div>
              <strong>
                Sin calendarizar
              </strong>

              <span>
                {
                  unscheduled.length
                } destinos visibles
              </span>
            </div>
          </div>

          <div className="rail-controls">
            <label className="rail-search">
              <Search size={14}/>

              <input
                value={query}
                onChange={(e) =>
                  setQuery(
                    e.target.value,
                  )
                }
                placeholder="Buscar contenido…"
              />
            </label>

            <select
              className="field"
              value={platformFilter}
              onChange={(e) =>
                setPlatformFilter(
                  e.target.value,
                )
              }
            >
              <option value="ALL">
                Todas las redes
              </option>

              {
                platforms.map(
                  (p) => (
                    <option
                      key={p}
                      value={p}
                    >
                      {p}
                    </option>
                  ),
                )
              }
            </select>

            <select
              className="field"
              value={typeFilter}
              onChange={(e) =>
                setTypeFilter(
                  e.target.value,
                )
              }
            >
              <option value="ALL">
                Todos los tipos
              </option>

              {
                types.map(
                  (type) => (
                    <option
                      key={type}
                      value={type}
                    >
                      {type}
                    </option>
                  ),
                )
              }
            </select>

            <select
              className="field"
              value={statusFilter}
              onChange={(e) =>
                setStatusFilter(
                  e.target.value,
                )
              }
            >
              <option value="ALL">
                Todos los estados
              </option>

              <option value="EN_CONFIRMACION">
                En confirmación
              </option>

              <option value="CON_CORRECCION">
                Con corrección
              </option>

              <option value="LISTO_POR_PROGRAMAR">
                Listo / por programar
              </option>

              <option value="PROGRAMADO">
                Programado
              </option>
            </select>
          </div>

          <div className="unscheduled-list">
            {
              unscheduled.map(
                ({
                  content,
                  target,
                }) => (
                  <DraggableTarget
                    key={target.id}
                    item={content}
                    target={target}
                    openDetail={
                      openDetail
                    }
                  />
                ),
              )
            }

            {
              !unscheduled.length
              && (
                <div className="rail-empty">
                  No hay destinos que coincidan con estos filtros.
                </div>
              )
            }
          </div>
        </DropZone>

        {
          pending
          && (
            <MovePublicationModal
              pending={pending}
              contents={visibleContents}
              moveScope={moveScope}
              setMoveScope={setMoveScope}
              selectedPlatforms={selectedPlatforms}
              setSelectedPlatforms={setSelectedPlatforms}
              onCancel={() => setPending(null)}
              onApply={applyMove}
            />
          )
        }
      </div>
    </DndContext>
  )
}
