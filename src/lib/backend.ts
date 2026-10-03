import {
  isTauriRuntime,
} from './runtime'

import {
  nativeBackend,
} from './nativeBackend'

import {
  mergePortableBrands,
  mergePortableContents,
  webBackend,
} from './webBackend'

import {
  schedulePublisherPush,
} from './publisherSync'

async function syncNativePortable() {
  if (
    !isTauriRuntime()
  ) {
    return
  }

  const [
    contents,
    brands,
    accounts,
    jobs,
  ] =
    await Promise.all([
      nativeBackend
        .listContents(),

      nativeBackend
        .listBrands(),

      nativeBackend
        .listConnectedAccounts(),

      nativeBackend
        .listPublicationJobs(),
    ])

  mergePortableContents(
    contents,
  )

  mergePortableBrands(
    brands,
  )

  for (
    const account
    of accounts
  ) {
    await webBackend
      .saveConnectedAccount({
        id:
          account.id,
        provider:
          account.provider,
        brand:
          account.brand,
        displayName:
          account.displayName,
        handle:
          account.handle,
        accountKind:
          account.accountKind,
        connectionStatus:
          account.connectionStatus,
        authState:
          account.authState,
        capabilitiesJson:
          account.capabilitiesJson,
        externalReference:
          account.externalReference,
      })
  }

  /*
   * Native jobs are mirrored by re-enqueueing
   * only when the portable queue is empty.
   * Existing portable cloud jobs remain.
   */
  if (
    (
      await webBackend
        .listPublicationJobs()
    ).length === 0
  ) {
    const inputs =
      jobs.map(
        (job) => ({
          targetId:
            job.targetId,
          accountId:
            job.accountId,
          mode:
            job.mode,
        }),
      )

    if (inputs.length) {
      await webBackend
        .enqueuePublications(
          inputs,
        )
    }
  }

  schedulePublisherPush()
}

export async function initializeBackend() {
  if (
    isTauriRuntime()
  ) {
    await syncNativePortable()
  }
}

