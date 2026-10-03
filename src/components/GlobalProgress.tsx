import { useEffect, useState } from 'react'
import { LoaderCircle } from 'lucide-react'

import {
  onProgress,
  type ProgressState,
} from '../lib/progress'

const idle: ProgressState = {
  active: false,
  label: '',
  percent: 0,
  blocking: false,
}

export function GlobalProgress() {
  const [state, setState] =
    useState<ProgressState>(idle)

  useEffect(
    () => onProgress(setState),
    [],
  )

  if (!state.active) return null

  return (
    <>
      <div
        className="global-progress"
        role="status"
        aria-live="polite"
      >
        <div className="global-progress-copy">
          <LoaderCircle
            size={15}
            className="global-progress-spinner"
          />

          <div>
            <strong>{state.label}</strong>
            {
              state.detail
              && <small>{state.detail}</small>
            }
          </div>
        </div>

        <b>{state.percent}%</b>

        <div className="global-progress-track">
          <span
            style={{
              width: `${state.percent}%`,
            }}
          />
        </div>
      </div>

      {
        state.blocking
        && (
          <div className="global-progress-blocker">
            <div className="global-progress-blocker-card">
              <LoaderCircle
                size={28}
                className="global-progress-spinner"
              />

              <strong>{state.label}</strong>
              <p>
                Esta operación necesita terminar antes de continuar.
                Publisher se desbloqueará automáticamente.
              </p>
            </div>
          </div>
        )
      }
    </>
  )
}
