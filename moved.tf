# Preserve the deployed singleton compute resources while placing them in the fleet module.
moved {
  from = aws_instance.minecraft-server
  to   = module.minecraft_server["homestead"].aws_instance.this
}

moved {
  from = aws_eip.minecraft-server-eip
  to   = module.minecraft_server["homestead"].aws_eip.this
}

# Retain scheduled root-volume protection until the controlled data migration
# flips homestead.migrate_existing_data to true.
moved {
  from = module.ebs_backup.aws_ec2_tag.snapshot_tag
  to   = module.ebs_backup.aws_ec2_tag.snapshot_tag["homestead-root"]
}
