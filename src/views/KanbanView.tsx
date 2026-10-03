import {
  useMemo,
} from 'react'

import {
  useAppStore,
} from '../lib/store'

import type {
  WorkflowStatus,
} from '../types'

const columns: {
  status: WorkflowStatus
  title: string
}[] = [
  {
    status: 'EN_CONFIRMACION',
    title: 'En confirmación',
  },
  {
    status: 'CON_CORRECCION',
    title: 'Con corrección',
  },
  {
    status: 'LISTO_POR_PROGRAMAR',
    title: 'Listo / por programar',
  },
  {
    status: 'PROGRAMADO',
    title: 'Programado',
  },
]

export function KanbanView() {
  const {
    contents,
    openDetail,
    selectedBrand,
  } = useAppStore()

  const visible = useMemo(
    () =>
      contents.filter(
        (c) =>
          selectedBrand === 'ALL'
          || c.client === selectedBrand,
      ),
    [
      contents,
      selectedBrand,
    ],
  )

  return (
    <div className="page scrollable">
      <header className="page-header">
        <div>
          <span className="eyebrow">
            ESTADOS
          </span>

          <h1>
            Kanban editorial
          </h1>

          <p>
            Es una vista de control. El estado se cambia exclusivamente desde la ficha.
          </p>
        </div>
      </header>

      <div className="kanban-grid">
        {
          columns.map((column) => {
            const items =
              visible.filter(
                (c) =>
                  c.status
                  === column.status,
              )

            return (
              <section
                className="kanban-column"
                key={column.status}
              >
                <header>
                  <strong>
                    {column.title}
                  </strong>

                  <span>
                    {items.length}
                  </span>
                </header>

                <div>
                  {
                    items.map(
                      (item) => (
                        <button
                          className="kanban-card"
                          key={item.id}
                          onClick={() =>
                            openDetail(item.id)
                          }
                        >
                          <small>
                            {item.client || 'Sin marca'}
                          </small>

                          <strong>
                            {item.title}
                          </strong>

                          <span>
                            {
                              item.targets
                                .map(
                                  (x) =>
                                    x.platform,
                                )
                                .join(' · ')
                            }
                          </span>
                        </button>
                      ),
                    )
                  }
                </div>
              </section>
            )
          })
        }
      </div>
    </div>
  )
}
