import type {
  ActivityEvent,
  Brand,
  ConnectedAccount,
  ContentItem,
  CorrectionNote,
  DriveAuthResult,
  DriveItem,
  EnqueueInput,
  ExternalPublication,
  HealthReport,
  ImportPreview,
  PreflightReport,
  PublishJob,
  RefreshResult,
  SaveAccountInput,
  ScanResult,
  ScheduleChange,
  SimulationReport,
} from '../types'

import {
  webDrive,
} from './webDrive'

const PREFIX =
  'abraxas.publisher.'

export interface PortableSnapshot {
  version: number
  brands: Brand[]
  contents: ContentItem[]
  accounts: ConnectedAccount[]
  publicationJobs: PublishJob[]
  activity: ActivityEvent[]

  syncMeta: {
    revision: number
    baseRevision: number
    deviceId: string
    productVersion: string
    updatedAt: string
  }
}

function read<T>(
  key: string,
  fallback: T,
): T {
  try {
    const value =
      localStorage.getItem(
        PREFIX + key,
      )

    return value
      ? JSON.parse(value)
      : fallback
  } catch {
    return fallback
  }
}

function write<T>(
  key: string,
  value: T,
) {
  localStorage.setItem(
    PREFIX + key,
    JSON.stringify(value),
  )

  window.dispatchEvent(
    new CustomEvent(
      'abraxas-portable-changed',
    ),
  )
}

function now() {
  return new Date()
    .toISOString()
}

function uid(
  prefix: string,
) {
  return (
    `${prefix}-${crypto.randomUUID()}`
  )
}

function deviceId() {
  const key =
    PREFIX + 'deviceId'

  let value =
    localStorage.getItem(
      key,
    )

  if (!value) {
    value =
      crypto.randomUUID()

    localStorage.setItem(
      key,
      value,
    )
  }

  return value
}

export function getPortableSnapshot():
  PortableSnapshot {
  const meta =
    read(
      'syncMeta',
      {
        revision: 0,
        baseRevision: 0,
        deviceId:
          deviceId(),
        productVersion:
          'publisher-1.3.2',
        updatedAt:
          now(),
      },
    )

  return {
    version: 1,

    brands:
      read<Brand[]>(
        'brands',
        [],
      ),

    contents:
      read<ContentItem[]>(
        'contents',
        [],
      ),

    accounts:
      read<ConnectedAccount[]>(
        'accounts',
        [],
      ),

    publicationJobs:
      read<PublishJob[]>(
        'jobs',
        [],
      ),

    activity:
      read<ActivityEvent[]>(
        'activity',
        [],
      ),

    syncMeta:
      meta,
  }
}

export function replacePortableSnapshot(
  snapshot:
    PortableSnapshot,
) {
  write(
    'brands',
    snapshot.brands || [],
  )

  write(
    'contents',
    snapshot.contents || [],
  )

  write(
    'accounts',
    snapshot.accounts || [],
  )

  write(
    'jobs',
    snapshot.publicationJobs || [],
  )

  write(
    'activity',
    snapshot.activity || [],
  )

  write(
    'syncMeta',
    snapshot.syncMeta,
  )

  window.dispatchEvent(
    new CustomEvent(
      'abraxas-portable-updated',
    ),
  )
}

export function mergePortableContents(
  incoming:
    ContentItem[],
) {
  const snapshot =
    getPortableSnapshot()

  const map =
    new Map(
      snapshot.contents.map(
        (item) => [
          item.id,
          item,
        ],
      ),
    )

  for (
    const content
    of incoming
  ) {
    map.set(
      content.id,
      {
        ...map.get(
          content.id,
        ),
        ...content,
      },
    )
  }

  snapshot.contents =
    [...map.values()]

  snapshot.syncMeta.updatedAt =
    now()

  replacePortableSnapshot(
    snapshot,
  )
}

