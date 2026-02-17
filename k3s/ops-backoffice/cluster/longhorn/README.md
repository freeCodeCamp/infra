# Longhorn Storage

Install Longhorn via Rancher catalog (Apps & Marketplace) on the ops-backoffice cluster.

## Settings

- Replicas: 2
- Default storage class: longhorn
- Backup target: `s3://net.freecodecamp.ops-k3s-backups@nyc3/longhorn/`
- Backup schedule: Daily 2 AM UTC, retention 7 days

## Post-Install

Configure backup target in Longhorn UI (Settings > Backup Target):

- **Backup Target**: `s3://net.freecodecamp.ops-k3s-backups@nyc3/longhorn/`
- **Backup Target Credential Secret**: Create secret `longhorn-backup-s3` in `longhorn-system` namespace with `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`

Then create a recurring backup job (Settings > Recurring Job):

- **Name**: `daily-backup`
- **Task**: Backup
- **Cron**: `0 2 * * *`
- **Retain**: 7
- **Groups**: `default`
