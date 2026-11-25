# Drone Motion System

Integration of the Xbox camera/dashboard and the GHOSTGRID DJI Android controller. **This is a prototype, not cleared for real-world autonomous flight.** The full Android app has not been built or tested with a controller or aircraft, and the web app has not been deployed to Vercel. See the validation requirements below.

## Components

- `web/` preserves the camera detector, dashboard, ingest API and bridge from Xbox Tracking System (`0b9fb191f4149a6e10b8782bd66b518916a9d8e8`).
- `android/` preserves the controller and simulator from GHOSTGRID (`171cf944a64b3096eab3bfa4a3bf865fcceb9d1d`). Most generated DJI docs remain in the [source repository](https://github.com/thabofromrichfield/dronesystem/tree/171cf944a64b3096eab3bfa4a3bf865fcceb9d1d/dji-reference/docs); the verifier's two required reference pages are included here.
- `integration/sql/000_operators.sql` through `009_claim_after_arm.sql` are applied in order to the Supabase project `drone-motionsystem` (`eu-west-1`). Do not apply the original `web/sql/schema.sql` instead: it permits anonymous writes and public evidence.

A fresh motion detection from an armed camera can create a deduplicated dispatch request expiring 20 seconds after detection. The dashboard shows requests, controller heartbeat, latest telemetry and reported SDK results. A signed-in operator can arm the foreground Android controller for one post-arm alert, with a 10-minute lease. The controller checks the aircraft model, link, state, battery, GPS/home, warnings, telemetry freshness and remaining request time before calling the DJI takeoff API. DJI acceptance is **not** evidence that the aircraft is airborne. Stopping the screen disarms it; the simulator refuses flight commands.

These safeguards are not a safety certification. An authorized camera/operator account can submit events, timestamps are supplied by the camera, and tampering, replay and operational risks require further review. Never use the prototype for unattended or real flight. Reconcile platform behavior with local aviation rules and a qualified operator's preflight and emergency procedures.

## Access and deployment

The Supabase database has operator-only policies and private evidence storage. The owner's email was added to the invite allowlist; it is not itself an Auth account. Create an account through the dashboard and verify its email to provision the operator. Signup, confirmation, Realtime, private evidence and the actual ingest path still need real end-to-end testing. Adding an invite for an already verified account requires manual operator provisioning; removing an invite does not revoke an existing operator. Manage both tables through a trusted administrator, not the browser.

A Vercel project `drone-motionsystem` exists but has **no deployment**; attempts through the available deployment connector failed. When deployment is available, use `web` as the project root, verify the serverless `/api/event` route, and add the production site URL to Supabase Auth's redirect allowlist. The local Python preview is only a static development server and its event endpoint is a mock, not the deployed API. The preview URL is temporary and must not be relied on for production.

The existing `xboxtracking` Supabase project was paused with the owner's approval to make room; it remains unavailable until restored.

## Validation

```sh
node --test web/tests/*.test.mjs
python3 -m py_compile web/bridge/xbox-bridge.py
(cd android && python3 tools/verify_structure.py)
# With Kotlin compiler and Java installed:
android/tests/run-dispatch-safety.sh
```

`integration/tests/` contains transactional SQL fixtures. These and the standalone safety tests do not substitute for Android/DJI builds or flight testing. A GitHub Actions workflow checks structure and builds the simulator and full flavor; a runnable full artifact requires a `DJI_API_KEY` Actions secret registered for package `drone.test` in this repository. Never commit the key. See `android/README.md` for original build details; the imported nested workflow does not run automatically in this repository.

Before any hardware use: obtain a working DJI SDK key and build the full app, validate the complete signed-in camera-to-dashboard-to-controller flow, test with DJI simulator and real equipment under controlled conditions, and independently verify aircraft compatibility, permissions, airspace, operator oversight, failsafes and emergency procedures. The requested automatic deployment must not be assumed operational until those steps succeed.
