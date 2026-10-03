import {
  isTauriRuntime,
} from './lib/runtime'

export function registerPwa() {
  if (
    isTauriRuntime()
    || !(
      'serviceWorker'
      in navigator
    )
  ) {
    return
  }

  window.addEventListener(
    'load',
    () => {
      navigator
        .serviceWorker
        .register(
          `${import.meta.env.BASE_URL}sw.js`,
        )
        .catch(
          console.error,
        )
    },
  )
}
