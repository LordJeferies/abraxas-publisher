import type {
  ContentItem,
  DriveItem,
  ImportPreview,
  MediaAsset,
  PublicationTarget,
} from '../types'

let token = ''
let expires = 0
let authClient:
  any = null

const READ_SCOPE =
  'https://www.googleapis.com/auth/drive.readonly'

function readyToken() {
  if (
    !token
    || Date.now() >= expires
  ) {
    throw new Error(
      'La sesión de Google Drive ha caducado. Conecta Drive nuevamente.',
    )
  }

  return token
}

async function loadGoogleIdentity() {
  if (
    (window as any)
      .google
      ?.accounts
      ?.oauth2
  ) {
    return
  }

  if (
    document
      .getElementById(
        'abraxas-google-gis',
      )
  ) {
    await new Promise(
      (resolve) =>
        setTimeout(
          resolve,
          700,
        ),
    )

    return
  }

  await new Promise<
    void
  >(
    (
      resolve,
      reject,
    ) => {
      const script =
        document
          .createElement(
            'script',
          )

      script.id =
        'abraxas-google-gis'

      script.src =
        'https://accounts.google.com/gsi/client'

      script.async =
        true

      const timeout =
        window.setTimeout(
          () => {
            script.remove()

            reject(
              new Error(
                'Google Identity Services no respondió.',
              ),
            )
          },
          15000,
        )

      script.onload =
        () => {
          clearTimeout(
            timeout,
          )

          resolve()
        }

      script.onerror =
        () => {
          clearTimeout(
            timeout,
          )

          reject(
            new Error(
              'No se pudo cargar Google Identity Services.',
            ),
          )
        }

      document.head
        .appendChild(
          script,
        )
    },
  )
}

async function api(
  path: string,
  params:
    Record<
      string,
      string
    > = {},
) {
  const url =
    new URL(
      `https://www.googleapis.com/drive/v3/${path}`,
    )

  for (
    const [
      key,
      value,
    ]
    of Object.entries(
      params,
    )
  ) {
    url.searchParams
      .set(
        key,
        value,
      )
  }

  const response =
    await fetch(
      url,
      {
        headers: {
          Authorization:
            `Bearer ${readyToken()}`,
        },

        cache:
          'no-store',

        referrerPolicy:
          'no-referrer',
      },
    )

  if (
    response.status
    === 401
  ) {
    token = ''
    expires = 0

    throw new Error(
      'La sesión de Drive caducó.',
    )
  }

  if (!response.ok) {
    throw new Error(
      `Google Drive ${response.status}`,
    )
  }

  return response.json()
}

function kindFromMime(
  mime: string,
) {
  if (
    mime.startsWith(
      'video/',
    )
  ) {
    return 'video'
  }

  if (
    mime.startsWith(
      'image/',
    )
  ) {
    return 'image'
  }

  return 'file'
}

function contentType(
  files:
    Array<{
      mimeType: string
      name: string
    }>,
) {
  if (
    files.some(
      (file) =>
        file.mimeType
          .startsWith(
            'video/',
          ),
    )
  ) {
    const name =
      files
        .map(
          (file) =>
            file.name
              .toLowerCase(),
        )
        .join(' ')

    if (
      name.includes(
        'reel',
      )
      || name.includes(
        'short',
      )
    ) {
      return 'reel'
    }

    return 'video'
  }

  if (
    files.filter(
      (file) =>
        file.mimeType
          .startsWith(
            'image/',
          ),
    ).length > 1
  ) {
    return 'carousel'
  }

  if (
    files.some(
      (file) =>
        file.mimeType
          .startsWith(
            'image/',
          ),
    )
  ) {
    return 'image'
  }

  return 'unknown'
}

function defaultTargets(
  contentId: string,
):
  PublicationTarget[] {
  return [
    'instagram',
    'facebook',
    'linkedin',
    'youtube',
    'tiktok',
  ].map(
    (platform) => ({
      id:
        `${contentId}-${platform}`,
      platform,
      account: null,
      status:
        'UNSCHEDULED',
      scheduledAt:
        null,
      sourceTxt:
        null,
      copy:
        null,
      scheduleSource:
        null,
    }),
  )
}

