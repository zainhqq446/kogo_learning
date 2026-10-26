# Deployment & Hosting Guide (superseded)

This guide described a manual NGINX + PM2 setup, a hardcoded English ElevenLabs voice, a seed script for a 300-word list and other details that no longer match the backend.

The current, tested deployment is documented in:

- **[DEPLOYMENT_COOLIFY.md](./DEPLOYMENT_COOLIFY.md)** - Docker / Coolify deployment for `https://be-kogo.taro.web.id` (Dockerfile, docker-compose, environment variables, HTTPS, health checks, backups, troubleshooting).
- **[API_DOCUMENTATION.md](./API_DOCUMENTATION.md)** - API reference (v2 device registration and sync, researcher metrics and CSV exports, voice proxy, auth).
- [`backend/.env.example`](../backend/.env.example) - every environment variable with comments.

Flutter app configuration: point the app's backend base URL to `https://be-kogo.taro.web.id/api` (for example via `--dart-define`), never to a LAN IP in release builds, and never embed the ElevenLabs API key in the APK (use the backend voice proxy).
