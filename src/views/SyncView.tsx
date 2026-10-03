import {
  CheckCircle2,
  Cloud,
  Laptop,
  LogIn,
  LogOut,
  RefreshCcw,
  Smartphone,
} from 'lucide-react'

import {
  useEffect,
  useState,
} from 'react'

import {
  runtimeSurface,
} from '../lib/runtime'

import {
  cloudSignIn,
  cloudSignOut,
  cloudSignUp,
  cloudUser,
  supabaseConfigured,
} from '../lib/supabase'

import {
  initializePublisherSync,
  pullPublisher,
  pushPublisher,
} from '../lib/publisherSync'

export function SyncView() {
  const [
    email,
    setEmail,
  ] =
    useState('')

  const [
    password,
    setPassword,
  ] =
    useState('')

  const [
    userEmail,
    setUserEmail,
  ] =
    useState<
      string | null
    >(null)

  const [
    message,
    setMessage,
  ] =
    useState('')

  const [
    syncing,
    setSyncing,
  ] =
    useState(false)

  const load =
    async () => {
      const user =
        await cloudUser()

      setUserEmail(
        user?.email
        || null,
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

  const login =
    async () => {
      try {
        setMessage(
          'Conectando…',
        )

        await cloudSignIn(
          email,
          password,
        )

        await initializePublisherSync()

        await load()

        setMessage(
          'ABRAXAS Cloud conectado y sincronizado.',
        )
      } catch (
        error
      ) {
        setMessage(
          String(error),
        )
      }
    }

  const register =
    async () => {
      try {
        const data =
          await cloudSignUp(
            email,
            password,
          )

        if (
          data.session
        ) {
          await initializePublisherSync()
          await load()
        }

        setMessage(
          data.session
            ? 'Cuenta creada y conectada.'
            : 'Cuenta creada. Revisa el email si Supabase exige confirmación.',
        )
      } catch (
        error
      ) {
        setMessage(
          String(error),
        )
      }
    }

  const sync =
    async () => {
      setSyncing(true)

      try {
        await pushPublisher()
        await pullPublisher()

        setMessage(
          'Sincronización completada.',
        )
      } catch (
        error
      ) {
        setMessage(
          String(error),
        )
      } finally {
        setSyncing(false)
      }
    }

  const logout =
    async () => {
      await cloudSignOut()

      setUserEmail(
        null,
      )

      setMessage(
        'Sesión cerrada.',
      )
    }

  const runtime =
    runtimeSurface()

  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            ABRAXAS CLOUD
          </span>

          <h1>
            Sincronización
          </h1>

          <p>
            El mismo workspace de Publisher en Mac, Web y PWA.
          </p>
        </div>

        {
          userEmail
          && (
            <button
              className="secondary-btn"
              disabled={syncing}
              onClick={sync}
            >
              <RefreshCcw size={15}/>
              {
                syncing
                  ? 'Sincronizando…'
                  : 'Sincronizar'
              }
            </button>
          )
        }
      </header>

      {
        !supabaseConfigured()
        ? (
          <section className="panel">
            Supabase no está configurado.
          </section>
        )
        : !userEmail
          ? (
            <section className="panel sync-login-card">
              <Cloud size={25}/>

              <span className="eyebrow">
                MISMO LOGIN ABRAXAS
              </span>

              <h2>
                Entrar
              </h2>

              <p>
                Usa el mismo usuario Supabase de Editorial OS en Desktop, iPhone y navegador.
              </p>

              <input
                className="field full-field"
                type="email"
                placeholder="Email"
                value={email}
                onChange={(event) =>
                  setEmail(
                    event.target.value,
                  )
                }
              />

              <input
                className="field full-field"
                type="password"
                placeholder="Contraseña"
                value={password}
                onChange={(event) =>
                  setPassword(
                    event.target.value,
                  )
                }
              />

              <div className="sync-login-actions">
                <button
                  className="primary-btn"
                  onClick={login}
                >
                  <LogIn size={15}/>
                  Entrar
                </button>

                <button
                  className="secondary-btn"
                  onClick={register}
                >
                  Crear cuenta
                </button>
              </div>

              {
                message
                && (
                  <small>
                    {message}
                  </small>
                )
              }
            </section>
          )
          : (
            <>
              <div className="sync-grid">
                <section className="panel sync-card">
                  <div className="sync-card-icon">
                    {
                      runtime
                      === 'desktop'
                        ? <Laptop/>
                        : <Smartphone/>
                    }
                  </div>

                  <span className="eyebrow">
                    DISPOSITIVO
                  </span>

                  <h2>
                    {
                      runtime
                      === 'desktop'
                        ? 'Publisher Desktop'
                        : 'Publisher Web/PWA'
                    }
                  </h2>

                  <p>
                    {
                      runtime
                        .toUpperCase()
                    }
                  </p>
                </section>

                <section className="panel sync-card">
                  <div className="sync-card-icon">
                    <CheckCircle2/>
                  </div>

                  <span className="eyebrow">
                    SUPABASE
                  </span>

                  <h2>
                    Conectado
                  </h2>

                  <p>
                    {userEmail}
                  </p>

                  <small>
                    workspace_key:
                    {' '}
                    abraxas-publisher
                  </small>
                </section>
              </div>

              <section className="panel">
                <h3>
                  Qué se comparte
                </h3>

                <div className="capability-table">
                  <div>
                    <span>
                      Marcas y contenidos
                    </span>
                    <b>
                      Desktop + Web
                    </b>
                  </div>

                  <div>
                    <span>
                      Estados y correcciones
                    </span>
                    <b>
                      Desktop + Web
                    </b>
                  </div>

                  <div>
                    <span>
                      Calendario
                    </span>
                    <b>
                      Desktop + Web
                    </b>
                  </div>

                  <div>
                    <span>
                      Cuentas metadata
                    </span>
                    <b>
                      Desktop + Web
                    </b>
                  </div>

                  <div>
                    <span>
                      Cola de publicación
                    </span>
                    <b>
                      Desktop + Web
                    </b>
                  </div>

                  <div>
                    <span>
                      Paths locales / ffmpeg
                    </span>
                    <b>
                      Sólo Desktop
                    </b>
                  </div>
                </div>
              </section>

              <button
                className="danger-text-btn"
                onClick={logout}
              >
                <LogOut size={14}/>
                Cerrar sesión
              </button>

              {
                message
                && (
                  <div className="hybrid-success">
                    {message}
                  </div>
                )
              }
            </>
          )
      }
    </div>
  )
}
