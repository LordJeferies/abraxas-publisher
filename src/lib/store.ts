import { create } from 'zustand'

import type {
  Brand,
  ContentItem,
  InspectorMode,
  SimulationReport,
} from '../types'

import {
  setLegacyLoading,
} from './progress'

export type View =
  | 'home'
  | 'today'
  | 'content'
  | 'kanban'
  | 'calendar'
  | 'queue'
  | 'publish'
  | 'accounts'
  | 'sync'
  | 'import'
  | 'activity'
  | 'help'
  | 'settings'

interface AppStore {
  view: View
  contents: ContentItem[]
  brands: Brand[]

  selectedId: string | null
  selectedIds: string[]

  selectedBrand: string
  inspectorMode: InspectorMode

  detailOpen: boolean
  simulation: SimulationReport | null
  loading: boolean

  setView: (view: View) => void
  setContents: (contents: ContentItem[]) => void
  setBrands: (brands: Brand[]) => void

  setSelectedBrand: (brand: string) => void

  setSelectedId: (id: string | null) => void
  selectContent: (id: string, multi?: boolean) => void
  clearSelection: () => void

  openDetail: (id: string) => void
  closeDetail: () => void

  setInspectorMode: (mode: InspectorMode) => void

  setSimulation: (
    r: SimulationReport | null,
  ) => void

  setLoading: (v: boolean) => void
}

const savedInspector =
  (localStorage.getItem(
    'abraxas.inspectorMode',
  ) as InspectorMode | null)
  ?? 'docked'

const savedBrand =
  localStorage.getItem(
    'abraxas.selectedBrand',
  )
  ?? 'ALL'

export const useAppStore =
  create<AppStore>((set) => ({
    view: 'home',

    contents: [],
    brands: [],

    selectedId: null,
    selectedIds: [],

    selectedBrand: savedBrand,
    inspectorMode: savedInspector,

    detailOpen: false,
    simulation: null,
    loading: false,

    setView: (view) =>
      set({ view }),

    setContents: (contents) =>
      set({ contents }),

    setBrands: (brands) =>
      set({ brands }),

    setSelectedBrand: (selectedBrand) => {
      localStorage.setItem(
        'abraxas.selectedBrand',
        selectedBrand,
      )

      set({
        selectedBrand,
        selectedId: null,
        selectedIds: [],
      })
    },

    setSelectedId: (selectedId) =>
      set((state) => ({
        selectedId,
        selectedIds:
          selectedId
            ? [selectedId]
            : [],
        inspectorMode:
          selectedId
            ? (
                state.inspectorMode === 'hidden'
                  ? 'docked'
                  : state.inspectorMode
              )
            : state.inspectorMode,
      })),

    selectContent: (id, multi = false) =>
      set((state) => {
        let selectedIds: string[]

        if (!multi) {
          selectedIds = [id]
        } else if (
          state.selectedIds.includes(id)
        ) {
          selectedIds =
            state.selectedIds.filter(
              (x) => x !== id,
            )
        } else {
          selectedIds =
            [...state.selectedIds, id]
        }

        return {
          selectedIds,
          selectedId:
            selectedIds.length
              ? id
              : null,
          inspectorMode:
            selectedIds.length
              && state.inspectorMode === 'hidden'
              ? 'docked'
              : state.inspectorMode,
        }
      }),

    clearSelection: () =>
      set({
        selectedId: null,
        selectedIds: [],
      }),

    openDetail: (selectedId) =>
      set((state) => ({
        selectedId,
        selectedIds:
          state.selectedIds.includes(selectedId)
            ? state.selectedIds
            : [selectedId],
        detailOpen: true,
      })),

    closeDetail: () =>
      set({
        detailOpen: false,
      }),

    setInspectorMode: (inspectorMode) => {
      localStorage.setItem(
        'abraxas.inspectorMode',
        inspectorMode,
      )

      set({ inspectorMode })
    },

    setSimulation: (simulation) =>
      set({ simulation }),

    setLoading: (loading) => {
      setLegacyLoading(loading)
      set({ loading })
    },
  }))
