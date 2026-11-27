# Mobile camera and dashboard

This directory contains the camera detector and dashboard adapted from Xbox Tracking System. It connects only to the separate `drone-motionsystem` Supabase project configured in `src/config.js`. A signed-in operator opens `/camera` on a mobile phone, grants camera access, and keeps the page foregrounded while monitoring. The dashboard is at `/`. No external camera ingestion API, bridge, or server-side Supabase secret is used.

See the [project README](../README.md) for deployment status, access setup, DJI controller requirements, tests and safety limitations. Run `node --test web/tests/*.test.mjs` from the repository root. For local preview, run `python3 web/tools/serve.py 5173`; mobile camera access requires an HTTPS origin.
