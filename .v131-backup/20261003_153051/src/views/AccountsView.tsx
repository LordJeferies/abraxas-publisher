import {
  CheckCircle2,
  Link2,
  Plus,
  ShieldAlert,
  Trash2,
  X,
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
  ConnectedAccount,
} from '../types'

const PROVIDERS = [
  'instagram',
  'facebook',
  'linkedin',
  'youtube',
  'tiktok',
]

function capabilities(
  provider: string,
) {
  const matrix:
    Record<string, object> = {
      instagram: {
        image: true,
        video: true,
        multiImage: true,
        reel: true,
        story: false,
        dispatchStrategy:
          'LOCAL_DISPATCH',
      },

      facebook: {
        image: true,
        video: true,
        multiImage: true,
        dispatchStrategy:
          'PROVIDER_OR_LOCAL',
      },

      linkedin: {
        text: true,
        image: true,
        video: true,
        document: true,
        multiImage: true,
        organicCarousel: false,
        dispatchStrategy:
          'LOCAL_DISPATCH',
      },

      youtube: {
        video: true,
        short: true,
        nativePublishAt: true,
        dispatchStrategy:
          'NATIVE_OR_LOCAL',
      },

      tiktok: {
        video: true,
        photo: true,
        directPost: true,
        mediaUploadDraft: true,
        creatorInfoRequired: true,
        dispatchStrategy:
          'LOCAL_DISPATCH',
      },
    }

  return JSON.stringify(
    matrix[provider]
    || {},
  )
}

