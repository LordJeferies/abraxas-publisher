import { invoke } from '@tauri-apps/api/core'

import type {
  ActivityEvent,
  Brand,
  ContentItem,
  CorrectionNote,
  DriveAuthResult,
  DriveItem,
  HealthReport,
  ImportPreview,
  RefreshResult,
  ScanResult,
  ScheduleChange,
  SimulationReport,
  WorkflowStatus,
} from '../types'

export const backend = {
  health: () =>
    invoke<HealthReport>('health'),

  listBrands: () =>
    invoke<Brand[]>('list_brands'),

  createBrand: (name: string) =>
    invoke<Brand>('create_brand', { name }),

  previewImportLocal: (
    path: string,
    brand: string,
  ) =>
    invoke<ImportPreview>(
      'preview_import_local',
      { path, brand },
    ),

  commitImportLocal: (
    path: string,
    brand: string,
    duplicatePolicy: 'replace' | 'keep' | 'skip',
  ) =>
    invoke<ScanResult>(
      'commit_import_local',
      { path, brand, duplicatePolicy },
    ),

  importFolder: (path: string) =>
    invoke<ScanResult>(
      'import_folder',
      { path },
    ),

  listContents: () =>
    invoke<ContentItem[]>('list_contents'),

  updateSchedule: (
    targetId: string,
    scheduledAt: string | null,
  ) =>
    invoke<boolean>(
      'update_schedule',
      { targetId, scheduledAt },
    ),

  updateSchedules: (
    changes: ScheduleChange[],
  ) =>
    invoke<number>(
      'update_schedules',
      { changes },
    ),

  updateWorkflowStatus: (
    contentId: string,
    status: WorkflowStatus,
  ) =>
    invoke<boolean>(
      'update_workflow_status',
      { contentId, status },
    ),

  saveCorrectionNote: (
    contentId: string,
    note: string,
    status: WorkflowStatus,
  ) =>
    invoke<CorrectionNote>(
      'save_correction_note',
      { contentId, note, status },
    ),

  refreshContent: (contentId: string) =>
    invoke<RefreshResult>(
      'refresh_content',
      { contentId },
    ),

  listActivity: () =>
    invoke<ActivityEvent[]>(
      'list_activity',
    ),

  undo: () =>
    invoke<ActivityEvent | null>(
      'undo_last',
    ),

  redo: () =>
    invoke<ActivityEvent | null>(
      'redo_last',
    ),

  getDriveClientId: () =>
    invoke<string | null>(
      'get_drive_client_id',
    ),

  setDriveClientId: (clientId: string) =>
    invoke<boolean>(
      'set_drive_client_id',
      { clientId },
    ),

  driveStatus: () =>
    invoke<boolean>(
      'drive_status',
    ),

  driveConnect: (clientId: string) =>
    invoke<DriveAuthResult>(
      'drive_connect',
      { clientId },
    ),

  driveList: (folderId = 'root') =>
    invoke<DriveItem[]>(
      'drive_list',
      { folderId },
    ),

  drivePreviewFolder: (
    folderId: string,
    brand: string,
  ) =>
    invoke<ImportPreview>(
      'drive_preview_folder',
      { folderId, brand },
    ),

  driveImportFolder: (
    folderId: string,
    brand: string,
    duplicatePolicy: 'replace' | 'keep' | 'skip',
  ) =>
    invoke<ScanResult>(
      'drive_import_folder',
      {
        folderId,
        brand,
        duplicatePolicy,
      },
    ),

  simulateBatch: () =>
    invoke<SimulationReport>(
      'simulate_batch',
    ),

  clearWorkspace: () =>
    invoke<boolean>(
      'clear_workspace',
    ),
}
