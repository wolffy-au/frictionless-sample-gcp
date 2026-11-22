# frictionless-sample-gcp

A minimal, no-cost Google Cloud sample: Firebase Hosting and a Cloud Firestore
database on the free **Spark** plan, so no billing account is needed. It is the
GCP counterpart of `frictionless-sample-azure`. On page load the browser reads
the `demoItems` collection directly from Firestore; on the first visit it
creates the three sample documents if the collection is empty.

## Project layout

| Path | Contents |
| --- | --- |
| `main.tf` | Infrastructure: APIs, Firestore `(default)` database and its security rules |
| `firebase.json` | Hosting config, plus Firestore and emulator config for local runs |
| `firestore.rules` | The access control: public reads, seed-only creates, nothing else |
| `public/` | Static frontend (`index.html`, `app.js`) |
| `deploy.sh` | Provisions the infrastructure with Terraform and deploys Hosting |

## Azure to GCP mapping

| Azure | GCP |
| --- | --- |
| Static Web App (Free) | Firebase Hosting |
| Azure Functions API | None: the browser uses the Firebase SDK, and `firestore.rules` takes the API's place as the access boundary |
| Azure SQL free tier | Cloud Firestore (Standard edition, `(default)` database) |
| `main.bicep` | `main.tf` (Terraform); Hosting content is uploaded by the Firebase CLI, which Terraform cannot do |

Running server-side code on GCP (Cloud Functions, Cloud Run, App Engine) needs
the Blaze plan and a billing account, even inside the free quotas. Leaving the
API out is what keeps this sample on Spark.

## Security model

The page fetches its Firebase web config from Hosting's reserved
`/__/firebase/init.json` URL. That config identifies the project; it is not a
secret. What a browser may do is decided by `firestore.rules`, enforced by
Firestore on every request:

- Anyone may read `demoItems`.
- Documents `1`, `2` and `3` may be **created** only with exactly the seed
  values (kept in sync with `SEED_ITEMS` in `public/app.js`), so whoever visits
  first seeds the collection.
- Nothing may be updated or deleted, and every other collection is denied.

Anyone can still script reads against the collection. On Spark that can use up
the daily free read quota, which stops reads until the quota resets; it cannot
create a bill.

## Prerequisites

- A Firebase project on the free Spark plan. Create it at
  <https://console.firebase.google.com>; no billing account is required.
- [Terraform](https://developer.hashicorp.com/terraform/install) 1.6 or later
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (`gcloud`), used
  only to give Terraform credentials
- Node.js 24 and npm (the version is pinned in `.nvmrc` and `.node-version`)
- Bash and git

On Windows: `winget install Hashicorp.Terraform Google.CloudSDK`.

The Firebase CLI is installed locally by `npm ci`; no global install is needed.

## Deploy

From Bash:

```bash
npm ci
npx firebase login                        # for the Hosting upload
gcloud auth application-default login     # for Terraform
cp .env.sample .env                       # then set PROJECT_ID
bash deploy.sh
```

The script runs `terraform apply`, which enables the APIs, creates the
Firestore `(default)` database (Standard edition, `us-central1` by default) and
releases `firestore.rules`. It shows the plan and asks for confirmation; set
`AUTO_APPROVE=1` to skip that. It then writes `public/version.json` and deploys
Hosting. The app is served at `https://<PROJECT_ID>.web.app`.

If the database or rules already exist, for example because the database was
created in the Firebase console, the script imports them into Terraform state
instead of failing. The database location cannot be changed later.

Terraform keeps its state in `terraform.tfstate` in this directory
(git-ignored). Keep that file: without it, the next run re-imports the existing
resources.

## Run locally

```bash
npx firebase emulators:start --only firestore,hosting --project demo-test
```

Open <http://127.0.0.1:5000>. When the page is served from `localhost` or
`127.0.0.1`, `app.js` connects to the Firestore emulator on port 8080.

## Build version

Before deploying, the script writes `public/version.json` with the output of
`git describe --tags --always --dirty` and the UTC build time. The page footer
shows this so you can tell which build is live:

- Without tags, the version is the short commit hash, for example `abad415`.
- After tagging a release (`git tag v1.0.0`), it shows the distance from that
  tag, for example `v1.0.0-3-gabad415`.
- A `-dirty` suffix means the deploy included uncommitted changes to tracked
  files.

Without the file, for example in the emulator, the footer reads "development
build".

## Free-tier limits

On Spark, Firestore allows 1 GiB stored and 50,000 reads, 20,000 writes and
20,000 deletes a day; Hosting allows 10 GB stored and 360 MB/day of transfer.
Like the Azure SQL free tier pausing, Spark stops serving when a limit is
reached instead of billing: the page shows an error until the daily quota
resets. Each page load costs three Firestore reads.

## License

Copyright (C) 2026 Stephan Borg

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU Affero General Public License as published by the Free
Software Foundation, version 3 of the License. See [LICENSE](LICENSE) for the
full text.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.
