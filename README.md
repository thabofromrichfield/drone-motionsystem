# Drone Motion System

This repository is the starting point for combining camera motion detection and a DJI drone controller. **Integration, the new database, deployment, and automated flight are not complete.** Do not use this project to operate a real drone without further engineering and testing.

## Imported projects

- `web/`: Xbox Tracking System at `0b9fb191f4149a6e10b8782bd66b518916a9d8e8`, including the camera detector, dashboard, ingest API, schema, bridge, and tests.
- `android/`: GHOSTGRID drone controller at `171cf944a64b3096eab3bfa4a3bf865fcceb9d1d`, including the Android source, simulator backend, and DJI sample code. The large generated DJI reference documentation was not copied; it remains in the [source repository](https://github.com/thabofromrichfield/dronesystem/tree/171cf944a64b3096eab3bfa4a3bf865fcceb9d1d/dji-reference/docs).

Upstream project READMEs describe the original projects, their infrastructure, and their original release procedures; they do not describe a working deployment of this repository.

The tracking app's original `xboxtracking` connection was replaced with the new project's URL and publishable key. It uses a separate local-storage key, requires operator sign-in, and the camera bridge requires an explicit endpoint. The new database currently has no authorized operators, so the app cannot access tracking data yet.

## Important boundaries

- Fresh armed-camera alerts with a detection timestamp create a deduplicated, short-lived request in `drone_dispatch_requests`. The dashboard displays requests and expiry. No controller consumes them yet, and detection does not issue a drone command. The Android simulator refuses flight commands; the full build keeps its original manual confirmation workflow.
- The imported tracking schema allows anonymous camera registration, event writes, dashboard changes, and public evidence access. It is not suitable as an authenticated flight-command source. It must be redesigned and tested before any internet-facing or flight integration deployment. Do not apply `web/sql/schema.sql` unchanged for real operations.
- Vercel can host the web application and its serverless API. It cannot directly connect to the aircraft; a powered, connected Android controller and a separately designed command and telemetry link are needed.
- Real-world autonomous takeoff requires validated aircraft compatibility, authenticated and expiring commands, operator oversight, preflight checks, failsafes, and simulator/hardware testing. Nothing here provides those guarantees yet.

## Current status

The Supabase project `drone-motionsystem` was created in `eu-west-1`. The migrations in `integration/sql/` have been applied. They add an operator allowlist, hardened tracking tables, a private evidence bucket, and the expiring request queue. Row-level security is enabled and anonymous camera registration is denied. The queue was exercised with a rolled-back database transaction covering fresh, duplicate, stale, invalid, test, and disarmed events.

No operator account has been provisioned, so access is currently denied. Browser sign-in, private snapshots, and end-to-end database access still require testing with a provisioned operator.

Pausing the existing `xboxtracking` project was requested with the owner's approval to free a project slot. Its services will remain unavailable until restored.

An empty Vercel project named `drone-motionsystem` was created. It is not linked to Git and has no deployment or configured database connection.

Run the imported detection logic tests with:

```sh
node --test web/tests/*.test.mjs
```

Android builds require the toolchain and, for the full flavor, a DJI SDK key as explained in `android/README.md`. Do not place secrets in this repository.
