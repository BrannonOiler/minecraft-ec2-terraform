[
%{ for idx, player in whitelist ~}
  {
    "uuid": "${player.uuid}",
    "name": "${player.name}"
  }%{ if idx < length(whitelist) - 1 },%{ endif }
%{ endfor ~}
]