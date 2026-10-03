import {
  AlertTriangle,
  CheckCircle2,
  Clock3,
  Cloud,
  ExternalLink,
  Hand,
  LoaderCircle,
  RefreshCcw,
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

function manualTemporalStatus(
  job: PublishJob,
) {
  if (
    job.mode !== 'MANUAL'
    || !job.scheduledFor
  ) {
    return job.status
  }

  if (
    job.status
    === 'PUBLISHED_EXTERNAL'
    || job.status
      === 'SCHEDULED_EXTERNAL'
  ) {
    return job.status
  }

  const when =
    new Date(
      job.scheduledFor,
    ).getTime()

  const now =
    Date.now()

  if (
    !Number.isFinite(
      when,
    )
  ) {
    return 'MANUAL_REQUIRED'
  }

  if (
    now >= when
  ) {
    return 'MANUAL_OVERDUE'
  }

  if (
    when - now
    <= 30 * 60 * 1000
  ) {
    return 'MANUAL_DUE'
  }

  return 'MANUAL_REQUIRED'
}

function JobIcon({
  job,
}: {
  job: PublishJob
}) {
  const status =
    manualTemporalStatus(
      job,
    )

  if (
    status === 'FAILED'
  ) {
    return (
      <AlertTriangle/>
    )
  }

  if (
    status === 'PUBLISHED'
    || status
      === 'PUBLISHED_EXTERNAL'
  ) {
    return (
      <CheckCircle2/>
    )
  }

  if (
    status
      === 'SCHEDULED_EXTERNAL'
  ) {
    return (
      <ExternalLink/>
    )
  }

  if (
    job.mode === 'MANUAL'
  ) {
    return (
      <Hand/>
    )
  }

  if (
    status === 'DISPATCHING'
    || status
      === 'PROCESSING_REMOTE'
    || status
      === 'VERIFYING'
  ) {
    return (
      <LoaderCircle/>
    )
  }

  if (
    job.mode === 'AUTO_API'
  ) {
    return (
      <Cloud/>
    )
  }

  return (
    <Clock3/>
  )
}

export function QueueView() {
  const [
    jobs,
    setJobs,
  ] =
    useState<
      PublishJob[]
    >([])

  const contents =
    useAppStore(
      (s) => s.contents,
    )

  const openDetail =
    useAppStore(
      (s) => s.openDetail,
    )

  const load =
    async () => {
      setJobs(
        await backend
          .listPublicationJobs(),
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

  const counts =
    useMemo(
      () => ({
        automatic:
          jobs.filter(
            (job) =>
              job.mode
              === 'AUTO_API',
          ).length,

        manual:
          jobs.filter(
            (job) =>
              job.mode
              === 'MANUAL'
              && ![
                'PUBLISHED_EXTERNAL',
                'SCHEDULED_EXTERNAL',
              ].includes(
                job.status,
              ),
          ).length,

        due:
          jobs.filter(
            (job) =>
              [
                'MANUAL_DUE',
                'MANUAL_OVERDUE',
              ].includes(
                manualTemporalStatus(
                  job,
                ),
              ),
          ).length,

        external:
          jobs.filter(
            (job) =>
              job.mode
              === 'EXTERNAL'
              || job.status
              === 'SCHEDULED_EXTERNAL',
          ).length,

        failed:
          jobs.filter(
            (job) =>
              job.status
              === 'FAILED',
          ).length,
      }),
      [
        jobs,
      ],
    )

  return (
    <div className="page scrollable queue-page">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            PUBLICACIÓN
          </span>

          <h1>
            Cola
          </h1>

          <p>
            Automáticas, manuales y programadas externamente en una sola agenda.
          </p>
        </div>

        <button
          className="secondary-btn"
          onClick={load}
        >
          <RefreshCcw size={15}/>
          Actualizar
        </button>
      </header>

      <div className="queue-summary hybrid">
        <div>
          <Cloud/>
          <strong>
            {counts.automatic}
          </strong>
          <span>
            automáticas
          </span>
        </div>

        <div>
          <Hand/>
          <strong>
            {counts.manual}
          </strong>
          <span>
            manuales
          </span>
        </div>

        <div
          className={
            counts.due
              ? 'attention'
              : ''
          }
        >
          <Clock3/>
          <strong>
            {counts.due}
          </strong>
          <span>
            requieren atención
          </span>
        </div>

        <div>
          <ExternalLink/>
          <strong>
            {counts.external}
          </strong>
          <span>
            externas
          </span>
        </div>

        <div>
          <AlertTriangle/>
          <strong>
            {counts.failed}
          </strong>
          <span>
            errores
          </span>
        </div>
      </div>

      <section className="panel job-list">
        {
          jobs.map(
            (job) => {
              const content =
                contents.find(
                  (x) =>
                    x.id
                    === job.contentId,
                )

              const displayStatus =
                manualTemporalStatus(
                  job,
                )

              return (
                <button
                  className={
                    displayStatus
                    === 'MANUAL_OVERDUE'
                      ? 'job-row manual-overdue'
                      : displayStatus
                        === 'MANUAL_DUE'
                        ? 'job-row manual-due'
                        : 'job-row'
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
                  <div
                    className={
                      `job-icon status-${displayStatus}`
                    }
                  >
                    <JobIcon
                      job={job}
                    />
                  </div>

                  <div className="job-main">
                    <small>
                      {
                        job.provider
                          .toUpperCase()
                      }
                      {' · '}
                      {
                        job.mode
                      }
                    </small>

                    <strong>
                      {
                        content?.title
                        || job.contentId
                      }
                    </strong>

                    <span>
                      {
                        job.scheduledFor
                          ? new Date(
                              job.scheduledFor,
                            ).toLocaleString()
                          : 'Sin fecha'
                      }
                    </span>
                  </div>

                  <div className="job-state">
                    <b>
                      {
                        displayStatus
                      }
                    </b>

                    {
                      job.mode
                      === 'MANUAL'
                      && (
                        <small>
                          Publicar manualmente
                        </small>
                      )
                    }

                    {
                      job.mode
                      === 'AUTO_API'
                      && (
                        <small>
                          Publisher se encargará
                        </small>
                      )
                    }
                  </div>
                </button>
              )
            },
          )
        }

        {
          !jobs.length
          && (
            <div className="empty-state">
              La cola está vacía. Ve a Preparar publicación.
            </div>
          )
        }
      </section>
    </div>
  )
}