export const webDrive = {
  async prepare() {
    await loadGoogleIdentity()
  },

  connected() {
    return Boolean(
      token
      && Date.now()
        < expires,
    )
  },

  async connect(
    clientId: string,
  ) {
    if (
      !/^[\w.-]+\.apps\.googleusercontent\.com$/
        .test(
          clientId,
        )
    ) {
      throw new Error(
        'Introduce un OAuth Client ID Web público válido.',
      )
    }

    await loadGoogleIdentity()

    const google =
      (window as any)
        .google

    return new Promise<
      void
    >(
      (
        resolve,
        reject,
      ) => {
        authClient =
          google.accounts
            .oauth2
            .initTokenClient({
              client_id:
                clientId,

              scope:
                READ_SCOPE,

              callback:
                (
                  response:
                    any,
                ) => {
                  if (
                    response.error
                  ) {
                    reject(
                      new Error(
                        `Google rechazó la conexión: ${response.error}`,
                      ),
                    )

                    return
                  }

                  token =
                    response
                      .access_token

                  expires =
                    Date.now()
                    + Math.max(
                        0,
                        Number(
                          response
                            .expires_in,
                        )
                        - 60,
                      )
                      * 1000

                  resolve()
                },

              error_callback:
                (
                  response:
                    any,
                ) => {
                  reject(
                    new Error(
                      `Ventana de Google: ${response.type}`,
                    ),
                  )
                },
            })

        authClient
          .requestAccessToken({
            prompt:
              'consent',
          })
      },
    )
  },

  async disconnect() {
    const previous =
      token

    token = ''
    expires = 0

    const google =
      (window as any)
        .google

    if (
      previous
      && google?.accounts
        ?.oauth2
    ) {
      google.accounts
        .oauth2
        .revoke(
          previous,
          () => {},
        )
    }
  },

  async list(
    folderId =
      'root',
  ):
    Promise<
      DriveItem[]
    > {
    const files:
      any[] = []

    let pageToken = ''

    do {
      const data =
        await api(
          'files',
          {
            q:
              `'${folderId}' in parents and trashed = false`,

            fields:
              'nextPageToken,files(id,name,mimeType,size,parents,videoMediaMetadata(durationMillis,width,height))',

            orderBy:
              'folder,name',

            pageSize:
              '100',

            supportsAllDrives:
              'true',

            includeItemsFromAllDrives:
              'true',

            ...(pageToken
              ? {
                  pageToken,
                }
              : {}),
          },
        )

      files.push(
        ...(data.files || []),
      )

      pageToken =
        data.nextPageToken
        || ''
    } while (
      pageToken
      && files.length < 2000
    )

    return files.map(
      (file) => ({
        id:
          file.id,
        name:
          file.name,
        mimeType:
          file.mimeType,
        isFolder:
          file.mimeType
          === 'application/vnd.google-apps.folder',
        size:
          file.size
            ? Number(
                file.size,
              )
            : null,
      }),
    )
  },

  async previewFolder(
    folderId: string,
    brand: string,
  ):
    Promise<
      ImportPreview
    > {
    const folder =
      folderId === 'root'
        ? {
            id: 'root',
            name:
              'Mi Drive',
          }
        : await api(
            `files/${encodeURIComponent(folderId)}`,
            {
              fields:
                'id,name,mimeType',
              supportsAllDrives:
                'true',
            },
          )

    const children:
      any[] =
      await this.list(
        folderId,
      )

    const mediaFiles =
      children.filter(
        (file) =>
          !file.isFolder
          && (
            file.mimeType
              .startsWith(
                'video/',
              )
            || file.mimeType
              .startsWith(
                'image/',
              )
          ),
      )

    const subfolders =
      children.filter(
        (file) =>
          file.isFolder,
      )

    const contents:
      ContentItem[] = []

    /*
     * Si la carpeta actual tiene media,
     * la carpeta completa es una ficha.
     */
    if (
      mediaFiles.length
      > 0
    ) {
      const id =
        `drive-${folderId}`

      const media:
        MediaAsset[] =
        mediaFiles.map(
          (file) => ({
            id:
              `drive-media-${file.id}`,
            path:
              `drive://${file.id}`,
            kind:
              kindFromMime(
                file.mimeType,
              ),
            sizeBytes:
              file.size
                ? Number(
                    file.size,
                  )
                : 0,
            durationSeconds:
              null,
            sha256:
              null,
            modifiedAt:
              null,
          }),
        )

      contents.push({
        id,
        folderPath:
          `drive://${folderId}`,
        title:
          folder.name
          || 'Contenido Drive',
        client:
          brand,
        contentType:
          contentType(
            mediaFiles,
          ),
        status:
          'EN_CONFIRMACION',
        validationStatus:
          'VALID',
        version: 1,
        sourceFingerprint:
          `drive:${folderId}`,
        refreshedAt:
          new Date()
            .toISOString(),
        latestNote:
          null,
        sourceKind:
          'GOOGLE_DRIVE',
        sourceRef:
          folderId,
        media,
        targets:
          defaultTargets(id),
        issues: [],
      })
    }

    /*
     * Subcarpetas aparecen como
     * fichas importables independientes.
     */
    for (
      const child
      of subfolders
    ) {
      const id =
        `drive-${child.id}`

      contents.push({
        id,
        folderPath:
          `drive://${child.id}`,
        title:
          child.name,
        client:
          brand,
        contentType:
          'unknown',
        status:
          'EN_CONFIRMACION',
        validationStatus:
          'VALID',
        version: 1,
        sourceFingerprint:
          `drive:${child.id}`,
        refreshedAt:
          new Date()
            .toISOString(),
        latestNote:
          null,
        sourceKind:
          'GOOGLE_DRIVE',
        sourceRef:
          child.id,
        media: [],
        targets:
          defaultTargets(id),
        issues: [],
      })
    }

    return {
      rootPath:
        `drive://${folderId}`,
      contents,
      duplicates: [],
      warnings:
        contents.length
          ? 0
          : 1,
      errors: 0,
    }
  },

  async mediaBlobUrl(
    fileId: string,
  ) {
    const response =
      await fetch(
        `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}?alt=media`,
        {
          headers: {
            Authorization:
              `Bearer ${readyToken()}`,
          },

          cache:
            'no-store',
        },
      )

    if (!response.ok) {
      throw new Error(
        `Drive ${response.status}`,
      )
    }

    const blob =
      await response.blob()

    return URL
      .createObjectURL(
        blob,
      )
  },
}
