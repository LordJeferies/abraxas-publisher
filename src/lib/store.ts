import { create } from 'zustand'
import type { ContentItem, SimulationReport } from '../types'

export type View = 'home' | 'today' | 'content' | 'kanban' | 'calendar' | 'queue' | 'import' | 'activity' | 'help' | 'settings'

interface AppStore {
  view: View
  contents: ContentItem[]
  selectedId: string | null
  detailOpen: boolean
  simulation: SimulationReport | null
  loading: boolean
  setView: (view: View) => void
  setContents: (contents: ContentItem[]) => void
  setSelectedId: (id: string | null) => void
  openDetail: (id: string) => void
  closeDetail: () => void
  setSimulation: (r: SimulationReport | null) => void
  setLoading: (v: boolean) => void
}

export const useAppStore = create<AppStore>((set) => ({
  view: 'home', contents: [], selectedId: null, detailOpen: false, simulation: null, loading: false,
  setView: (view) => set({ view }),
  setContents: (contents) => set({ contents }),
  setSelectedId: (selectedId) => set({ selectedId }),
  openDetail: (selectedId) => set({ selectedId, detailOpen: true }),
  closeDetail: () => set({ detailOpen: false }),
  setSimulation: (simulation) => set({ simulation }),
  setLoading: (loading) => set({ loading }),
}))
