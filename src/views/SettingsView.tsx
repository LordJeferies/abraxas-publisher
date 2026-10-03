import {
  Cloud,
  Save,
} from 'lucide-react'

import {
  useEffect,
  useState,
} from 'react'

import {
  backend,
} from '../lib/backend'

import type {
  HealthReport,
} from '../types'

export function SettingsView() {
  const [
    health,
    setHealth,
  ] =
    useState<
      HealthReport | null
    >(null)

  const [
    clientId,
    setClientId,
  ] =
    useState('')

  const [
    connected,
    setConnected,
  ] =
    useState(false)

  const [
    message,
    setMessage,
  ] =
    useState('')

  useEffect(
    () => {
      backend.health()
        .then(setHealth)
        .catch(() => {})

      backend.getDriveClientId()
        .then(
          (id) =>
            setClientId(
              id || '',
            ),
        )
        .catch(() => {})

      backend.driveStatus()
        .then(setConnected)
        .catch(() => {})
    },
    [],
  )

  const save =
    async () => {
      await backend.setDriveClientId(
        clientId.trim(),
      )

      setMessage(
        'Configuración guardada.',
      )
    }

  const connect =
    async () => {
      try {
        await backend.setDriveClientId(
          clientId.trim(),
        )

        const result =
          await backend.driveConnect(
            clientId.trim(),
          )

        setConnected(
          result.connected,
        )

        setMessage(
          result.message,
        )
      } catch (e) {
        setMessage(
          String(e),
        )
      }
    }

  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            SISTEMA
          </span>

          <h1>
            Ajustes
          </h1>

          <p>
            Diagnóstico local, Google Drive y configuración del workspace.
          </p>
        </div>
      </header>

      <section className="panel settings-panel">
        <h3>
          Doctor
        </h3>

        <div className="health-row">
          <span>
            SQLite
          </span>

          <b>
            {
              health?.database
                ? 'OK'
                : '—'
            }
          </b>
        </div>

        <div className="health-row">
          <span>
            FFmpeg
          </span>

          <b>
            {
              health?.ffmpeg
                ? 'OK'
                : 'No detectado'
            }
          </b>
        </div>

        <div className="health-row">
          <span>
            FFprobe
          </span>

          <b>
            {
              health?.ffprobe
                ? 'OK'
                : 'No detectado'
            }
          </b>
        </div>

        <div className="health-row">
          <span>
            Datos
          </span>

          <small>
            {
              health?.appDataDir
              || '...'
            }
          </small>
        </div>
      </section>

      <section className="panel settings-panel">
        <div className="panel-title-row">
          <div>
            <h3>
              Google Drive directo
            </h3>

            <p>
              {
                connected
                  ? 'Conectado durante esta sesión.'
                  : 'No conectado.'
              }
            </p>
          </div>

          <Cloud
            size={24}
          />
        </div>

        <label className="field-label">
          OAuth Client ID · Desktop
        </label>

        <input
          className="field full-field"
          value={clientId}
          onChange={(e) =>
            setClientId(
              e.target.value,
            )
          }
          placeholder="xxxxxxxx.apps.googleusercontent.com"
        />

        <div className="button-row">
          <button
            className="secondary-btn"
            onClick={save}
          >
            <Save size={14}/>
            Guardar
          </button>

          <button
            className="primary-btn"
            onClick={connect}
            disabled={
              !clientId.trim()
            }
          >
            <Cloud size={14}/>
            Conectar Drive
          </button>
        </div>

        <small className="helper">
          El OAuth se abre en el navegador del sistema mediante loopback local 127.0.0.1.
        </small>
      </section>

      <section className="panel settings-panel">
        <h3>
          Redes sociales
        </h3>

        <div className="disabled-connect">
          Instagram · Facebook · LinkedIn · YouTube

          <span>
            Publicación real continúa desactivada. Esto pertenece al Paso 2.
          </span>
        </div>
      </section>

      {
        message
        && (
          <div className="calendar-message">
            {message}
          </div>
        )
      }
    </div>
  )
}
