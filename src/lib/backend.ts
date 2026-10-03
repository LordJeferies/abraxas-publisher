import { invoke } from '@tauri-apps/api/core'
import type { ContentItem, CorrectionNote, HealthReport, RefreshResult, ScanResult, SimulationReport, WorkflowStatus } from '../types'

export const backend = {
  health: () => invoke<HealthReport>('health'),
  importFolder: (path: string) => invoke<ScanResult>('import_folder', { path }),
  listContents: () => invoke<ContentItem[]>('list_contents'),
  updateSchedule: (targetId: string, scheduledAt: string | null) => invoke<boolean>('update_schedule', { targetId, scheduledAt }),
  updateWorkflowStatus: (contentId: string, status: WorkflowStatus) => invoke<boolean>('update_workflow_status', { contentId, status }),
  saveCorrectionNote: (contentId: string, note: string, status: WorkflowStatus) => invoke<CorrectionNote>('save_correction_note', { contentId, note, status }),
  refreshContent: (contentId: string) => invoke<RefreshResult>('refresh_content', { contentId }),
  simulateBatch: () => invoke<SimulationReport>('simulate_batch'),
  clearWorkspace: () => invoke<boolean>('clear_workspace'),
}