export function mergePortableBrands(
  incoming:
    Brand[],
) {
  const snapshot =
    getPortableSnapshot()

  const map =
    new Map(
      snapshot.brands.map(
        (brand) => [
          brand.id,
          brand,
        ],
      ),
    )

  for (
    const brand
    of incoming
  ) {
    map.set(
      brand.id,
      brand,
    )
  }

  snapshot.brands =
    [...map.values()]

  replacePortableSnapshot(
    snapshot,
  )
}

function logActivity(
  action: string,
  entityType: string,
  entityId: string,
  label: string,
) {
  const list =
    read<ActivityEvent[]>(
      'activity',
      [],
    )

  list.unshift({
    id:
      uid('activity'),
    action,
    entityType,
    entityId,
    label,
    beforeJson: null,
    afterJson: null,
    reversible: false,
    remote: false,
    undone: false,
    createdAt:
      now(),
  })

  write(
    'activity',
    list.slice(
      0,
      500,
    ),
  )
}

function updateContent(
  id: string,
  fn:
    (
      value:
        ContentItem,
    ) => ContentItem,
) {
  const list =
    read<ContentItem[]>(
      'contents',
      [],
    )

  let changed =
    false

  const next =
    list.map(
      (item) => {
        if (
          item.id !== id
        ) {
          return item
        }

        changed = true

        return fn(item)
      },
    )

  write(
    'contents',
    next,
  )

  return changed
}

