import {
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  ExternalLink,
  Send,
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

import {
  PlatformPreview,
} from '../components/PlatformPreview'

import type {
  ConnectedAccount,
  PreflightReport,
  PublicationTarget,
} from '../types'

export function PublishView() {
  const {
    contents,
    selectedBrand,
    setContents,
  } = useAppStore()

  const [
    accounts,
    setAccounts,
  ] =
    useState<
      ConnectedAccount[]
    >([])

  const [
    step,
    setStep,
  ] =
    useState(1)

  const [
    selectedTargets,
    setSelectedTargets,
  ] =
    useState<string[]>([])

  const [
    accountFor,
    setAccountFor,
  ] =
    useState<
      Record<string,string>
    >({})

  const [
    preflight,
    setPreflight,
  ] =
    useState<
      Record<
        string,
        PreflightReport
      >
    >({})

  const [
    previewId,
    setPreviewId,
  ] =
    useState<string | null>(
      null,
    )

  const [
    externalMethod,
    setExternalMethod,
  ] =
    useState('Edits')

  const [
    message,
    setMessage,
  ] =
    useState('')

  useEffect(
    () => {
      backend
        .listConnectedAccounts()
        .then(setAccounts)
        .catch(console.error)
    },
    [],
  )

  const candidates =
    useMemo(
      () =>
        contents
          .filter(
            (content) =>
              (
                selectedBrand
                === 'ALL'
                || content.client
                === selectedBrand
              )
              && (
                content.status
                === 'LISTO_POR_PROGRAMAR'
                || content.status
                === 'PROGRAMADO'
              ),
          )
          .flatMap(
            (content) =>
              content.targets.map(
                (target) => ({
                  content,
                  target,
                }),
              ),
          ),
      [
        contents,
        selectedBrand,
      ],
    )

  const selected =
    candidates.filter(
      ({ target }) =>
        selectedTargets
          .includes(
            target.id,
          ),
    )

  const toggle =
    (
      id: string,
    ) => {
      setSelectedTargets(
        (prev) =>
          prev.includes(id)
            ? prev.filter(
                (x) => x !== id,
              )
            : [...prev,id],
      )
    }

  const compatibleAccounts =
    (
      target: PublicationTarget,
      brand?: string | null,
    ) =>
      accounts.filter(
        (account) =>
          account.provider
            === target.platform
          && (
            !account.brand
            || !brand
            || account.brand
              === brand
          ),
      )

  const runPreflight =
    async () => {
      const next:
        Record<
          string,
          PreflightReport
        > = {}

      for (
        const {
          target,
        }
        of selected
      ) {
        next[target.id] =
          await backend
            .publishingPreflight(
              target.id,
              accountFor[
                target.id
              ]
              || null,
            )
      }

      setPreflight(next)
      setStep(3)
    }

  const allReady =
    selected.length > 0
    && selected.every(
      ({ target }) =>
        preflight[
          target.id
        ]?.ready,
    )

  const enqueue =
    async () => {
      if (!allReady) {
        setMessage(
          'Hay destinos bloqueados por el preflight.',
        )

        return
      }

      await backend
        .enqueuePublications(
          selected.map(
            ({ target }) => ({
              targetId:
                target.id,
              accountId:
                accountFor[
                  target.id
                ]
                || null,
              mode:
                'SCHEDULE',
            }),
          ),
        )

      setMessage(
        `${selected.length} destino(s) añadidos a la cola.`,
      )

      setStep(5)
    }

  const markExternal =
    async (
      targetId: string,
    ) => {
      const entry =
        candidates.find(
          ({ target }) =>
            target.id
            === targetId,
        )

      if (!entry) {
        return
      }

      await backend
        .markScheduledExternal(
          targetId,
          externalMethod,
          entry.target
            .scheduledAt
          || null,
          null,
          `Programado fuera de Publisher mediante ${externalMethod}.`,
        )

      setContents(
        await backend
          .listContents(),
      )

      setMessage(
        `Marcado como SCHEDULED_EXTERNAL · ${externalMethod}`,
      )
    }

  const previewEntry =
    previewId
      ? candidates.find(
          ({ target }) =>
            target.id
            === previewId,
        )
      : selected[0]

  return (
    <div
      className={
        previewEntry
          ? `page scrollable publish-page theme-${previewEntry.target.platform}`
          : 'page scrollable publish-page'
      }
    >
      <header className="page-header publish-header">
        <div>
          <span className="eyebrow">
            ÁREA DE PUBLICACIÓN
          </span>

          <h1>
            Preparar publicación
          </h1>

          <p>
            Selecciona → destinos → preflight → preview → cola.
          </p>
        </div>

        <div className="publish-step-number">
          {step}/5
        </div>
      </header>

      <div className="wizard-steps">
        {
          [
            'Contenido',
            'Cuentas',
            'Verificar',
            'Preview',
            'Confirmar',
          ].map(
            (label,index) => (
              <div
                className={
                  step === index + 1
                    ? 'wizard-step active'
                    : step > index + 1
                      ? 'wizard-step done'
                      : 'wizard-step'
                }
                key={label}
              >
                <span>
                  {index + 1}
                </span>

                {label}
              </div>
            ),
          )
        }
      </div>

      {
        step === 1
        && (
          <section className="publish-stage">
            <div className="stage-title">
              <div>
                <h2>
                  ¿Qué vas a programar?
                </h2>

                <p>
                  Sólo aparece contenido editorialmente listo.
                </p>
              </div>

              <button
                className="secondary-btn"
                onClick={() =>
                  setSelectedTargets(
                    candidates.map(
                      ({ target }) =>
                        target.id,
                    ),
                  )
                }
              >
                Seleccionar todos
              </button>
            </div>

            <div className="publish-selection-list">
              {
                candidates.map(
                  ({
                    content,
                    target,
                  }) => (
                    <label
                      className={
                        selectedTargets.includes(
                          target.id,
                        )
                          ? 'publish-select-row selected'
                          : 'publish-select-row'
                      }
                      key={target.id}
                    >
                      <input
                        type="checkbox"
                        checked={
                          selectedTargets.includes(
                            target.id,
                          )
                        }
                        onChange={() =>
                          toggle(
                            target.id,
                          )
                        }
                      />

                      <div>
                        <small>
                          {
                            content.client
                            || 'Sin marca'
                          }
                        </small>

                        <strong>
                          {
                            content.title
                          }
                        </strong>

                        <span>
                          {
                            target.platform
                          }
                          {' · '}
                          {
                            target.scheduledAt
                              ? new Date(
                                  target.scheduledAt,
                                ).toLocaleString()
                              : 'Sin calendarizar'
                          }
                        </span>
                      </div>

                      <b>
                        {
                          content.contentType
                        }
                      </b>
                    </label>
                  ),
                )
              }
            </div>
          </section>
        )
      }

      {
        step === 2
        && (
          <section className="publish-stage">
            <div className="stage-title">
              <div>
                <h2>
                  Cuentas de destino
                </h2>

                <p>
                  Una cuenta distinta puede usarse por cada red.
                </p>
              </div>
            </div>

            <div className="destination-list">
              {
                selected.map(
                  ({
                    content,
                    target,
                  }) => {
                    const compatible =
                      compatibleAccounts(
                        target,
                        content.client,
                      )

                    return (
                      <article
                        className={
                          `destination-card provider-${target.platform}`
                        }
                        key={target.id}
                      >
                        <div>
                          <small>
                            {
                              target.platform
                                .toUpperCase()
                            }
                          </small>

                          <strong>
                            {
                              content.title
                            }
                          </strong>

                          <span>
                            {
                              target.scheduledAt
                                ? new Date(
                                    target.scheduledAt,
                                  ).toLocaleString()
                                : 'Sin fecha'
                            }
                          </span>
                        </div>

                        <select
                          className="field"
                          value={
                            accountFor[
                              target.id
                            ]
                            || ''
                          }
                          onChange={(e) =>
                            setAccountFor(
                              (prev) => ({
                                ...prev,
                                [
                                  target.id
                                ]:
                                  e.target.value,
                              }),
                            )
                          }
                        >
                          <option value="">
                            Seleccionar cuenta
                          </option>

                          {
                            compatible.map(
                              (account) => (
                                <option
                                  value={account.id}
                                  key={account.id}
                                >
                                  {
                                    account.displayName
                                  }
                                  {' · '}
                                  {
                                    account.connectionStatus
                                  }
                                </option>
                              ),
                            )
                          }
                        </select>

                        <button
                          className="secondary-btn small"
                          onClick={() =>
                            markExternal(
                              target.id,
                            )
                          }
                        >
                          <ExternalLink size={14}/>
                          Programado fuera
                        </button>
                      </article>
                    )
                  },
                )
              }
            </div>

            <div className="external-method-row">
              <span>
                Si fue programado fuera:
              </span>

              <select
                className="field"
                value={externalMethod}
                onChange={(e) =>
                  setExternalMethod(
                    e.target.value,
                  )
                }
              >
                <option>
                  Edits
                </option>
                <option>
                  Meta Business Suite
                </option>
                <option>
                  YouTube Studio
                </option>
                <option>
                  LinkedIn
                </option>
                <option>
                  TikTok
                </option>
                <option>
                  Otra herramienta
                </option>
              </select>
            </div>
          </section>
        )
      }

      {
        step === 3
        && (
          <section className="publish-stage">
            <div className="stage-title">
              <div>
                <h2>
                  Verificador
                </h2>

                <p>
                  Ningún job sale a una API sin pasar esta fase.
                </p>
              </div>
            </div>

            <div className="preflight-grid">
              {
                selected.map(
                  ({
                    content,
                    target,
                  }) => {
                    const report =
                      preflight[
                        target.id
                      ]

                    return (
                      <article
                        className={
                          report?.ready
                            ? 'preflight-card ready'
                            : 'preflight-card blocked'
                        }
                        key={target.id}
                      >
                        <header>
                          <div>
                            <small>
                              {
                                target.platform
                              }
                            </small>

                            <strong>
                              {
                                content.title
                              }
                            </strong>
                          </div>

                          {
                            report?.ready
                              ? <CheckCircle2/>
                              : <CircleAlert/>
                          }
                        </header>

                        {
                          report?.checks.map(
                            (check) => (
                              <div
                                className={
                                  check.ok
                                    ? 'preflight-check ok'
                                    : 'preflight-check fail'
                                }
                                key={check.key}
                              >
                                <span>
                                  {
                                    check.ok
                                      ? '✓'
                                      : '✕'
                                  }
                                </span>

                                <div>
                                  <strong>
                                    {
                                      check.label
                                    }
                                  </strong>

                                  <small>
                                    {
                                      check.detail
                                    }
                                  </small>
                                </div>
                              </div>
                            ),
                          )
                        }
                      </article>
                    )
                  },
                )
              }
            </div>
          </section>
        )
      }

      {
        step === 4
        && (
          <section className="publish-stage preview-stage">
            <aside className="preview-target-list">
              {
                selected.map(
                  ({
                    content,
                    target,
                  }) => (
                    <button
                      className={
                        previewEntry?.target.id
                        === target.id
                          ? 'active'
                          : ''
                      }
                      key={target.id}
                      onClick={() =>
                        setPreviewId(
                          target.id,
                        )
                      }
                    >
                      <strong>
                        {
                          target.platform
                        }
                      </strong>

                      <span>
                        {
                          content.title
                        }
                      </span>
                    </button>
                  ),
                )
              }
            </aside>

            <div className="preview-workbench">
              {
                previewEntry
                && (
                  <>
                    <div className="preview-toolbar">
                      <div>
                        <span className="eyebrow">
                          PREVIEW
                        </span>

                        <h2>
                          {
                            previewEntry.target.platform
                          }
                        </h2>
                      </div>

                      <div className="preview-type-badge">
                        {
                          previewEntry.content.contentType
                        }
                      </div>
                    </div>

                    <PlatformPreview
                      item={
                        previewEntry.content
                      }
                      target={
                        previewEntry.target
                      }
                    />
                  </>
                )
              }
            </div>
          </section>
        )
      }

      {
        step === 5
        && (
          <section className="publish-stage confirmation-stage">
            <span className="eyebrow">
              CONFIRMAR
            </span>

            <h2>
              {
                selected.length
              } publicación(es)
            </h2>

            <p>
              La confirmación añade jobs persistentes a la cola. Sólo los adapters realmente autorizados podrán ejecutar llamadas externas.
            </p>

            <div className="confirmation-summary">
              {
                selected.map(
                  ({
                    content,
                    target,
                  }) => (
                    <div key={target.id}>
                      <span>
                        {
                          target.platform
                        }
                      </span>

                      <strong>
                        {
                          content.title
                        }
                      </strong>

                      <small>
                        {
                          target.scheduledAt
                            ? new Date(
                                target.scheduledAt,
                              ).toLocaleString()
                            : 'Sin fecha'
                        }
                      </small>
                    </div>
                  ),
                )
              }
            </div>

            <button
              className="publish-confirm-btn"
              disabled={!allReady}
              onClick={enqueue}
            >
              <Send size={18}/>
              PROGRAMAR {
                selected.length
              } PUBLICACIÓN(ES)
            </button>

            {
              !allReady
              && (
                <div className="account-warning">
                  Existen destinos sin cuenta API autorizada o con preflight bloqueado.
                </div>
              )
            }
          </section>
        )
      }

      <footer className="wizard-footer">
        <button
          className="secondary-btn"
          disabled={step === 1}
          onClick={() =>
            setStep(
              Math.max(
                1,
                step - 1,
              ),
            )
          }
        >
          <ChevronLeft size={15}/>
          Atrás
        </button>

        <span>
          {
            message
          }
        </span>

        {
          step < 5
          && (
            <button
              className="primary-btn"
              disabled={
                step === 1
                && !selected.length
              }
              onClick={() => {
                if (
                  step === 2
                ) {
                  runPreflight()
                } else {
                  setStep(
                    step + 1,
                  )
                }
              }}
            >
              Continuar
              <ChevronRight size={15}/>
            </button>
          )
        }
      </footer>
    </div>
  )
}
