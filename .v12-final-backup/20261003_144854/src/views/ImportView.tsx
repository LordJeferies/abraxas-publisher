import {
  open,
} from '@tauri-apps/plugin-dialog'

import {
  Cloud,
  FolderOpen,
  RefreshCcw,
  ShieldCheck,
  TriangleAlert,
  ChevronLeft,
} from 'lucide-react'

import {
  useEffect,
  useMemo,
  useState,
} from 'react'

import {
  backend,
} from '../lib/backend'

import {
  useAppStore,
} from '../lib/store'

import type {
  DriveItem,
  ImportPreview,
  ScanResult,
} from '../types'

type Mode =
  | 'local'
  | 'drive'

type Policy =
  | 'replace'
  | 'keep'
  | 'skip'

export function ImportView() {
  const {
    brands,
    selectedBrand,
    setSelectedBrand,
    setContents,
    loading,
    setLoading,
    setView,
  } = useAppStore()

  const fallbackBrand =
    selectedBrand !== 'ALL'
      ? selectedBrand
      : (
          brands[0]?.name
          || 'JOC'
        )

  const [brand, setBrand] =
    useState(fallbackBrand)

  const [mode, setMode] =
    useState<Mode>('local')

  const [path, setPath] =
    useState('')

  const [preview, setPreview] =
    useState<ImportPreview | null>(null)

  const [result, setResult] =
    useState<ScanResult | null>(null)

  const [error, setError] =
    useState<string | null>(null)

  const [policy, setPolicy] =
    useState<Policy>('replace')

  const [clientId, setClientId] =
    useState('')

  const [driveConnected, setDriveConnected] =
    useState(false)

  const [driveItems, setDriveItems] =
    useState<DriveItem[]>([])

  const [folderId, setFolderId] =
    useState('root')

  const [folderName, setFolderName] =
    useState('Mi Drive')

  const [stack, setStack] =
    useState<
      { id: string; name: string }[]
    >([])

  const [driveSearch, setDriveSearch] =
    useState('')

  useEffect(() => {
    backend.getDriveClientId()
      .then((x) => {
        if (x) setClientId(x)
      })
      .catch(() => {})

    backend.driveStatus()
      .then(setDriveConnected)
      .catch(() => {})
  }, [])

  useEffect(() => {
    if (
      selectedBrand !== 'ALL'
      && selectedBrand !== brand
    ) {
      setBrand(selectedBrand)
    }
  }, [selectedBrand])

  const filteredDriveItems =
    useMemo(
      () => {
        const q =
          driveSearch
            .trim()
            .toLowerCase()

        if (!q) {
          return driveItems
        }

        return driveItems.filter(
          (item) =>
            item.name
              .toLowerCase()
              .includes(q),
        )
      },
      [
        driveItems,
        driveSearch,
      ],
    )

  const refreshWorkspace =
    async () => {
      setContents(
        await backend.listContents(),
      )
    }

  const pickLocal =
    async () => {
      const selected = await open({
        directory: true,
        multiple: false,
        title:
          'Selecciona una carpeta o semana de contenido',
      })

      if (
        !selected
        || Array.isArray(selected)
      ) {
        return
      }

      setPath(selected)
      setPreview(null)
      setResult(null)
      setError(null)

      setLoading(true)

      try {
        const p =
          await backend.previewImportLocal(
            selected,
            brand,
          )

        setPreview(p)
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  const previewLocalAgain =
    async () => {
      if (!path) {
        return
      }

      setLoading(true)
      setError(null)

      try {
        setPreview(
          await backend.previewImportLocal(
            path,
            brand,
          ),
        )
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  const commitLocal =
    async () => {
      if (!path || !preview) {
        return
      }

      setLoading(true)
      setError(null)

      try {
        /*
         * Resolver contenido por contenido permite
         * mantener decisiones distintas cuando
         * aparezcan duplicados.
         *
         * El selector general `policy` funciona
         * como "Aplicar a todos".
         */
        let last: ScanResult | null = null

        for (const item of preview.contents) {
          last =
            await backend.commitImportLocal(
              item.folderPath,
              brand,
              policy,
            )
        }

        if (last) {
          setResult(last)
        }

        await refreshWorkspace()

        setSelectedBrand(brand)
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  const connectDrive =
    async () => {
      if (!clientId.trim()) {
        setError(
          'Primero introduce el OAuth Client ID de Google tipo Desktop.',
        )
        return
      }

      setLoading(true)
      setError(null)

      try {
        await backend.setDriveClientId(
          clientId.trim(),
        )

        const auth =
          await backend.driveConnect(
            clientId.trim(),
          )

        setDriveConnected(
          auth.connected,
        )

        if (auth.connected) {
          const items =
            await backend.driveList(
              'root',
            )

          setDriveItems(items)
          setFolderId('root')
          setFolderName('Mi Drive')
          setStack([])
        }
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  const loadDrive =
    async (
      id: string,
    ) => {
      setLoading(true)
      setError(null)

      try {
        setDriveItems(
          await backend.driveList(id),
        )

        setFolderId(id)
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  const enterFolder =
    async (
      item: DriveItem,
    ) => {
      if (!item.isFolder) {
        return
      }

      setStack(
        (prev) => [
          ...prev,
          {
            id: folderId,
            name: folderName,
          },
        ],
      )

      setFolderName(item.name)

      await loadDrive(item.id)
    }

  const backDrive =
    async () => {
      const previous =
        stack[
          stack.length - 1
        ]

      if (!previous) {
        return
      }

      setStack(
        (prev) =>
          prev.slice(
            0,
            -1,
          ),
      )

      setFolderName(
        previous.name,
      )

      await loadDrive(
        previous.id,
      )
    }

  const previewDrive =
    async () => {
      if (!driveConnected) {
        return
      }

      setLoading(true)
      setError(null)
      setPreview(null)
      setResult(null)

      try {
        const p =
          await backend.drivePreviewFolder(
            folderId,
            brand,
          )

        setPreview(p)
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  const commitDrive =
    async () => {
      if (!preview) {
        return
      }

      setLoading(true)
      setError(null)

      try {
        /*
         * Si el preview devuelve carpetas
         * individuales de Drive con sourceRef,
         * se importan de manera independiente.
         * Así un conflicto no obliga a modificar
         * toda la semana.
         */
        let last: ScanResult | null = null

        for (
          const item
          of preview.contents
        ) {
          const driveFolderId =
            item.sourceRef
            || folderId

          last =
            await backend.driveImportFolder(
              driveFolderId,
              brand,
              policy,
            )
        }

        if (!preview.contents.length) {
          last =
            await backend.driveImportFolder(
              folderId,
              brand,
              policy,
            )
        }

        if (last) {
          setResult(last)
        }

        await refreshWorkspace()

        setSelectedBrand(brand)
      } catch (e) {
        setError(String(e))
      } finally {
        setLoading(false)
      }
    }

  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            INGESTA
          </span>

          <h1>
            Importar contenido
          </h1>

          <p>
            Desde este Mac o directamente desde Google Drive.
          </p>
        </div>

        <select
          className="field"
          value={brand}
          onChange={(e) =>
            setBrand(
              e.target.value,
            )
          }
        >
          {
            brands.map(
              (b) => (
                <option
                  key={b.id}
                  value={b.name}
                >
                  {b.name}
                </option>
              ),
            )
          }
        </select>
      </header>

      <div className="source-tabs">
        <button
          className={
            mode === 'local'
              ? 'source-tab active'
              : 'source-tab'
          }
          onClick={() => {
            setMode('local')
            setPreview(null)
            setResult(null)
          }}
        >
          <FolderOpen size={17}/>
          Este Mac
        </button>

        <button
          className={
            mode === 'drive'
              ? 'source-tab active'
              : 'source-tab'
          }
          onClick={() => {
            setMode('drive')
            setPreview(null)
            setResult(null)
          }}
        >
          <Cloud size={17}/>
          Google Drive
        </button>
      </div>

      {
        mode === 'local'
        && (
          <section className="source-panel">
            <button
              className="drop-zone"
              onClick={pickLocal}
              disabled={loading}
            >
              <FolderOpen size={34}/>

              <strong>
                {
                  loading
                    ? 'Analizando…'
                    : 'Seleccionar carpeta'
                }
              </strong>

              <span>
                Puedes seleccionar una carpeta individual o una carpeta que contenga toda una semana.
              </span>
            </button>

            {
              path
              && (
                <div className="selected-source">
                  <span>
                    Carpeta
                  </span>

                  <strong>
                    {path}
                  </strong>

                  <button
                    className="secondary-btn small"
                    onClick={
                      previewLocalAgain
                    }
                  >
                    <RefreshCcw size={14}/>
                    Volver a analizar
                  </button>
                </div>
              )
            }
          </section>
        )
      }

      {
        mode === 'drive'
        && (
          <section className="source-panel">
            {
              !driveConnected
              ? (
                <div className="drive-connect-card">
                  <Cloud size={34}/>

                  <h3>
                    Conectar Google Drive
                  </h3>

                  <p>
                    Usa un OAuth Client ID de tipo Desktop. El login se abre en tu navegador, no dentro del WebView.
                  </p>

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

                  <button
                    className="primary-btn"
                    disabled={
                      loading
                      || !clientId.trim()
                    }
                    onClick={
                      connectDrive
                    }
                  >
                    <Cloud size={15}/>
                    Conectar Drive
                  </button>

                  <small className="helper">
                    El Client ID se guarda en los ajustes locales de Publisher. No se guarda ningún token social.
                  </small>
                </div>
              )
              : (
                <div className="drive-browser">
                  <div className="drive-browser-head">
                    <button
                      className="secondary-btn small"
                      disabled={
                        !stack.length
                      }
                      onClick={
                        backDrive
                      }
                    >
                      <ChevronLeft size={14}/>
                      Atrás
                    </button>

                    <div>
                      <span className="eyebrow">
                        GOOGLE DRIVE
                      </span>

                      <strong>
                        {folderName}
                      </strong>
                    </div>

                    <button
                      className="secondary-btn small"
                      onClick={() =>
                        loadDrive(
                          folderId,
                        )
                      }
                    >
                      <RefreshCcw size={14}/>
                      Actualizar
                    </button>
                  </div>

                  <input
                    className="field full-field"
                    placeholder="Buscar dentro de esta carpeta…"
                    value={driveSearch}
                    onChange={(e) =>
                      setDriveSearch(
                        e.target.value,
                      )
                    }
                  />

                  <div className="drive-list">
                    {
                      filteredDriveItems.map(
                        (item) => (
                          <button
                            className={
                              item.isFolder
                                ? 'drive-row folder'
                                : 'drive-row'
                            }
                            key={item.id}
                            onDoubleClick={() =>
                              enterFolder(
                                item,
                              )
                            }
                            onClick={() => {
                              if (
                                item.isFolder
                              ) {
                                enterFolder(
                                  item,
                                )
                              }
                            }}
                          >
                            {
                              item.isFolder
                                ? '📁'
                                : '📄'
                            }

                            <span>
                              <strong>
                                {item.name}
                              </strong>

                              <small>
                                {
                                  item.isFolder
                                    ? 'Carpeta'
                                    : item.mimeType
                                }
                              </small>
                            </span>
                          </button>
                        ),
                      )
                    }

                    {
                      !filteredDriveItems.length
                      && (
                        <div className="empty-state">
                          Esta carpeta está vacía o el filtro no encontró resultados.
                        </div>
                      )
                    }
                  </div>

                  <button
                    className="primary-btn wide"
                    disabled={loading}
                    onClick={
                      previewDrive
                    }
                  >
                    <ShieldCheck size={15}/>
                    Usar esta carpeta
                  </button>
                </div>
              )
            }
          </section>
        )
      }

      {
        error
        && (
          <div className="banner error">
            <TriangleAlert size={17}/>
            {error}
          </div>
        )
      }

      {
        preview
        && (
          <section className="import-preview panel">
            <div className="panel-title-row">
              <div>
                <span className="eyebrow">
                  PREVIEW DE IMPORTACIÓN
                </span>

                <h3>
                  {
                    preview.contents.length
                  } contenidos detectados
                </h3>
              </div>

              <div className="import-counts">
                <span>
                  {
                    preview.duplicates.length
                  } duplicados
                </span>

                <span>
                  {
                    preview.warnings
                  } warnings
                </span>

                <span>
                  {
                    preview.errors
                  } errores
                </span>
              </div>
            </div>

            {
              preview.duplicates.length
              > 0
              && (
                <div className="duplicate-panel">
                  <TriangleAlert size={18}/>

                  <div>
                    <strong>
                      Contenido ya existente
                    </strong>

                    <p>
                      Publisher detectó {
                        preview.duplicates.length
                      } conflicto(s). Elige qué hacer.
                    </p>
                  </div>

                  <select
                    className="field"
                    value={policy}
                    onChange={(e) =>
                      setPolicy(
                      e.target.value === 'keep'
                        ? 'keep'
                        : e.target.value === 'skip'
                          ? 'skip'
                          : 'replace'
                    )
                    }
                  >
                    <option value="replace">
                      Reemplazar todos
                    </option>

                    <option value="keep">
                      Mantener ambos
                    </option>

                    <option value="skip">
                      Omitir todos
                    </option>
                  </select>
                </div>
              )
            }

            <div className="import-content-list">
              {
                preview.contents.map(
                  (item) => {
                    const duplicate =
                      preview.duplicates
                        .find(
                          (x) =>
                            x.incomingId
                            === item.id,
                        )

                    return (
                      <div
                        className="import-content-row"
                        key={
                          `${item.id}-${item.folderPath}`
                        }
                      >
                        <div>
                          <small>
                            {
                              item.client
                              || brand
                            }
                          </small>

                          <strong>
                            {item.title}
                          </strong>

                          <span>
                            {item.contentType}
                            {' · '}
                            {
                              item.targets
                                .map(
                                  (x) =>
                                    x.platform,
                                )
                                .join(' · ')
                            }
                          </span>
                        </div>

                        {
                          duplicate
                          ? (
                            <span className="duplicate-badge">
                              Ya existe
                            </span>
                          )
                          : (
                            <span className="new-badge">
                              Nuevo
                            </span>
                          )
                        }
                      </div>
                    )
                  },
                )
              }
            </div>

            <button
              className="primary-btn wide"
              disabled={loading}
              onClick={
                mode === 'local'
                  ? commitLocal
                  : commitDrive
              }
            >
              {
                loading
                  ? 'Importando…'
                  : 'Confirmar importación'
              }
            </button>
          </section>
        )
      }

      {
        result
        && (
          <div className="import-summary">
            <div className="summary-top">
              <ShieldCheck size={21}/>

              <div>
                <strong>
                  Importación completada
                </strong>

                <span>
                  {
                    result.importedCount
                  } elementos procesados
                </span>
              </div>
            </div>

            <button
              className="primary-btn wide"
              onClick={() =>
                setView('content')
              }
            >
              Ver contenido
            </button>
          </div>
        )
      }
    </div>
  )
}
