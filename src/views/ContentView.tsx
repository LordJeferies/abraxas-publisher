import {
  useMemo,
  useState,
} from 'react'

import {
  useAppStore,
} from '../lib/store'

import {
  ContentCard,
} from '../components/ContentCard'

export function ContentView() {
  const {
    contents,
    selectedIds,
    selectContent,
    openDetail,
    selectedBrand,
  } = useAppStore()

  const [query, setQuery] =
    useState('')

  const [status, setStatus] =
    useState('ALL')

  const filtered = useMemo(
    () =>
      contents.filter((c) => {
        if (
          selectedBrand !== 'ALL'
          && c.client !== selectedBrand
        ) {
          return false
        }

        if (
          status !== 'ALL'
          && c.status !== status
        ) {
          return false
        }

        return [
          c.title,
          c.client,
          c.contentType,
        ]
          .join(' ')
          .toLowerCase()
          .includes(
            query.toLowerCase(),
          )
      }),
    [
      contents,
      query,
      status,
      selectedBrand,
    ],
  )

  return (
    <div className="page scrollable">
      <header className="page-header compact">
        <div>
          <span className="eyebrow">
            BIBLIOTECA
          </span>

          <h1>
            Contenido
          </h1>

          <p>
            Click selecciona. ⌘/Shift + click permite seleccionar varias fichas.
          </p>
        </div>

        <div className="filter-row">
          <select
            className="field"
            value={status}
            onChange={(e) =>
              setStatus(
                e.target.value,
              )
            }
          >
            <option value="ALL">
              Todos los estados
            </option>

            <option value="EN_CONFIRMACION">
              En confirmación
            </option>

            <option value="CON_CORRECCION">
              Con corrección
            </option>

            <option value="LISTO_POR_PROGRAMAR">
              Listo / por programar
            </option>

            <option value="PROGRAMADO">
              Programado
            </option>
          </select>

          <input
            className="field compact-field"
            value={query}
            onChange={(e) =>
              setQuery(
                e.target.value,
              )
            }
            placeholder="Buscar…"
          />
        </div>
      </header>

      {
        filtered.length
        ? (
          <div className="content-grid">
            {
              filtered.map(
                (item) => (
                  <div
                    key={item.id}
                    onDoubleClick={() =>
                      openDetail(item.id)
                    }
                  >
                    <ContentCard
                      item={item}
                      selected={
                        selectedIds.includes(
                          item.id,
                        )
                      }
                      onSelect={(e) =>
                        selectContent(
                          item.id,
                          e.metaKey
                            || e.shiftKey,
                        )
                      }
                    />
                  </div>
                ),
              )
            }
          </div>
        )
        : (
          <div className="hero-empty">
            <h2>
              No hay contenido
            </h2>

            <p>
              Importa una carpeta local o abre Google Drive.
            </p>
          </div>
        )
      }
    </div>
  )
}