export const backend = {
  /*
   * PORTABLE DOMAIN
   *
   * Siempre se usa para que Desktop/Web/PWA
   * compartan el mismo workspace.
   */
  listConnectedAccounts:
    webBackend
      .listConnectedAccounts,

  saveConnectedAccount:
    async (
      input:
        Parameters<
          typeof webBackend
            .saveConnectedAccount
        >[0],
    ) => {
      const portable =
        await webBackend
          .saveConnectedAccount(
            input,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .saveConnectedAccount(
              input,
            )
        } catch (
          error
        ) {
          console.error(
            'Native account mirror:',
            error,
          )
        }
      }

      schedulePublisherPush()

      return portable
    },

  removeConnectedAccount:
    async (
      accountId: string,
    ) => {
      const result =
        await webBackend
          .removeConnectedAccount(
            accountId,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .removeConnectedAccount(
              accountId,
            )
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  listPublicationJobs:
    webBackend
      .listPublicationJobs,

  publishingPreflight:
    webBackend
      .publishingPreflight,

  enqueuePublications:
    async (
      inputs:
        Parameters<
          typeof webBackend
            .enqueuePublications
        >[0],
    ) => {
      const result =
        await webBackend
          .enqueuePublications(
            inputs,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .enqueuePublications(
              inputs,
            )
        } catch (
          error
        ) {
          console.error(
            'Native queue mirror:',
            error,
          )
        }
      }

      schedulePublisherPush()

      return result
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
    ) => {
      const result =
        await webBackend
          .markScheduledExternal(
            targetId,
            method,
            scheduledAt,
            remoteUrl,
            note,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .markScheduledExternal(
              targetId,
              method,
              scheduledAt,
              remoteUrl,
              note,
            )
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  listBrands:
    webBackend
      .listBrands,

  createBrand:
    async (
      name: string,
    ) => {
      const result =
        await webBackend
          .createBrand(
            name,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          const native =
            await nativeBackend
              .createBrand(
                name,
              )

          mergePortableBrands([
            native,
          ])
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  listContents:
    webBackend
      .listContents,

  updateSchedule:
    async (
      targetId: string,
      scheduledAt:
        string | null,
    ) => {
      const result =
        await webBackend
          .updateSchedule(
            targetId,
            scheduledAt,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .updateSchedule(
              targetId,
              scheduledAt,
            )
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  updateSchedules:
    async (
      changes:
        Parameters<
          typeof webBackend
            .updateSchedules
        >[0],
    ) => {
      const result =
        await webBackend
          .updateSchedules(
            changes,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .updateSchedules(
              changes,
            )
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  updateWorkflowStatus:
    async (
      contentId: string,
      status: string,
    ) => {
      const result =
        await webBackend
          .updateWorkflowStatus(
            contentId,
            status,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .updateWorkflowStatus(
              contentId,
              status,
            )
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  saveCorrectionNote:
    async (
      contentId: string,
      note: string,
      status: string,
    ) => {
      const result =
        await webBackend
          .saveCorrectionNote(
            contentId,
            note,
            status,
          )

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .saveCorrectionNote(
              contentId,
              note,
              status,
            )
        } catch {}
      }

      schedulePublisherPush()

      return result
    },

  listActivity:
    webBackend
      .listActivity,

  /*
   * NATIVE-ONLY operations
   */
  health:
    () =>
      isTauriRuntime()
        ? nativeBackend
            .health()
        : webBackend
            .health(),

  previewImportLocal:
    async (
      path: string,
      brand: string,
    ) => {
      if (
        !isTauriRuntime()
      ) {
        return webBackend
          .previewImportLocal(
            path,
            brand,
          )
      }

      return nativeBackend
        .previewImportLocal(
          path,
          brand,
        )
    },

  commitImportLocal:
    async (
      path: string,
      brand: string,
      policy:
        'replace'
        | 'keep'
        | 'skip',
    ) => {
      if (
        !isTauriRuntime()
      ) {
        return webBackend
          .commitImportLocal(
            path,
            brand,
            policy,
          )
      }

      const result =
        await nativeBackend
          .commitImportLocal(
            path,
            brand,
            policy,
          )

      mergePortableContents(
        result.contents,
      )

      schedulePublisherPush()

      return result
    },

  importFolder:
    async (
      path: string,
    ) => {
      if (
        !isTauriRuntime()
      ) {
        return webBackend
          .importFolder(
            path,
          )
      }

      const result =
        await nativeBackend
          .importFolder(
            path,
          )

      mergePortableContents(
        result.contents,
      )

      schedulePublisherPush()

      return result
    },

  refreshContent:
    async (
      contentId: string,
    ) => {
      if (
        !isTauriRuntime()
      ) {
        return webBackend
          .refreshContent(
            contentId,
          )
      }

      const result =
        await nativeBackend
          .refreshContent(
            contentId,
          )

      mergePortableContents([
        result.content,
      ])

      schedulePublisherPush()

      return result
    },

  undo:
    async () => {
      if (
        !isTauriRuntime()
      ) {
        return webBackend
          .undo()
      }

      const result =
        await nativeBackend
          .undo()

      await syncNativePortable()

      return result
    },

  redo:
    async () => {
      if (
        !isTauriRuntime()
      ) {
        return webBackend
          .redo()
      }

      const result =
        await nativeBackend
          .redo()

      await syncNativePortable()

      return result
    },

  /*
   * DRIVE:
   * Desktop usa Tauri OAuth.
   * Web/PWA usa GIS OAuth.
   */
  getDriveClientId:
    () =>
      isTauriRuntime()
        ? nativeBackend
            .getDriveClientId()
        : webBackend
            .getDriveClientId(),

  setDriveClientId:
    (
      clientId: string,
    ) =>
      isTauriRuntime()
        ? nativeBackend
            .setDriveClientId(
              clientId,
            )
        : webBackend
            .setDriveClientId(
              clientId,
            ),

  driveStatus:
    () =>
      isTauriRuntime()
        ? nativeBackend
            .driveStatus()
        : webBackend
            .driveStatus(),

  driveConnect:
    (
      clientId: string,
    ) =>
      isTauriRuntime()
        ? nativeBackend
            .driveConnect(
              clientId,
            )
        : webBackend
            .driveConnect(
              clientId,
            ),

  driveList:
    (
      folderId =
        'root',
    ) =>
      isTauriRuntime()
        ? nativeBackend
            .driveList(
              folderId,
            )
        : webBackend
            .driveList(
              folderId,
            ),

  drivePreviewFolder:
    (
      folderId: string,
      brand: string,
    ) =>
      isTauriRuntime()
        ? nativeBackend
            .drivePreviewFolder(
              folderId,
              brand,
            )
        : webBackend
            .drivePreviewFolder(
              folderId,
              brand,
            ),

  driveImportFolder:
    async (
      folderId: string,
      brand: string,
      policy:
        'replace'
        | 'keep'
        | 'skip',
    ) => {
      const result =
        isTauriRuntime()
          ? await nativeBackend
              .driveImportFolder(
                folderId,
                brand,
                policy,
              )
          : await webBackend
              .driveImportFolder(
                folderId,
                brand,
                policy,
              )

      mergePortableContents(
        result.contents,
      )

      schedulePublisherPush()

      return result
    },

  simulateBatch:
    () =>
      isTauriRuntime()
        ? nativeBackend
            .simulateBatch()
        : webBackend
            .simulateBatch(),

  clearWorkspace:
    async () => {
      await webBackend
        .clearWorkspace()

      if (
        isTauriRuntime()
      ) {
        try {
          await nativeBackend
            .clearWorkspace()
        } catch {}
      }

      schedulePublisherPush()

      return true
    },
}
