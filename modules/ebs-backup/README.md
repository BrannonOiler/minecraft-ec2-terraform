# Minecraft fleet EBS backups

This module applies one DLM lifecycle policy to every supplied volume. Each
volume is tagged `Backup=minecraft`, and the shared policy targets that tag.
The policy retains one daily snapshot created at 09:00 UTC and one weekly
snapshot created Sunday at 09:00 UTC for each volume. Keeping one policy avoids
duplicate snapshots as the fleet grows.

```hcl
module "ebs_backup" {
  source      = "./modules/ebs-backup"
  project_tag = "minecraft-server"
  volume_ids  = { homestead = "vol-0123456789abcdef0" }
}
```