export const webBackend = {
  listConnectedAccounts:
    async () =>
      read<
        ConnectedAccount[]
      >(
        'accounts',
        [],
      ),

  saveConnectedAccount:
    async (
      input:
        SaveAccountInput,
    ) => {
      const list =
        read<
          ConnectedAccount[]
        >(
          'accounts',
          [],
        )

      const id =
        input.id
        || uid('account')

      const previous =
        list.find(
          (item) =>
            item.id === id,
        )

      const item:
        ConnectedAccount = {
          id,
          provider:
            input.provider,
          brand:
            input.brand,
          displayName:
            input.displayName,
          handle:
            input.handle,
          accountKind:
            input.accountKind,
          connectionStatus:
            input.connectionStatus,
          authState:
            input.authState,
          capabilitiesJson:
            input.capabilitiesJson,
          externalReference:
            input.externalReference,
          lastVerifiedAt:
            previous
              ?.lastVerifiedAt
            || null,
          lastError:
            previous
              ?.lastError
            || null,
          createdAt:
            previous
              ?.createdAt
            || now(),
          updatedAt:
            now(),
        }

      write(
        'accounts',
        [
          ...list.filter(
            (x) =>
              x.id !== id,
          ),
          item,
        ],
      )

      return item
    },

  removeConnectedAccount:
    async (
      accountId: string,
    ) => {
      const list =
        read<
          ConnectedAccount[]
        >(
          'accounts',
          [],
        )

      const next =
        list.filter(
          (item) =>
            item.id
            !== accountId,
        )

      write(
        'accounts',
        next,
      )

      return (
        next.length
        !== list.length
      )
    },

  listPublicationJobs:
    async () =>
      read<
        PublishJob[]
      >(
        'jobs',
        [],
      ),

  publishingPreflight:
    async (
      targetId: string,
      accountId?:
        string | null,
    ):
      Promise<
        PreflightReport
      > => {
      const contents =
        read<ContentItem[]>(
          'contents',
          [],
        )

      const content =
        contents.find(
          (item) =>
            item.targets
              .some(
                (target) =>
                  target.id
                  === targetId,
              ),
        )

      const target =
        content?.targets
          .find(
            (item) =>
              item.id
              === targetId,
          )

      if (
        !content
        || !target
      ) {
        throw new Error(
          'Destino no encontrado.',
        )
      }

      const accounts =
        read<
          ConnectedAccount[]
        >(
          'accounts',
          [],
        )

      const account =
        accounts.find(
          (item) =>
            item.id
            === accountId,
        )

      const auto =
        Boolean(
          account
          && account.connectionStatus
            === 'CONNECTED'
          && account.authState
            === 'AUTHORIZED',
        )

      const checks = [
        {
          key:
            'editorial',
          label:
            'Contenido aprobado',
          ok:
            content.status
              === 'LISTO_POR_PROGRAMAR'
            || content.status
              === 'PROGRAMADO',
          blocking:
            true,
          detail:
            content.status,
        },

        {
          key:
            'media',
          label:
            'Medio disponible',
          ok:
            content.media.length
            > 0,
          blocking:
            true,
          detail:
            `${content.media.length} asset(s)`,
        },

        {
          key:
            'schedule',
          label:
            'Fecha/hora definida',
          ok:
            Boolean(
              target.scheduledAt,
            ),
          blocking:
            true,
          detail:
            target.scheduledAt,
        },

        {
          key:
            'account',
          label:
            auto
              ? 'API autorizada'
              : 'Publicación manual válida',
          ok:
            true,
          blocking:
            false,
          detail:
            account?.displayName
            || 'Sin API',
        },
      ]

      return {
        targetId,
        accountId,
        provider:
          target.platform,
        ready:
          checks
            .filter(
              (check) =>
                check.blocking,
            )
            .every(
              (check) =>
                check.ok,
            ),
        executionMode:
          auto
            ? 'AUTO_API'
            : 'MANUAL',
        needsManualAction:
          !auto,
        checks,
      }
    },

  enqueuePublications:
    async (
      inputs:
        EnqueueInput[],
    ) => {
      const contents =
        read<ContentItem[]>(
          'contents',
          [],
        )

      const existing =
        read<PublishJob[]>(
          'jobs',
          [],
        )

      const map =
        new Map(
          existing.map(
            (job) => [
              job.idempotencyKey,
              job,
            ],
          ),
        )

      for (
        const input
        of inputs
      ) {
        const content =
          contents.find(
            (item) =>
              item.targets
                .some(
                  (target) =>
                    target.id
                    === input.targetId,
                ),
          )

        const target =
          content?.targets
            .find(
              (item) =>
                item.id
                === input.targetId,
            )

        if (
          !content
          || !target
        ) {
          continue
        }

        const key =
          [
            input.targetId,
            input.accountId || '',
            target.scheduledAt || '',
            content.sourceFingerprint || '',
            input.mode,
          ].join(':')

        const existingJob =
          map.get(key)

        const mode =
          input.mode
          || 'MANUAL'

        const item:
          PublishJob = {
          id:
            existingJob?.id
            || uid('job'),
          targetId:
            input.targetId,
          contentId:
            content.id,
          provider:
            target.platform,
          accountId:
            input.accountId,
          mode,
          scheduledFor:
            target.scheduledAt,
          status:
            mode === 'AUTO_API'
              ? 'QUEUED'
              : mode === 'EXTERNAL'
                ? 'SCHEDULED_EXTERNAL'
                : 'MANUAL_REQUIRED',
          idempotencyKey:
            key,
          attempt:
            existingJob?.attempt
            || 0,
          maxAttempts: 4,
          remoteId:
            existingJob?.remoteId
            || null,
          remoteUrl:
            existingJob?.remoteUrl
            || null,
          lastErrorCode:
            null,
          lastErrorMessage:
            null,
          createdAt:
            existingJob
              ?.createdAt
            || now(),
          updatedAt:
            now(),
        }

        map.set(
          key,
          item,
        )
      }

      const jobs =
        [...map.values()]

      write(
        'jobs',
        jobs,
      )

      return jobs
    },

  markScheduledExternal:
    async (
      targetId: string,
      method: string,
      scheduledAt?:
        string | null,
      remoteUrl?:
        string | null,
      note?:
        string | null,
    ):
      Promise<
        ExternalPublication
      > => {
      const contents =
        read<ContentItem[]>(
          'contents',
          [],
        )

      let provider = ''

      const next =
        contents.map(
          (content) => ({
            ...content,

            targets:
              content.targets.map(
                (target) => {
                  if (
                    target.id
                    !== targetId
                  ) {
                    return target
                  }

                  provider =
                    target.platform

                  return {
                    ...target,
                    status:
                      'SCHEDULED_EXTERNAL',
                    scheduledAt:
                      scheduledAt
                      || target
                        .scheduledAt,
                    scheduleSource:
                      'EXTERNAL',
                  }
                },
              ),
          }),
        )

      write(
        'contents',
        next,
      )

      return {
        id:
          uid('external'),
        targetId,
        provider,
        method,
        scheduledAt,
        remoteUrl,
        note,
        createdAt:
          now(),
      }
    },

  health:
    async ():
      Promise<
        HealthReport
      > => ({
      database: true,
      ffmpeg: false,
      ffprobe: false,
      appDataDir:
        'Portable browser workspace',
    }),

  listBrands:
    async () =>
      read<Brand[]>(
        'brands',
        [],
      ),

  createBrand:
    async (
      name: string,
    ) => {
      const brands =
        read<Brand[]>(
          'brands',
          [],
        )

      const existing =
        brands.find(
          (item) =>
            item.name
              .toLowerCase()
            === name
              .trim()
              .toLowerCase(),
        )

      if (existing) {
        return existing
      }

      const brand:
        Brand = {
        id:
          uid('brand'),
        name:
          name.trim(),
        createdAt:
          now(),
      }

      write(
        'brands',
        [
          ...brands,
          brand,
        ],
      )

      return brand
    },

  previewImportLocal:
    async (
      _path: string,
      _brand: string,
    ) => {
      throw new Error(
        'La importación desde carpetas locales requiere Desktop.',
      )
    },

  commitImportLocal:
    async (
      _path: string,
      _brand: string,
      _duplicatePolicy:
        'replace'
        | 'keep'
        | 'skip',
    ) => {
      throw new Error(
        'La importación local requiere Desktop.',
      )
    },

  importFolder:
    async (
      _path: string,
    ) => {
      throw new Error(
        'La importación local requiere Desktop.',
      )
    },

  listContents:
    async () =>
      read<ContentItem[]>(
        'contents',
        [],
      ),

  updateSchedule:
    async (
      targetId: string,
      scheduledAt:
        string | null,
    ) => {
      const list =
        read<ContentItem[]>(
          'contents',
          [],
        )

      let changed =
        false

      const next =
        list.map(
          (content) => ({
            ...content,

            targets:
              content.targets.map(
                (target) => {
                  if (
                    target.id
                    !== targetId
                  ) {
                    return target
                  }

                  changed = true

                  return {
                    ...target,
                    scheduledAt,
                    scheduleSource:
                      scheduledAt
                        ? 'LOCAL'
                        : null,
                  }
                },
              ),
          }),
        )

      write(
        'contents',
        next,
      )

      return changed
    },

  updateSchedules:
    async (
      changes:
        ScheduleChange[],
    ) => {
      let total = 0

      for (
        const change
        of changes
      ) {
        if (
          await webBackend
            .updateSchedule(
              change.targetId,
              change.scheduledAt,
            )
        ) {
          total += 1
        }
      }

      return total
    },

  updateWorkflowStatus:
    async (
      contentId: string,
      status: string,
    ) => {
      const changed =
        updateContent(
          contentId,
          (content) => ({
            ...content,
            status,
          }),
        )

      if (changed) {
        logActivity(
          'STATUS',
          'content',
          contentId,
          status,
        )
      }

      return changed
    },

  saveCorrectionNote:
    async (
      contentId: string,
      note: string,
      status: string,
    ):
      Promise<
        CorrectionNote
      > => {
      const correction:
        CorrectionNote = {
        id:
          uid('note'),
        body:
          note,
        createdAt:
          now(),
      }

      updateContent(
        contentId,
        (content) => ({
          ...content,
          status,
          latestNote:
            correction,
        }),
      )

      return correction
    },

  refreshContent:
    async (
      contentId: string,
    ):
      Promise<
        RefreshResult
      > => {
      const content =
        read<ContentItem[]>(
          'contents',
          [],
        ).find(
          (item) =>
            item.id
            === contentId,
        )

      if (!content) {
        throw new Error(
          'Contenido no encontrado.',
        )
      }

      return {
        content,
        changed: false,
        previousVersion:
          content.version,
        currentVersion:
          content.version,
        message:
          'En Web/PWA la referencia cloud no requiere refresh local.',
      }
    },

  listActivity:
    async () =>
      read<ActivityEvent[]>(
        'activity',
        [],
      ),

  undo:
    async () =>
      null,

  redo:
    async () =>
      null,

  getDriveClientId:
    async () =>
      localStorage.getItem(
        PREFIX
        + 'driveWebClientId',
      ),

  setDriveClientId:
    async (
      clientId: string,
    ) => {
      localStorage.setItem(
        PREFIX
        + 'driveWebClientId',
        clientId,
      )

      return true
    },

  driveStatus:
    async () =>
      webDrive.connected(),

  driveConnect:
    async (
      clientId: string,
    ):
      Promise<
        DriveAuthResult
      > => {
      await webDrive.prepare()

      await webDrive.connect(
        clientId,
      )

      return {
        connected: true,
        message:
          'Google Drive conectado.',
      }
    },

  driveList:
    async (
      folderId =
        'root',
    ):
      Promise<
        DriveItem[]
      > =>
      webDrive.list(
        folderId,
      ),

  drivePreviewFolder:
    async (
      folderId: string,
      brand: string,
    ):
      Promise<
        ImportPreview
      > =>
      webDrive.previewFolder(
        folderId,
        brand,
      ),

  driveImportFolder:
    async (
      folderId: string,
      brand: string,
      duplicatePolicy:
        'replace'
        | 'keep'
        | 'skip',
    ):
      Promise<
        ScanResult
      > => {
      const preview =
        await webDrive
          .previewFolder(
            folderId,
            brand,
          )

      const existing =
        read<ContentItem[]>(
          'contents',
          [],
        )

      const map =
        new Map(
          existing.map(
            (item) => [
              item.id,
              item,
            ],
          ),
        )

      let imported = 0

      for (
        const item
        of preview.contents
      ) {
        const found =
          map.get(
            item.id,
          )

        if (
          found
          && duplicatePolicy
            === 'skip'
        ) {
          continue
        }

        if (
          found
          && duplicatePolicy
            === 'keep'
        ) {
          const copy = {
            ...item,
            id:
              uid('drive'),
            title:
              `${item.title} · copia`,
          }

          map.set(
            copy.id,
            copy,
          )
        } else {
          map.set(
            item.id,
            item,
          )
        }

        imported += 1
      }

      const contents =
        [...map.values()]

      write(
        'contents',
        contents,
      )

      return {
        rootPath:
          `drive://${folderId}`,
        importedCount:
          imported,
        contents,
        warnings:
          preview.warnings,
        errors:
          preview.errors,
      }
    },

  simulateBatch:
    async ():
      Promise<
        SimulationReport
      > => {
      const targets =
        read<ContentItem[]>(
          'contents',
          [],
        )
          .flatMap(
            (item) =>
              item.targets,
          )

      return {
        totalTargets:
          targets.length,
        ready:
          targets.filter(
            (target) =>
              Boolean(
                target.scheduledAt,
              ),
          ).length,
        warnings:
          targets.filter(
            (target) =>
              !target.scheduledAt,
          ).length,
        errors: 0,
        generatedAt:
          now(),
        platforms: [],
        note:
          'Simulación portable.',
      }
    },

  clearWorkspace:
    async () => {
      for (
        const key
        of Object.keys(
          localStorage,
        )
      ) {
        if (
          key.startsWith(
            PREFIX,
          )
        ) {
          localStorage
            .removeItem(key)
        }
      }

      return true
    },
}
