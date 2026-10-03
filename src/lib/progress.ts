export type ProgressState = {
  active: boolean
  label: string
  detail?: string
  percent: number
  blocking: boolean
}

const EVENT = 'abraxas-progress'

function emit(state: ProgressState) {
  window.dispatchEvent(
    new CustomEvent<ProgressState>(
      EVENT,
      { detail: state },
    ),
  )
}

export function onProgress(
  listener: (state: ProgressState) => void,
) {
  const handler = (event: Event) => {
    const custom = event as CustomEvent<ProgressState>
    listener(custom.detail)
  }

  window.addEventListener(EVENT, handler)

  return () =>
    window.removeEventListener(EVENT, handler)
}

export async function runProgressTask<T>(
  label: string,
  task: () => Promise<T>,
  options?: {
    blocking?: boolean
    detail?: string
  },
): Promise<T> {
  let percent = 8

  emit({
    active: true,
    label,
    detail: options?.detail,
    percent,
    blocking: options?.blocking ?? false,
  })

  const timer = window.setInterval(() => {
    if (percent >= 92) return

    percent = Math.min(
      92,
      percent + Math.max(1, Math.round((92 - percent) / 7)),
    )

    emit({
      active: true,
      label,
      detail: options?.detail,
      percent,
      blocking: options?.blocking ?? false,
    })
  }, 350)

  try {
    const result = await task()

    emit({
      active: true,
      label,
      detail: options?.detail,
      percent: 100,
      blocking: options?.blocking ?? false,
    })

    await new Promise((resolve) =>
      window.setTimeout(resolve, 220),
    )

    return result
  } catch (error) {
    emit({
      active: true,
      label: 'No se pudo completar la operación',
      detail:
        error instanceof Error
          ? error.message
          : String(error),
      percent: 100,
      blocking: false,
    })

    await new Promise((resolve) =>
      window.setTimeout(resolve, 850),
    )

    throw error
  } finally {
    window.clearInterval(timer)

    emit({
      active: false,
      label: '',
      percent: 0,
      blocking: false,
    })
  }
}
