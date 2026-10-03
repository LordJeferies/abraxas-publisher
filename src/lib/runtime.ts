export type RuntimeSurface =
  | 'desktop'
  | 'web'
  | 'pwa'

export type ExecutionHost =
  | 'DESKTOP'
  | 'CLOUD'
  | 'MANUAL'

export function isTauriRuntime() {
  return (
    typeof window !== 'undefined'
    && (
      '__TAURI_INTERNALS__' in window
      || '__TAURI__' in window
    )
  )
}

export function isStandalonePwa() {
  if (
    typeof window === 'undefined'
  ) {
    return false
  }

  return (
    window.matchMedia(
      '(display-mode: standalone)',
    ).matches
    || (
      'standalone' in navigator
      && Boolean(
        (
          navigator as Navigator
          & {
            standalone?: boolean
          }
        ).standalone,
      )
    )
  )
}

export function runtimeSurface():
  RuntimeSurface {
  if (isTauriRuntime()) {
    return 'desktop'
  }

  if (isStandalonePwa()) {
    return 'pwa'
  }

  return 'web'
}

export function cloudEndpoint() {
  return (
    import.meta.env
      .VITE_ABRAXAS_SYNC_API
    || ''
  ).replace(
    /\/$/,
    '',
  )
}

export function cloudConfigured() {
  return Boolean(
    cloudEndpoint(),
  )
}
