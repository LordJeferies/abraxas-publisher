import {
  cloudConfigured,
  cloudEndpoint,
  runtimeSurface,
} from './runtime'

export interface DeviceInfo {
  id: string
  name: string
  runtime:
    'desktop'
    | 'web'
    | 'pwa'
  lastSeen: string
  online: boolean
}

export interface RemoteTask {
  id: string
  type: string

  executionHost:
    'DESKTOP'
    | 'CLOUD'
    | 'MANUAL'

  status:
    | 'WAITING_FOR_DESKTOP'
    | 'QUEUED_CLOUD'
    | 'MANUAL_REQUIRED'
    | 'RUNNING'
    | 'DONE'
    | 'FAILED'

  payload:
    Record<
      string,
      unknown
    >

  createdAt: string
}

const DEVICE_KEY =
  'abraxas.deviceId'

export function deviceId() {
  let value =
    localStorage.getItem(
      DEVICE_KEY,
    )

  if (!value) {
    value =
      crypto.randomUUID()

    localStorage.setItem(
      DEVICE_KEY,
      value,
    )
  }

  return value
}

export function localDevice():
  DeviceInfo {
  return {
    id:
      deviceId(),

    name:
      runtimeSurface()
      === 'desktop'
        ? 'ABRAXAS Desktop'
        : runtimeSurface()
          === 'pwa'
          ? 'ABRAXAS PWA'
          : 'ABRAXAS Web',

    runtime:
      runtimeSurface(),

    lastSeen:
      new Date()
        .toISOString(),

    online:
      navigator.onLine,
  }
}

export async function syncHealth() {
  if (
    !cloudConfigured()
  ) {
    return {
      configured: false,
      online:
        navigator.onLine,
      cloud: false,
      message:
        'Cloud Sync todavía no está configurado.',
    }
  }

  try {
    const response =
      await fetch(
        `${cloudEndpoint()}/health`,
        {
          headers: {
            Accept:
              'application/json',
          },
        },
      )

    return {
      configured: true,
      online:
        navigator.onLine,
      cloud:
        response.ok,
      message:
        response.ok
          ? 'Cloud conectado.'
          : `Cloud respondió ${response.status}.`,
    }
  } catch (
    error
  ) {
    return {
      configured: true,
      online:
        navigator.onLine,
      cloud: false,
      message:
        String(error),
    }
  }
}

export async function submitRemoteTask(
  task:
    Omit<
      RemoteTask,
      'id'
      | 'createdAt'
    >,
) {
  const complete:
    RemoteTask = {
    ...task,
    id:
      crypto.randomUUID(),
    createdAt:
      new Date()
        .toISOString(),
  }

  if (
    !cloudConfigured()
  ) {
    const current =
      JSON.parse(
        localStorage.getItem(
          'abraxas.pendingRemoteTasks',
        )
        || '[]',
      ) as
        RemoteTask[]

    current.push(
      complete,
    )

    localStorage.setItem(
      'abraxas.pendingRemoteTasks',
      JSON.stringify(
        current,
      ),
    )

    return complete
  }

  const response =
    await fetch(
      `${cloudEndpoint()}/tasks`,
      {
        method:
          'POST',

        headers: {
          'Content-Type':
            'application/json',
        },

        body:
          JSON.stringify(
            complete,
          ),
      },
    )

  if (
    !response.ok
  ) {
    throw new Error(
      `Sync API respondió ${response.status}`,
    )
  }

  return complete
}
