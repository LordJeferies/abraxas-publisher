import {
  AlertTriangle,
  CheckCircle2,
  Clock3,
  Cloud,
  Hand,
  MessageSquareText,
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
  PublishJob,
} from '../types'

function isToday(
  value?: string | null,
) {
  if (!value) {
    return false
  }

  const d =
    new Date(value)

  const now =
    new Date()

  return (
    d.getFullYear()
      === now.getFullYear()
    && d.getMonth()
      === now.getMonth()
    && d.getDate()
      === now.getDate()
  )
}

export function TodayView() {
  const {
    contents,
    openDetail,
    setView,
  } =
    useAppStore()

  const [
    jobs,
    setJobs,
  ] =
    useState<
      PublishJob[]
    >([])

  useEffect(
    () => {
      backend
        .listPublicationJobs()
        .then(setJobs)
        .catch(
          console.error,
        )
    },
    [],
  )

  const targets =
    contents.flatMap(
      (content) =>
        content.targets.map(
          (target) => ({
            content,
            target,
          }),
        ),
    )

  const scheduled =
    targets
      .filter(
        (x) =>
          x.target
            .scheduledAt,
      )
      .sort(
        (a,b) =>
          String(
            a.target
              .scheduledAt,
          ).localeCompare(
            String(
              b.target
                .scheduledAt,
            ),
          ),
      )
      .slice(0,6)

  const corrections =
    contents.filter(
      (content) =>
        content.status
        === 'CON_CORRECCION',
    )

  const issues =
    contents.flatMap(
      (content) =>
        content.issues.map(
          (issue) => ({
            content,
            issue,
          }),
        ),
    ).slice(
      0,
      5,
    )

  const todayJobs =
    jobs.filter(
      (job) =>
        isToday(
          job.scheduledFor,
        ),
    )

  const manualToday =
    todayJobs.filter(
      (job) =>
        job.mode === 'MANUAL'
        && ![
          'PUBLISHED_EXTERNAL',
          'SCHEDULED_EXTERNAL',
        ].includes(
          job.status,
        ),
    )

  const autoToday =
    todayJobs.filter(
      (job) =>
        job.mode
        === 'AUTO_API',
    )

  const externalToday =
    todayJobs.filter(
      (job) =>
        job.mode
        === 'EXTERNAL'
        || job.status
        === 'SCHEDULED_EXTERNAL',
    )

  const overdue =
    useMemo(
      () =>
        manualToday.filter(
          (job) => {
            if (
              !job.scheduledFor
            ) {
              return false
            }

            const time =
              new Date(
                job.scheduledFor,
              ).getTime()

            return (
              Number.isFinite(
                time,
              )
              && time
                <= Date.now()
            )
          },
        ),
      [
        manualToday,
      ],
    )

  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            OPERACIONES
          </span>

          <h1>
            Hoy
          </h1>

          <p>
            Qué se publica automáticamente y qué requiere tu intervención.
          </p>
        </div>
      </header>

      <div className="metric-grid">
        <div className="metric">
          <span>
            Hoy
          </span>

          <strong>
            {
              todayJobs.length
            }
          </strong>

          <small>
            publicaciones
          </small>
        </div>

        <div className="metric">
          <span>
            Automáticas
          </span>

          <strong>
            {
              autoToday.length
            }
          </strong>

          <small>
            Publisher se encarga
          </small>
        </div>

        <div className="metric">
          <span>
            Manuales
          </span>

          <strong>
            {
              manualToday.length
            }
          </strong>

          <small>
            requieren publicación
          </small>
        </div>

        <div
          className={
            overdue.length
              ? 'metric danger'
              : 'metric'
          }
        >
          <span>
            Atención ahora
          </span>

          <strong>
            {
              overdue.length
            }
          </strong>

          <small>
            manuales vencidas
          </small>
        </div>
      </div>

      {
        manualToday.length
        > 0
        && (
          <section className="panel manual-attention-panel">
            <div className="panel-title-row">
              <h3>
                <Hand size={17}/>
                Requieren publicación manual
              </h3>

              <button
                className="secondary-btn small"
                onClick={() =>
                  setView(
                    'queue',
                  )
                }
              >
                Ver cola
              </button>
            </div>

            {
              manualToday.map(
                (job) => {
                  const content =
                    contents.find(
                      (x) =>
                        x.id
                        === job.contentId,
                    )

                  const due =
                    job.scheduledFor
                    && new Date(
                      job.scheduledFor,
                    ).getTime()
                      <= Date.now()

                  return (
                    <button
                      className={
                        due
                          ? 'manual-task overdue'
                          : 'manual-task'
                      }
                      key={job.id}
                      onClick={() => {
                        if (
                          content
                        ) {
                          openDetail(
                            content.id,
                          )
                        }
                      }}
                    >
                      <Hand size={16}/>

                      <div>
                        <small>
                          {
                            job.provider
                              .toUpperCase()
                          }
                        </small>

                        <strong>
                          {
                            content?.title
                            || job.contentId
                          }
                        </strong>
                      </div>

                      <span>
                        {
                          job.scheduledFor
                            ? new Date(
                                job.scheduledFor,
                              ).toLocaleTimeString(
                                [],
                                {
                                  hour:
                                    '2-digit',
                                  minute:
                                    '2-digit',
                                },
                              )
                            : 'Sin hora'
                        }
                      </span>

                      <b>
                        {
                          due
                            ? 'PUBLICAR AHORA'
                            : 'MANUAL'
                        }
                      </b>
                    </button>
                  )
                },
              )
            }
          </section>
        )
      }

      <div className="two-col">
        <section className="panel">
          <h3>
            <Clock3 size={17}/>
            Próximas
          </h3>

          {
            scheduled.length
              ? scheduled.map(
                  ({
                    content,
                    target,
                  }) => (
                    <button
                      className="list-row clickable"
                      key={target.id}
                      onClick={() =>
                        openDetail(
                          content.id,
                        )
                      }
                    >
                      <div>
                        <strong>
                          {
                            content.title
                          }
                        </strong>

                        <span>
                          {
                            target.platform
                          }
                        </span>
                      </div>

                      <small>
                        {
                          new Date(
                            target.scheduledAt!,
                          ).toLocaleString()
                        }
                      </small>
                    </button>
                  ),
                )
              : (
                  <div className="empty-state">
                    Todavía no hay horarios locales.
                  </div>
                )
          }
        </section>

        <section className="panel">
          <h3>
            <MessageSquareText size={17}/>
            Correcciones
          </h3>

          {
            corrections.length
              ? corrections
                  .slice(
                    0,
                    6,
                  )
                  .map(
                    (content) => (
                      <button
                        className="list-row clickable"
                        key={content.id}
                        onClick={() =>
                          openDetail(
                            content.id,
                          )
                        }
                      >
                        <div>
                          <strong>
                            {
                              content.title
                            }
                          </strong>

                          <span>
                            {
                              content.latestNote
                                ?.body
                              || 'Pendiente de corrección'
                            }
                          </span>
                        </div>

                        <small>
                          v{
                            content.version
                          }
                        </small>
                      </button>
                    ),
                  )
              : (
                  <div className="empty-state">
                    <CheckCircle2 size={18}/>
                    Sin correcciones pendientes.
                  </div>
                )
          }

          {
            issues.length
            > 0
            && (
              <div className="today-warning">
                <AlertTriangle size={14}/>
                {
                  issues.length
                } incidencias técnicas
              </div>
            )
          }
        </section>
      </div>

      {
        autoToday.length
        > 0
        && (
          <div className="auto-status-strip">
            <Cloud size={15}/>

            <strong>
              {
                autoToday.length
              } automática(s) hoy
            </strong>

            <span>
              No requieren publicación manual mientras sus APIs sigan saludables.
            </span>
          </div>
        )
      }

      {
        externalToday.length
        > 0
        && (
          <div className="external-status-strip">
            {
              externalToday.length
            } publicación(es) registradas como programadas fuera de Publisher.
          </div>
        )
      }
    </div>
  )
}
