import type {
  ActivityEvent,
  Brand,
  ConnectedAccount,
  ContentItem,
  PublishJob,
} from '../types'

import {
  getPortableSnapshot,
  replacePortableSnapshot,
  type PortableSnapshot,
} from './webBackend'

import {
  cloudUser,
  getPublisherChannel,
  PUBLISHER_WORKSPACE,
  setPublisherChannel,
  supabaseClient,
} from './supabase'

let pushTimer:
  number | undefined

let pushing = false
let applyingRemote = false

type SyncMeta = {
  revision: number
  baseRevision: number
  deviceId: string
  productVersion: string
  updatedAt: string
}

type UnknownPayload =
  Record<string, unknown>

function now() {
  return new Date()
    .toISOString()
}

function isUnknownPayload(
  value: unknown,
): value is UnknownPayload {
  return (
    typeof value === 'object'
    && value !== null
    && !Array.isArray(value)
  )
}

function byId<T extends { id: string }>(
  remote: T[] = [],
  local: T[] = [],
): T[] {
  const map =
    new Map<string, T>()

  for (const item of remote) {
    map.set(
      item.id,
      item,
    )
  }

  for (const item of local) {
    const previous =
      map.get(item.id)

    map.set(
      item.id,
      {
        ...(previous || {}),
        ...item,
      } as T,
    )
  }

  return Array.from(
    map.values(),
  )
}

function mergeTargets(
  remote: ContentItem,
  local: ContentItem,
) {
  const targetMap =
    new Map(
      (remote.targets || [])
        .map(
          (target) => [
            target.id,
            target,
          ],
        ),
    )

  for (
    const target
    of local.targets || []
  ) {
    const previous =
      targetMap.get(
        target.id,
      )

    targetMap.set(
      target.id,
      {
        ...(previous || {}),
        ...target,
      },
    )
  }

  return Array.from(
    targetMap.values(),
  )
}

function mergeMedia(
  remote: ContentItem,
  local: ContentItem,
) {
  const mediaMap =
    new Map(
      (remote.media || [])
        .map(
          (media) => [
            media.id,
            media,
          ],
        ),
    )

  for (
    const media
    of local.media || []
  ) {
    const previous =
      mediaMap.get(
        media.id,
      )

    mediaMap.set(
      media.id,
      {
        ...(previous || {}),
        ...media,
      },
    )
  }

  return Array.from(
    mediaMap.values(),
  )
}

function mergeContents(
  remote: ContentItem[] = [],
  local: ContentItem[] = [],
) {
  const map =
    new Map<string, ContentItem>()

  for (
    const item
    of remote
  ) {
    map.set(
      item.id,
      item,
    )
  }

  for (
    const item
    of local
  ) {
    const previous =
      map.get(
        item.id,
      )

    if (!previous) {
      map.set(
        item.id,
        item,
      )

      continue
    }

    map.set(
      item.id,
      {
        ...previous,
        ...item,

        media:
          mergeMedia(
            previous,
            item,
          ),

        targets:
          mergeTargets(
            previous,
            item,
          ),
      },
    )
  }

  return Array.from(
    map.values(),
  )
}

function numberValue(
  value: unknown,
) {
  const parsed =
    Number(value)

  return Number.isFinite(
    parsed,
  )
    ? parsed
    : 0
}

function nextMeta(
  remoteMeta:
    Partial<SyncMeta>
    | undefined,

  localMeta:
    SyncMeta,
): SyncMeta {
  const remoteRevision =
    numberValue(
      remoteMeta
        ?.revision,
    )

  const remoteBase =
    numberValue(
      remoteMeta
        ?.baseRevision,
    )

  const localRevision =
    numberValue(
      localMeta
        .revision,
    )

  const localBase =
    numberValue(
      localMeta
        .baseRevision,
    )

  return {
    revision:
      Math.max(
        remoteRevision,
        remoteBase,
        localRevision,
        localBase,
      ) + 1,

    baseRevision:
      remoteRevision,

    deviceId:
      localMeta.deviceId,

    productVersion:
      'publisher-1.3.2',

    updatedAt:
      now(),
  }
}

