#!/bin/sh
set -u

prefix=${1:-}
limit=3
minutes=15

unreadable() {
  printf 'could not read the Swarm\n'
  exit 2
}

cron=$(docker service ls --filter label=swarm.cronjob.enable=true --format 'cron|{{.Name}}') ||
  unreadable
services=$(docker service ls --format '{{.Name}}|{{.Mode}}|{{.Replicas}}') || unreadable

checked=$(printf '%s\n%s\n' "$cron" "$services" | awk -F'|' -v prefix="$prefix" '
  $1 == "cron" { skip[$2] = 1; next }
  substr($1, 1, length(prefix)) == prefix && !skip[$1] && ($2 == "replicated" || $2 == "global")')

below=$(printf '%s\n' "$checked" | awk -F'|' 'NF {
  split($3, replicas, " ")
  split(replicas[1], count, "/")
  if (count[1] + 0 < count[2] + 0) print "below target: " $1 " " replicas[1]
}')

names=$(printf '%s\n' "$checked" | cut -d'|' -f1)
rejecting=
if [ -n "$names" ]; then
  # shellcheck disable=SC2086
  tasks=$(docker service ps $names --format '{{.Node}}|{{.CurrentState}}') || unreadable
  rejecting=$(printf '%s\n' "$tasks" | awk -F'|' -v limit="$limit" -v minutes="$minutes" '
    $2 ~ /^Rejected / {
      age = tolower($2)
      recent = age ~ /second/ || age ~ /about a minute/
      if (age ~ /[0-9]+ minutes? ago/) { split(age, word, " "); recent = word[2] + 0 < minutes }
      if (recent) count[$1]++
    }
    END {
      for (node in count)
        if (count[node] >= limit)
          print "rejecting tasks: " node " (" count[node] " in the last " minutes " min)"
    }')
fi

findings=$(printf '%s\n%s\n' "$below" "$rejecting" | sed '/^$/d')
[ -z "$findings" ] && exit 0
printf '%s\n' "$findings"
exit 1
