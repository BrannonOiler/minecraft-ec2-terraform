# Minecraft fleet EBS backups

This module applies one DLM lifecycle policy to every supplied volume. Each
volume is tagged `Backup=minecraft`, and the shared policy targets that tag.
Keeping one policy avoids duplicate snapshots as the fleet grows.

```hcl
module "ebs_backup" {
  source     = "./modules/ebs-backup"
  volume_ids = { homestead = "vol-0123456789abcdef0" }
}
```