/*
 * Publisher tiene su propio workspace.
 *
 * Aun así conservamos campos root desconocidos
 * que puedan aparecer en futuras versiones.
 */
function buildMergedPayload(
  remoteRaw:
    UnknownPayload
    | null,

  local:
    PortableSnapshot,
) {
  const remote =
    (
      remoteRaw || {}
    ) as
      UnknownPayload
      & Partial<PortableSnapshot>

  const remoteMeta =
    (
      remote.syncMeta
      || {}
    ) as
      Partial<SyncMeta>

  const merged:
    UnknownPayload
    & PortableSnapshot = {
    ...remote,

    version: 1,

    brands:
      byId<Brand>(
        remote.brands || [],
        local.brands || [],
      ),

    contents:
      mergeContents(
        remote.contents || [],
        local.contents || [],
      ),

    accounts:
      byId<ConnectedAccount>(
        remote.accounts || [],
        local.accounts || [],
      ),

    publicationJobs:
      byId<PublishJob>(
        remote.publicationJobs
          || [],
        local.publicationJobs
          || [],
      ),

    activity:
      byId<ActivityEvent>(
        remote.activity || [],
        local.activity || [],
      )
        .sort(
          (a, b) =>
            b.createdAt
              .localeCompare(
                a.createdAt,
              ),
        )
        .slice(
          0,
          500,
        ),

    syncMeta:
      nextMeta(
        remoteMeta,
        local.syncMeta,
      ),
  }

  return merged
}

export async function pullPublisher(
  silent = false,
) {
  const supabase =
    supabaseClient()

  const user =
    await cloudUser()

  if (
    !supabase
    || !user
  ) {
    return false
  }

  const response =
    await supabase
      .from(
        'editorial_state',
      )
      .select(
        'payload,updated_at',
      )
      .eq(
        'user_id',
        user.id,
      )
      .eq(
        'workspace_key',
        PUBLISHER_WORKSPACE,
      )
      .maybeSingle()

  if (response.error) {
    if (!silent) {
      throw response.error
    }

    console.error(
      'Publisher pull:',
      response.error,
    )

    return false
  }

  const raw =
    response.data
      ?.payload

  if (
    !raw
    || typeof raw
      !== 'object'
  ) {
    return false
  }

  const remote =
    raw as
      unknown as
      PortableSnapshot

  const local =
    getPortableSnapshot()

  const remoteRevision =
    numberValue(
      remote.syncMeta
        ?.revision,
    )

  applyingRemote =
    true

  try {
    replacePortableSnapshot({
      version: 1,

      brands:
        remote.brands || [],

      contents:
        remote.contents || [],

      accounts:
        remote.accounts || [],

      publicationJobs:
        remote.publicationJobs
        || [],

      activity:
        remote.activity || [],

      syncMeta: {
        revision:
          remoteRevision,

        baseRevision:
          remoteRevision,

        deviceId:
          local.syncMeta
            .deviceId,

        productVersion:
          'publisher-1.3.2',

        updatedAt:
          remote.syncMeta
            ?.updatedAt
          || now(),
      },
    })
  } finally {
    applyingRemote =
      false
  }

  return true
}

