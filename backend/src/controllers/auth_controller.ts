import { Request, Response, NextFunction } from 'express';
import { AuthService } from '../services/auth_service.js';
import { getDbPool } from '../config/database.js';
import { registerSchema, childRegisterSchema, loginSchema } from '../types/schemas.js';
import { ForbiddenError } from '../types/errors.js';
import { STAFF_ROLES } from '../types/user.js';

export class AuthController {
  private getService(): AuthService {
    return new AuthService(getDbPool());
  }

  /**
   * Registrasi akun oleh staf yang login (route mewajibkan admin/researcher/
   * teacher). Akun staf (admin/researcher/teacher) hanya dapat dibuat admin;
   * researcher/teacher hanya dapat membuat akun anak (`child`/`student`).
   * Tidak ada registrasi publik, sehingga endpoint ini tidak dapat dipakai
   * untuk enumerasi username atau kode peserta.
   */
  register = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const data = registerSchema.parse(req.body ?? {});
      const role = data.role ?? 'child';

      if (STAFF_ROLES.includes(role) && req.user?.role !== 'admin') {
        throw new ForbiddenError('Staff accounts can only be created by an administrator.');
      }

      const user = await this.getService().registerUser({
        username: data.username,
        password: data.password,
        fullName: data.fullName,
        role,
        ageYears: data.ageYears,
        schoolName: data.schoolName,
      });

      res.status(201).json({
        status: 'success',
        message: 'Akun berhasil didaftarkan',
        data: user,
      });
    } catch (err) {
      next(err);
    }
  };

  registerChild = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const data = childRegisterSchema.parse(req.body ?? {});

      const user = await this.getService().registerUser({
        username: data.username,
        password: data.password,
        fullName: data.fullName,
        role: 'child', // Paksa role 'child' oleh kebijakan backend
        ageYears: data.ageYears,
        schoolName: data.schoolName,
      });

      res.status(201).json({
        status: 'success',
        message: 'Registrasi anak berhasil',
        data: user,
      });
    } catch (err) {
      next(err);
    }
  };

  login = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const data = loginSchema.parse(req.body ?? {});
      const result = await this.getService().login(data.username, data.password);

      res.status(200).json({
        status: 'success',
        message: 'Login berhasil',
        data: result,
      });
    } catch (err) {
      next(err);
    }
  };

  me = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const user = await this.getService().getUserProfile(req.user!.userId);

      res.status(200).json({
        status: 'success',
        data: user,
      });
    } catch (err) {
      next(err);
    }
  };

  logout = async (_req: Request, res: Response): Promise<void> => {
    // Stateless JWT logout: klien menghapus token lokal
    res.status(200).json({
      status: 'success',
      message: 'Logged out successfully. Please clear your client-side tokens.',
    });
  };
}