export function AccountsView() {
  const brands =
    useAppStore(
      (s) => s.brands,
    )

  const [
    accounts,
    setAccounts,
  ] =
    useState<
      ConnectedAccount[]
    >([])

  const [
    modal,
    setModal,
  ] =
    useState(false)

  const [
    provider,
    setProvider,
  ] =
    useState('instagram')

  const [
    brand,
    setBrand,
  ] =
    useState(
      brands[0]?.name
      || '',
    )

  const [
    name,
    setName,
  ] =
    useState('')

  const [
    handle,
    setHandle,
  ] =
    useState('')

  const [
    kind,
    setKind,
  ] =
    useState('creator')

  const [
    mode,
    setMode,
  ] =
    useState<
      'api'
      | 'external'
    >('api')

  const load =
    async () => {
      setAccounts(
        await backend
          .listConnectedAccounts(),
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

  const save =
    async () => {
      if (!name.trim()) {
        return
      }

      await backend
        .saveConnectedAccount({
          provider,
          brand:
            brand || null,
          displayName:
            name.trim(),
          handle:
            handle.trim()
            || null,
          accountKind:
            kind,

          // No fingimos OAuth.
          connectionStatus:
            mode === 'external'
              ? 'EXTERNAL_ONLY'
              : 'NEEDS_AUTH',

          authState:
            mode === 'external'
              ? 'NOT_REQUIRED'
              : 'PENDING',

          capabilitiesJson:
            capabilities(
              provider,
            ),

          externalReference:
            null,
        })

      await load()

      setModal(false)
      setName('')
      setHandle('')
    }

  const remove =
    async (
      id: string,
    ) => {
      await backend
        .removeConnectedAccount(
          id,
        )

      await load()
    }

  return (
    <div className="page scrollable accounts-page">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            CUENTAS
          </span>

          <h1>
            Cuentas conectadas
          </h1>

          <p>
            Un único lugar para cuentas API, cuentas externas y capacidades de publicación.
          </p>
        </div>

        <button
          className="primary-btn"
          onClick={() =>
            setModal(true)
          }
        >
          <Plus size={16}/>
          Conectar cuenta
        </button>
      </header>

      <div className="account-grid">
        {
          accounts.map(
            (account) => (
              <article
                className={
                  `account-card provider-${account.provider}`
                }
                key={account.id}
              >
                <div className="account-provider">
                  <div>
                    <span>
                      {
                        account.provider
                          .toUpperCase()
                      }
                    </span>

                    <strong>
                      {
                        account.displayName
                      }
                    </strong>

                    <small>
                      {
                        account.handle
                        || account.accountKind
                      }
                    </small>
                  </div>

                  {
                    account.connectionStatus
                    === 'CONNECTED'
                      ? (
                        <CheckCircle2
                          className="healthy"
                          size={20}
                        />
                      )
                      : (
                        <ShieldAlert
                          className="warning"
                          size={20}
                        />
                      )
                  }
                </div>

                <div className="account-health">
                  <span>
                    Marca
                    <b>
                      {
                        account.brand
                        || 'Todas'
                      }
                    </b>
                  </span>

                  <span>
                    Estado
                    <b>
                      {
                        account.connectionStatus
                      }
                    </b>
                  </span>

                  <span>
                    Auth
                    <b>
                      {
                        account.authState
                      }
                    </b>
                  </span>
                </div>

                {
                  account.connectionStatus
                  === 'NEEDS_AUTH'
                  && (
                    <div className="account-warning">
                      <Link2 size={14}/>

                      Falta completar OAuth para habilitar publicación API real.
                    </div>
                  )
                }

                {
                  account.connectionStatus
                  === 'EXTERNAL_ONLY'
                  && (
                    <div className="account-warning neutral">
                      Esta cuenta se usa para registrar publicaciones hechas fuera de Publisher.
                    </div>
                  )
                }

                <button
                  className="danger-text-btn"
                  onClick={() =>
                    remove(
                      account.id,
                    )
                  }
                >
                  <Trash2 size={13}/>
                  Quitar
                </button>
              </article>
            ),
          )
        }

        {
          !accounts.length
          && (
            <div className="hero-empty">
              <h2>
                Sin cuentas
              </h2>

              <p>
                Añade Instagram, Facebook, LinkedIn, YouTube o TikTok.
              </p>
            </div>
          )
        }
      </div>

      {
        modal
        && (
          <div className="modal-backdrop">
            <section className="account-modal">
              <header>
                <div>
                  <span className="eyebrow">
                    CUENTA NUEVA
                  </span>

                  <h3>
                    Conectar cuenta
                  </h3>
                </div>

                <button
                  onClick={() =>
                    setModal(false)
                  }
                >
                  <X size={18}/>
                </button>
              </header>

              <label>
                Plataforma
              </label>

              <select
                className="field full-field"
                value={provider}
                onChange={(e) =>
                  setProvider(
                    e.target.value,
                  )
                }
              >
                {
                  PROVIDERS.map(
                    (value) => (
                      <option
                        value={value}
                        key={value}
                      >
                        {value}
                      </option>
                    ),
                  )
                }
              </select>

              <label>
                Marca
              </label>

              <select
                className="field full-field"
                value={brand}
                onChange={(e) =>
                  setBrand(
                    e.target.value,
                  )
                }
              >
                <option value="">
                  Todas
                </option>

                {
                  brands.map(
                    (value) => (
                      <option
                        key={value.id}
                        value={value.name}
                      >
                        {value.name}
                      </option>
                    ),
                  )
                }
              </select>

              <label>
                Nombre visible
              </label>

              <input
                className="field full-field"
                value={name}
                onChange={(e) =>
                  setName(
                    e.target.value,
                  )
                }
                placeholder="Ej. Joc López"
              />

              <label>
                Handle
              </label>

              <input
                className="field full-field"
                value={handle}
                onChange={(e) =>
                  setHandle(
                    e.target.value,
                  )
                }
                placeholder="@jocventas"
              />

              <label>
                Tipo
              </label>

              <select
                className="field full-field"
                value={kind}
                onChange={(e) =>
                  setKind(
                    e.target.value,
                  )
                }
              >
                <option value="creator">
                  Creator / perfil
                </option>

                <option value="organization">
                  Organización / página
                </option>

                <option value="channel">
                  Canal
                </option>
              </select>

              <label>
                Uso
              </label>

              <div className="account-mode-grid">
                <button
                  className={
                    mode === 'api'
                      ? 'choice-card active'
                      : 'choice-card'
                  }
                  onClick={() =>
                    setMode('api')
                  }
                >
                  <strong>
                    API
                  </strong>

                  <span>
                    Preparar OAuth y publicación desde Publisher.
                  </span>
                </button>

                <button
                  className={
                    mode === 'external'
                      ? 'choice-card active'
                      : 'choice-card'
                  }
                  onClick={() =>
                    setMode('external')
                  }
                >
                  <strong>
                    Externa
                  </strong>

                  <span>
                    Edits, Studio, Business Suite u otra app.
                  </span>
                </button>
              </div>

              {
                mode === 'api'
                && (
                  <div className="account-warning">
                    La cuenta se guardará como OAuth pendiente. Publisher no la marcará como CONNECTED hasta verificar credenciales y permisos reales.
                  </div>
                )
              }

              <div className="modal-actions">
                <button
                  className="secondary-btn"
                  onClick={() =>
                    setModal(false)
                  }
                >
                  Cancelar
                </button>

                <button
                  className="primary-btn"
                  onClick={save}
                >
                  Guardar cuenta
                </button>
              </div>
            </section>
          </div>
        )
      }
    </div>
  )
}