export async function pushPublisher(
  silent = false,
) {
  if (
    pushing
    || applyingRemote
    || !navigator.onLine
  ) {
    return false
  }

  const supabase =
    supabaseClient()

  const user =
    await cloudUser()

  if (
    !supabase
    || !user
  ) {
    return false
  }

  pushing = true

  try {
    const response =
      await supabase
        .from(
          'editorial_state',
        )
        .select(
          'payload,updated_at',
        )
        .eq(
          'user_id',
          user.id,
        )
        .eq(
          'workspace_key',
          PUBLISHER_WORKSPACE,
        )
        .maybeSingle()

    if (response.error) {
      if (!silent) {
        throw response.error
      }

      console.error(
        'Publisher read before push:',
        response.error,
      )

      return false
    }

    const remoteRaw =
      response.data
        ?.payload

    const remote =
      isUnknownPayload(
        remoteRaw,
      )
        ? remoteRaw
        : null

    const local =
      getPortableSnapshot()

    const merged =
      buildMergedPayload(
        remote,
        local,
      )

    const upsert =
      await supabase
        .from(
          'editorial_state',
        )
        .upsert(
          {
            user_id:
              user.id,

            workspace_key:
              PUBLISHER_WORKSPACE,

            payload:
              merged,

            updated_at:
              now(),
          },
          {
            onConflict:
              'user_id,workspace_key',
          },
        )

    if (upsert.error) {
      if (!silent) {
        throw upsert.error
      }

      console.error(
        'Publisher push:',
        upsert.error,
      )

      return false
    }

    applyingRemote =
      true

    try {
      replacePortableSnapshot(
        merged,
      )
    } finally {
      applyingRemote =
        false
    }

    return true
  } finally {
    pushing = false
  }
}

export function schedulePublisherPush() {
  if (applyingRemote) {
    return
  }

  if (
    pushTimer !== undefined
  ) {
    window.clearTimeout(
      pushTimer,
    )
  }

  pushTimer =
    window.setTimeout(
      () => {
        pushPublisher(
          true,
        ).catch(
          console.error,
        )
      },
      900,
    )
}

function applyRealtimePayload(
  raw: unknown,
) {
  if (
    !raw
    || typeof raw
      !== 'object'
  ) {
    return
  }

  const remote =
    raw as PortableSnapshot

  const local =
    getPortableSnapshot()

  const remoteRevision =
    numberValue(
      remote.syncMeta
        ?.revision,
    )

  const localRevision =
    numberValue(
      local.syncMeta
        ?.revision,
    )

  if (
    remoteRevision
    <= localRevision
  ) {
    return
  }

  applyingRemote =
    true

  try {
    replacePortableSnapshot({
      version: 1,

      brands:
        remote.brands
        || [],

      contents:
        remote.contents
        || [],

      accounts:
        remote.accounts
        || [],

      publicationJobs:
        remote.publicationJobs
        || [],

      activity:
        remote.activity
        || [],

      syncMeta: {
        revision:
          remoteRevision,

        baseRevision:
          remoteRevision,

        deviceId:
          local.syncMeta
            .deviceId,

        productVersion:
          'publisher-1.3.2',

        updatedAt:
          remote.syncMeta
            ?.updatedAt
          || now(),
      },
    })
  } finally {
    applyingRemote =
      false
  }
}

export async function subscribePublisher() {
  const supabase =
    supabaseClient()

  const user =
    await cloudUser()

  if (!supabase || !user) {
    return false
  }

  const previous =
    getPublisherChannel()

  if (previous) {
    await supabase.removeChannel(
      previous,
    )
  }

  const channelName =
    `abraxas-publisher-${user.id}`

  const channel =
    supabase.channel(
      channelName,
    )

  channel.on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'editorial_state',
      filter:
        `user_id=eq.${user.id}`,
    },
    (event: any) => {
      const row =
        event?.new

      if (!row) {
        return
      }

      if (
        row.workspace_key
        !== PUBLISHER_WORKSPACE
      ) {
        return
      }

      if (!row.payload) {
        return
      }

      applyRealtimePayload(
        row.payload,
      )
    },
  )

  channel.subscribe()

  setPublisherChannel(
    channel,
  )

  return true
}

export async function initializePublisherSync() {
  const user =
    await cloudUser()

  if (!user) {
    return false
  }

  /*
   * Primera entrada:
   *
   * Si Cloud tiene estado, se recupera.
   * Si no tiene fila todavía, subimos
   * el estado local actual.
   */
  const pulled =
    await pullPublisher(
      true,
    )

  if (!pulled) {
    await pushPublisher(
      true,
    )
  }

  await subscribePublisher()

  return true
}

window.addEventListener(
  'online',
  () => {
    pushPublisher(
      true,
    ).catch(
      console.error,
    )
  },
)

window.addEventListener(
  'abraxas-portable-changed',
  () => {
    schedulePublisherPush()
  },
)
