export interface Participant {
  id: string;
  participant_code: string;
  display_alias: string;
  age_years?: number | null;
  gender?: string | null;
  pin_hash: string;
  created_by_user_id?: string | null;
  is_active: boolean;
  created_at: Date;
  updated_at: Date;
}

export interface Device {
  id: string;
  device_identifier: string;
  device_label?: string | null;
  platform: 'android' | 'ios' | 'windows' | 'macos' | 'linux';
  app_version?: string | null;
  registered_at: Date;
  last_seen_at: Date;
}

export interface ResearchSession {
  id: string;
  client_session_uuid: string;
  participant_id: string;
  device_id: string;
  session_sequence_number: number;
  started_at: Date;
  ended_at?: Date | null;
  notes?: string | null;
  synced_at: Date;
}

export interface SpeechAttempt {
  id: string;
  client_attempt_uuid: string;
  session_id: string;
  participant_id: string;
  device_id: string;
  question_id: number;
  attempt_number: number;
  target_text: string;
  recognized_text: string;
  asr_provider?: string | null;
  locale?: string | null;
  asr_confidence?: number | null;
  duration_ms?: number | null;
  attempted_at: Date;
  synced_at: Date;
}

export type EvaluationStatus = 'EXACT_MATCH' | 'ACCEPTED_SIMILAR' | 'INCORRECT' | 'UNRECOGNIZED';

export interface SimilarityEvaluation {
  id: string;
  attempt_id: string;
  normalized_target: string;
  normalized_recognized: string;
  edit_distance: number;
  similarity_score: number;
  similarity_percent: number;
  is_correct: boolean;
  evaluation_status: EvaluationStatus;
  threshold_used: number;
  evaluation_method: string;
  feedback_text?: string | null;
  created_at: Date;
}