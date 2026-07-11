# Netlify deploy legacy

## Build settings

- Build command: `pnpm build`
- Publish directory: `dist`

## Environment variables

Required public frontend variables:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

Forbidden variables:

- `SUPABASE_SERVICE_ROLE_KEY`
- `DATABASE_PASSWORD`
- `SUPABASE_ACCESS_TOKEN`
- `JWT_SECRET`

Do not configure server-only secrets in the Netlify frontend environment.

## Netlify setup

1. Open Netlify and select **New site from Git**.
2. Select the repository `mundo-mega-pos-legacy`.
3. Select the branch `legacy/production-snapshot`.
4. Set build command to `pnpm build`.
5. Set publish directory to `dist`.
6. Add the required environment variables:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
7. Start the deploy.

## Post-deploy checks

1. Open the deployed Netlify URL.
2. Log in with the authorized admin user.
3. Confirm that Mundo Mega loads.
4. Confirm that Sucursal Principal loads.
5. Open Productos and confirm product listing.
6. Open Caja and confirm cash status.
7. Run a small test sale using test data only.
8. Confirm the sale appears in recent sales.
9. Close the test cash session if one was opened.

## Known limitation

The corporate control report related to `branch_control_report` / `branch_control_report_v2` remains outside this deployment preparation phase.
