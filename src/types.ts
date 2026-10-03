export type Platform = 'instagram' | 'facebook' | 'linkedin' | 'youtube' | string
export type ContentType = 'reel' | 'video' | 'carousel' | 'image' | 'unknown' | string
export type WorkflowStatus = 'EN_CONFIRMACION' | 'CON_CORRECCION' | 'LISTO_POR_PROGRAMAR' | 'PROGRAMADO'
export type ValidationStatus = 'VALID' | 'WARNING' | 'INVALID' | string

export interface MediaAsset {
  id: string
  path: string
  kind: 'video' | 'image' | string
  sizeBytes: number
  durationSeconds?: number | null
  sha256?: string | null
  modifiedAt?: string | null
}

export interface PublicationTarget {
  id: string
  platform: Platform
  account?: string | null
  status: string
  scheduledAt?: string | null
  sourceTxt?: string | null
  copy?: string | null
  scheduleSource?: string | null
}

export interface ValidationIssue { id: string; severity: 'warning' | 'error' | string; message: string }
export interface CorrectionNote { id: string; body: string; createdAt: string }

export interface ContentItem {
  id: string
  folderPath: string
  title: string
  client?: string | null
  contentType: ContentType
  status: WorkflowStatus | string
  validationStatus: ValidationStatus
  version: number
  sourceFingerprint?: string | null
  refreshedAt?: string | null
  latestNote?: CorrectionNote | null
  media: MediaAsset[]
  targets: PublicationTarget[]
  issues: ValidationIssue[]
}

export interface ScanResult { rootPath: string; importedCount: number; contents: ContentItem[]; warnings: number; errors: number }
export interface RefreshResult { content: ContentItem; changed: boolean; previousVersion: number; currentVersion: number; message: string }
export interface SimulationPlatform { platform: string; total: number; ready: number; warnings: number; errors: number }
export interface SimulationReport { totalTargets: number; ready: number; warnings: number; errors: number; generatedAt: string; platforms: SimulationPlatform[]; note: string }
export interface HealthReport { database: boolean; ffmpeg: boolean; ffprobe: boolean; appDataDir: string }
