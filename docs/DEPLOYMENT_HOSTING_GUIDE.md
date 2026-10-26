# Deployment & Hosting Guide (superseded)

This guide described a manual NGINX + PM2 setup, a hardcoded English ElevenLabs voice, a seed script for a 300-word list and other details that no longer match the backend.

The current, tested deployment is documented in:

- **[DEPLOYMENT_COOLIFY.md](./DEPLOYMENT_COOLIFY.md)** - Docker / Coolify deployment for `https://be-kogo.taro.web.id` (Dockerfile, docker-compose, environment variables, HTTPS, health checks, backups, troubleshooting).
- **[API_DOCUMENTATION.md](./API_DOCUMENTATION.md)** - API reference (v2 device registration and sync, researcher metrics and CSV exports, voice proxy, auth).
- [`backend/.env.example`](../backend/.env.example) - every environment variable with comments.

Flutter app configuration: the APK's default backend base URL is `https://be-kogo.taro.web.id/api`; override it with `--dart-define=KOGO_BACKEND_URL=https://<host>/api` or on the tablet in Research mode, never point release builds at a LAN IP, and never embed the ElevenLabs API key in the APK (use the backend voice proxy). See the field test checklist in [DEPLOYMENT_COOLIFY.md](./DEPLOYMENT_COOLIFY.md) for device approval and `KOGO_ENROLLMENT_KEY`.
