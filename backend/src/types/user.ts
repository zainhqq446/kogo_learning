export type UserRole = 'admin' | 'researcher' | 'teacher' | 'child' | 'student';

export const USER_ROLES: readonly UserRole[] = ['admin', 'researcher', 'teacher', 'child', 'student'];
export const STAFF_ROLES: readonly UserRole[] = ['admin', 'researcher', 'teacher'];

export interface User {
  id: string;
  username: string;
  password_hash: string;
  full_name: string;
  role: UserRole;
  is_active: boolean;
  age_years?: number | null;
  school_name?: string | null;
  created_at: Date;
  updated_at: Date;
}

export interface UserProfileResponse {
  id: string;
  username: string;
  fullName: string;
  role: UserRole;
  isActive: boolean;
  ageYears?: number | null;
  schoolName?: string | null;
  createdAt: string;
}

/** Payload access token pengguna (peneliti/guru/admin/anak). */
export interface AuthTokenPayload {
  userId: string;
  username: string;
  role: UserRole;
  tokenType: 'access';
}

/** Payload refresh token (tidak pernah diterima sebagai access token). */
export interface RefreshTokenPayload {
  userId: string;
  tokenType: 'refresh';
}

/**
 * Payload token perangkat Android (aplikasi offline-first) untuk sinkronisasi.
 * `sub` sengaja berisi id internal (bukan deviceUuid): payload JWT hanya
 * base64, dan deviceUuid adalah kredensial perangkat yang tidak boleh bocor.
 */
export interface DeviceTokenPayload {
  /** `sub` = id baris `app_devices` (sama dengan `deviceId`). */
  sub: string;
  /** id baris `app_devices` di database. */
  deviceId: string;
  role: 'device';
  tokenType: 'device';
}

export interface DevicePrincipal {
  deviceId: string;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: string;
}
