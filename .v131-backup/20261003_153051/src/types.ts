export type Platform =
  | 'instagram'
  | 'facebook'
  | 'linkedin'
  | 'youtube'
  | string

export type ContentType =
  | 'reel'
  | 'video'
  | 'carousel'
  | 'image'
  | 'unknown'
  | string

export type WorkflowStatus =
  | 'EN_CONFIRMACION'
  | 'CON_CORRECCION'
  | 'LISTO_POR_PROGRAMAR'
  | 'PROGRAMADO'

export type ValidationStatus =
  | 'VALID'
  | 'WARNING'
  | 'INVALID'
  | string

export type InspectorMode =
  | 'hidden'
  | 'docked'
  | 'floating'

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

export interface ValidationIssue {
  id: string
  severity: 'warning' | 'error' | string
  message: string
}

export interface CorrectionNote {
  id: string
  body: string
  createdAt: string
}

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
  sourceKind: string
  sourceRef?: string | null
  media: MediaAsset[]
  targets: PublicationTarget[]
  issues: ValidationIssue[]
}

export interface Brand {
  id: string
  name: string
  createdAt: string
}

export interface DuplicateConflict {
  incomingId: string
  incomingTitle: string
  existingId: string
  existingTitle: string
  identicalFingerprint: boolean
}

export interface ImportPreview {
  rootPath: string
  contents: ContentItem[]
  duplicates: DuplicateConflict[]
  warnings: number
  errors: number
}

export interface ScanResult {
  rootPath: string
  importedCount: number
  contents: ContentItem[]
  warnings: number
  errors: number
}

export interface RefreshResult {
  content: ContentItem
  changed: boolean
  previousVersion: number
  currentVersion: number
  message: string
}

export interface ScheduleChange {
  targetId: string
  scheduledAt: string | null
}

export interface ActivityEvent {
  id: string
  action: string
  entityType: string
  entityId: string
  label: string
  beforeJson?: string | null
  afterJson?: string | null
  reversible: boolean
  remote: boolean
  undone: boolean
  createdAt: string
}

export interface DriveItem {
  id: string
  name: string
  mimeType: string
  isFolder: boolean
  size?: number | null
}

export interface DriveAuthResult {
  connected: boolean
  message: string
}

export interface SimulationPlatform {
  platform: string
  total: number
  ready: number
  warnings: number
  errors: number
}

export interface SimulationReport {
  totalTargets: number
  ready: number
  warnings: number
  errors: number
  generatedAt: string
  platforms: SimulationPlatform[]
  note: string
}

export interface HealthReport {
  database: boolean
  ffmpeg: boolean
  ffprobe: boolean
  appDataDir: string
}

export type Provider =
  | 'instagram'
  | 'facebook'
  | 'linkedin'
  | 'youtube'
  | 'tiktok'
  | string

export interface ConnectedAccount {
  id: string
  provider: Provider
  brand?: string | null
  displayName: string
  handle?: string | null
  accountKind: string
  connectionStatus: string
  authState: string
  capabilitiesJson: string
  externalReference?: string | null
  lastVerifiedAt?: string | null
  lastError?: string | null
  createdAt: string
  updatedAt: string
}

export interface SaveAccountInput {
  id?: string | null
  provider: string
  brand?: string | null
  displayName: string
  handle?: string | null
  accountKind: string
  connectionStatus: string
  authState: string
  capabilitiesJson: string
  externalReference?: string | null
}

export interface PublishJob {
  id: string
  targetId: string
  contentId: string
  provider: string
  accountId?: string | null
  mode: string
  scheduledFor?: string | null
  status: string
  idempotencyKey: string
  attempt: number
  maxAttempts: number
  remoteId?: string | null
  remoteUrl?: string | null
  lastErrorCode?: string | null
  lastErrorMessage?: string | null
  createdAt: string
  updatedAt: string
}

export interface EnqueueInput {
  targetId: string
  accountId?: string | null
  mode: string
}

export interface PreflightCheck {
  key: string
  label: string
  ok: boolean
  blocking: boolean
  detail?: string | null
}

export interface PreflightReport {
  targetId: string
  accountId?: string | null
  provider: string
  ready: boolean
  checks: PreflightCheck[]
}

export interface ExternalPublication {
  id: string
  targetId: string
  provider: string
  method: string
  scheduledAt?: string | null
  remoteUrl?: string | null
  note?: string | null
  createdAt: string
}
