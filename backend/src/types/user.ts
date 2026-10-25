export type UserRole = 'admin' | 'researcher' | 'teacher' | 'child' | 'student';

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

export interface AuthTokenPayload {
  userId: string;
  username: string;
  role: UserRole;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: string;
}