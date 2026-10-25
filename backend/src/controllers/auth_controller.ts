import { Request, Response, NextFunction } from 'express';
import { AuthService } from '../services/auth_service.js';
import { getDbPool } from '../config/database.js';
import { registerSchema, childRegisterSchema, loginSchema } from '../types/schemas.js';

export class AuthController {
  private getService(): AuthService {
    return new AuthService(getDbPool());
  }

  register = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const data = registerSchema.parse(req.body);
      const service = this.getService();
      
      // Keamanan: Tolak jika client mencoba inject role admin/researcher pada registrasi publik
      let enforcedRole = data.role;
      if (enforcedRole === 'admin' || enforcedRole === 'researcher') {
        // Hanya izinkan jika request memiliki token admin (atau paksa default ke 'child')
        if (req.user?.role !== 'admin') {
          enforcedRole = 'child';
        }
      } else if (!enforcedRole) {
        enforcedRole = 'child';
      }

      const user = await service.registerUser({
        username: data.username,
        password: data.password,
        fullName: data.fullName,
        role: enforcedRole,
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
      const data = childRegisterSchema.parse(req.body);
      const service = this.getService();

      const user = await service.registerUser({
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
      const data = loginSchema.parse(req.body);
      const service = this.getService();
      const result = await service.login(data.username, data.password);

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
      const userId = req.user!.userId;
      const service = this.getService();
      const user = await service.getUserProfile(userId);

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