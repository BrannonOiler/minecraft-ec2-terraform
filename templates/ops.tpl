[
%{ for idx, player in ops ~}
  {
    "uuid": "${player.uuid}",
    "name": "${player.name}",
    "level": 2,
    "bypassesPlayerLimit": true
  }%{ if idx < length(ops) - 1 },%{ endif }
%{ endfor ~}
]