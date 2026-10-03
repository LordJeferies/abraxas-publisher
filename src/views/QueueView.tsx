import {
  AlertTriangle,
  CheckCircle2,
  Clock3,
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

const groups = [
  'REVIEW_REQUIRED',
  'QUEUED',
  'DISPATCHING',
  'PROCESSING_REMOTE',
  'VERIFYING',
  'SCHEDULED_REMOTE',
  'SCHEDULED_EXTERNAL',
  'PUBLISHED',
  'FAILED',
]

function JobIcon({
  status,
}: {
  status: string
}) {
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
      === 'SCHEDULED_REMOTE'
  ) {
    return (
      <CheckCircle2/>
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

  const byStatus =
    useMemo(
      () =>
        Object.fromEntries(
          groups.map(
            (status) => [
              status,
              jobs.filter(
                (job) =>
                  job.status
                  === status,
              ),
            ],
          ),
        ) as
        Record<
          string,
          PublishJob[]
        >,
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
            Jobs persistentes, reintentos, verificación y estado remoto.
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

      <div className="queue-summary">
        {
          groups.map(
            (status) => (
              <div key={status}>
                <strong>
                  {
                    byStatus[
                      status
                    ]?.length
                    || 0
                  }
                </strong>

                <span>
                  {status}
                </span>
              </div>
            ),
          )
        }
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

              return (
                <button
                  className="job-row"
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
                      `job-icon status-${job.status}`
                    }
                  >
                    <JobIcon
                      status={
                        job.status
                      }
                    />
                  </div>

                  <div className="job-main">
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
                      {job.status}
                    </b>

                    <small>
                      intento {
                        job.attempt
                      } / {
                        job.maxAttempts
                      }
                    </small>
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
