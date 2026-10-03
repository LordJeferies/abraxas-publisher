import {
  useState,
} from 'react'

import {
  CalendarDays,
  CircleHelp,
  Cloud,
  FileCheck2,
  FolderOpen,
  Plus,
} from 'lucide-react'

import {
  backend,
} from '../lib/backend'

import {
  useAppStore,
} from '../lib/store'

export function HomeView() {
  const {
    contents,
    brands,
    setBrands,
    selectedBrand,
    setSelectedBrand,
    setView,
    openDetail,
  } = useAppStore()

  const [creating, setCreating] =
    useState(false)

  const [brandName, setBrandName] =
    useState('')

  const recent = contents
    .filter(
      (c) =>
        selectedBrand === 'ALL'
        || c.client === selectedBrand,
    )
    .slice(0, 4)

  const addBrand = async () => {
    if (!brandName.trim()) {
      return
    }

    const brand =
      await backend.createBrand(
        brandName.trim(),
      )

    const next =
      await backend.listBrands()

    setBrands(next)
    setSelectedBrand(brand.name)

    setBrandName('')
    setCreating(false)
  }

  return (
    <div className="page scrollable welcome-page">
      <section className="welcome-hero">
        <span className="eyebrow">
          ABRAXAS PUBLISHER · V1.2
        </span>

        <h1>
          Planifica. Revisa. Programa.
        </h1>

        <p>
          Elige la marca y entra al workspace o importa contenido desde tu Mac o Google Drive.
        </p>

        <div className="welcome-brand-picker">
          <label>
            Marca
          </label>

          <select
            className="field"
            value={selectedBrand}
            onChange={(e) =>
              setSelectedBrand(
                e.target.value,
              )
            }
          >
            <option value="ALL">
              Todas las marcas
            </option>

            {
              brands.map(
                (brand) => (
                  <option
                    key={brand.id}
                    value={brand.name}
                  >
                    {brand.name}
                  </option>
                ),
              )
            }
          </select>

          <button
            className="secondary-btn"
            onClick={() =>
              setCreating(
                !creating,
              )
            }
          >
            <Plus size={15}/>
            Nueva marca
          </button>
        </div>

        {
          creating
          && (
            <div className="inline-create-brand">
              <input
                className="field"
                placeholder="Ej. MOKA"
                value={brandName}
                onChange={(e) =>
                  setBrandName(
                    e.target.value,
                  )
                }
                onKeyDown={(e) => {
                  if (
                    e.key === 'Enter'
                  ) {
                    addBrand()
                  }
                }}
              />

              <button
                className="primary-btn"
                onClick={addBrand}
              >
                Crear
              </button>
            </div>
          )
        }

        <div className="welcome-actions">
          <button
            className="primary-btn welcome-primary"
            onClick={() =>
              setView('import')
            }
          >
            <FolderOpen size={17}/>
            Importar contenido
          </button>

          <button
            className="secondary-btn"
            onClick={() =>
              setView('help')
            }
          >
            <CircleHelp size={17}/>
            Cómo usar
          </button>
        </div>
      </section>

      <div className="welcome-grid">
        <button
          className="welcome-card"
          onClick={() =>
            setView('content')
          }
        >
          <FileCheck2/>

          <div>
            <strong>
              Revisar contenido
            </strong>

            <span>
              Preview, correcciones, estados y versiones.
            </span>
          </div>
        </button>

        <button
          className="welcome-card"
          onClick={() =>
            setView('calendar')
          }
        >
          <CalendarDays/>

          <div>
            <strong>
              Precalendarizar
            </strong>

            <span>
              Día, semana, mes y bandeja sin calendarizar.
            </span>
          </div>
        </button>

        <button
          className="welcome-card"
          onClick={() =>
            setView('import')
          }
        >
          <Cloud/>

          <div>
            <strong>
              Google Drive directo
            </strong>

            <span>
              Navega Drive desde Publisher sin depender de Finder.
            </span>
          </div>
        </button>
      </div>

      <section className="panel recent-panel">
        <div className="panel-title-row">
          <h3>
            Recientes
          </h3>

          <span>
            {recent.length}
          </span>
        </div>

        {
          recent.length
          ? recent.map(
              (c) => (
                <button
                  className="recent-content"
                  key={c.id}
                  onClick={() =>
                    openDetail(c.id)
                  }
                >
                  <div>
                    <strong>
                      {c.title}
                    </strong>

                    <span>
                      {c.client || 'Sin marca'}
                      {' · '}
                      {c.contentType}
                      {' · '}
                      v{c.version}
                    </span>
                  </div>

                  <span>
                    {c.status.replaceAll('_', ' ')}
                  </span>
                </button>
              ),
            )
          : (
            <div className="empty-state">
              Todavía no hay contenido para esta marca.
            </div>
          )
        }
      </section>
    </div>
  )
}
