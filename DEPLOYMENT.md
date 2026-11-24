# GEMBUL Studio deployment and recovery guide

## Current architecture

- The customer website and staff interface are static HTML, CSS, and JavaScript files.
- Supabase provides PostgreSQL, Auth, row-level security, and business RPCs. There is no separate Node/Express API server.
- Capacitor packages the same web pages for Android and iOS. The Android/iOS projects are not production-signed releases.
- Vercel is suitable for the static website. Supabase remains a separate managed backend.
- The browser Supabase URL and publishable/anon key are public client configuration, not secrets. Never put a Supabase `service_role` key in a browser, mobile bundle, Git, or Vercel client build variables.

## Required hosting configuration

In the Vercel project settings, add these environment variables for **Production**, and add separate staging values if a staging deployment is used:

| Variable | Required | Secret? | Purpose |
|---|---:|---:|---|
| `SUPABASE_URL` | Yes for Vercel build | No | HTTPS URL of the Supabase project used by this build |
| `SUPABASE_ANON_KEY` | Yes for Vercel build | No | Supabase publishable key (legacy anon JWT keys are also accepted) |

These are embedded in the generated browser configuration and are therefore public. Do not configure `SUPABASE_SERVICE_ROLE_KEY` for this static client. `.env.example` documents the variables; Vercel reads its environment settings, not a local `.env` file.

## Pre-deployment checklist

1. Create a Vercel project connected to the repository. Set the project root to the repository root.
2. Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` in Vercel's Production environment. Use a separate Supabase project and separate environment values for staging.
3. Confirm Supabase Auth site URL and redirect allow-list include the final HTTPS website origin and `/account.html` recovery route.
4. In a Supabase staging project, run migrations in timestamp order. Check that the migration history matches the repository before applying any migration. Back up the database before production migrations.
5. Test signup, login/logout, password reset, booking, staff permissions, POS, voucher, stock movements, refund, reports, and member stamps in staging.
6. Run `npm ci`, `npm run check`, `npm run test:pwa`, `npm run test:business`, `npm run test:mobile`, and `npm run build:web`.
7. Review the Vercel deployment preview and its response headers. Deploy production only after explicit owner approval.

## Build and local preview

```powershell
npm ci
$env:SUPABASE_URL = "https://YOUR_PROJECT.supabase.co"
$env:SUPABASE_ANON_KEY = "YOUR_PUBLIC_PUBLISHABLE_KEY"
npm run build:web
npm run serve:web
```

`npm run build:web` writes the static website to `dist/`; it does not deploy. A Vercel build fails if either required environment variable is missing. For local development without environment variables, the existing public configuration is copied to `dist`.

Vercel configuration is in `vercel.json`: `npm run build:web` is the build command, `dist` is the output directory, standard security headers are enabled, and authenticated/account/booking/staff pages receive `Cache-Control: no-store`. The PWA service worker does not precache those pages and never serves a cached private page while offline.

## Database migrations and backups

- Production and staging databases are Supabase PostgreSQL projects; do not run migrations against production from an unverified SQL Editor session.
- Review the applied migration history first. The repository currently contains migrations through `20261124040000_fix_customer_signup_phone_conflicts.sql`; apply only missing migrations in order.
- Take a Supabase backup/export before schema changes. Supabase backup retention and point-in-time recovery depend on the selected plan and project configuration; verify them in the Supabase dashboard. This repository does not enable or verify automatic backups.
- Keep database exports encrypted and access-restricted. Do not commit SQL dumps, customer data, or credentials.
- Restore to a separate staging project first. Verify customer/member counts, transaction totals, receipts, and stock movement consistency before any production restore.
- If a migration fails, stop; capture the exact error and applied migration state. Do not rerun or reverse data-changing SQL blindly. Correct the migration forward or restore using the provider's recovery tooling after a verified backup.

Suggested policy: automated daily database backups with at least 30 days of retention, plus a manual pre-migration export. Confirm the plan supports this schedule; it is a recommendation, not an active configuration.

## Storage and external integrations

Current product/barber imagery is served from the repository's `images/` directory. There is no customer-photo upload, expense-proof upload, or object-storage integration in the current app. If uploads are introduced, use Supabase Storage with private buckets, explicit RLS policies, size/type validation, and a backup plan; do not rely on writable local hosting disk.

WhatsApp links open a prefilled message for a human to review and send. There is no WhatsApp Business API integration, automatic delivery, or delivery-status tracking. Google OAuth, push notifications, barcode/QR member cards, PDF/Excel report generation, and barber commission settlement are not implemented as complete end-to-end integrations.

## Custom domain and HTTPS

1. Add the custom domain in Vercel project settings.
2. Configure the exact DNS records Vercel displays at the domain provider. Do not guess A/CNAME values.
3. Wait for Vercel's domain verification and managed TLS certificate issuance.
4. Set the canonical production URL as the Supabase Auth Site URL and allow only required redirect URLs.
5. Verify HTTPS, HTTP-to-HTTPS redirection, password recovery, and authentication redirects before sharing the site.

## Updates and rollback

Use a branch or pull request and Vercel Preview deployments for changes. Verify Supabase migrations and staging flows before promoting code. A Vercel code rollback does **not** roll back a database migration. Prefer backward-compatible, forward-only database changes. If a deployment fails, restore the previous Vercel deployment and diagnose the build/runtime issue; restore database data only from a verified backup and a documented recovery decision.

## Known readiness limits

The local source has automated integration, PWA, business-logic static assertions, and mobile bundle checks. This environment has no running PostgreSQL/Supabase local stack, and no owner credentials were provided, so real database migration execution, Auth end-to-end flows, concurrent POS behavior, and live payment reconciliation have not been independently tested here. Run those checks in staging before production.
