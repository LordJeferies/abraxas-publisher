import {
  RotateCcw,
  RotateCw,
} from 'lucide-react'

import {
  useEffect,
  useState,
} from 'react'

import {
  backend,
} from '../lib/backend'

import {
  useAppStore,
} from '../lib/store'

import type {
  ActivityEvent,
} from '../types'

export function ActivityView() {
  const [
    events,
    setEvents,
  ] =
    useState<
      ActivityEvent[]
    >([])

  const [
    message,
    setMessage,
  ] =
    useState('')

  const setContents =
    useAppStore(
      (s) =>
        s.setContents,
    )

  const load =
    async () => {
      setEvents(
        await backend.listActivity(),
      )
    }

  useEffect(
    () => {
      load()
        .catch(
          console.error,
        )
    },
    [],
  )

  const undo =
    async () => {
      const result =
        await backend.undo()

      setMessage(
        result
          ? `Deshecho: ${result.label}`
          : 'No hay ninguna acción local reversible.',
      )

      setContents(
        await backend.listContents(),
      )

      await load()
    }

  const redo =
    async () => {
      const result =
        await backend.redo()

      setMessage(
        result
          ? `Rehecho: ${result.label}`
          : 'No hay ninguna acción para rehacer.',
      )

      setContents(
        await backend.listContents(),
      )

      await load()
    }

  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            AUDITORÍA
          </span>

          <h1>
            Actividad
          </h1>

          <p>
            Historial del workspace. Undo/Redo sólo afecta acciones locales reversibles.
          </p>
        </div>

        <div className="activity-actions">
          <button
            className="secondary-btn"
            onClick={undo}
          >
            <RotateCcw size={15}/>
            Undo
            <kbd>⌘Z</kbd>
          </button>

          <button
            className="secondary-btn"
            onClick={redo}
          >
            <RotateCw size={15}/>
            Redo
            <kbd>⇧⌘Z</kbd>
          </button>
        </div>
      </header>

      {
        message
        && (
          <div className="calendar-message">
            {message}
          </div>
        )
      }

      <section className="activity-list panel">
        {
          events.length
          ? events.map(
            (event) => (
              <article
                className={
                  event.undone
                    ? 'activity-row undone'
                    : 'activity-row'
                }
                key={event.id}
              >
                <div className="activity-time">
                  {
                    new Date(
                      event.createdAt,
                    ).toLocaleString()
                  }
                </div>

                <div className="activity-main">
                  <strong>
                    {
                      event.label
                    }
                  </strong>

                  <span>
                    {
                      event.action
                    }
                    {' · '}
                    {
                      event.entityType
                    }
                    {
                      event.remote
                        ? ' · REMOTO'
                        : ' · LOCAL'
                    }
                    {
                      event.undone
                        ? ' · DESHECHO'
                        : ''
                    }
                  </span>
                </div>

                <div className="activity-flags">
                  {
                    event.reversible
                    && !event.remote
                    && (
                      <span>
                        reversible
                      </span>
                    )
                  }

                  {
                    event.remote
                    && (
                      <span className="danger">
                        definitivo
                      </span>
                    )
                  }
                </div>
              </article>
            ),
          )
          : (
            <div className="empty-state">
              Todavía no hay actividad.
            </div>
          )
        }
      </section>
    </div>
  )
}
