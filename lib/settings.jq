# jq helpers for team pi settings, used by steps/50-pi-settings.sh and
# scripts/doctor.sh. Load with: jq -L lib 'include "settings"; ...'
# Pass `team` and `prev` as $variables, not as filters.

# Path to every setting: walks objects only, so arrays count as one value.
def leaves: [paths(type != "object")] | map(select(all(.[]; type == "string")));

# Apply the team settings to the developer's settings (the input).
#   team: config/pi-settings.json now
#   prev: the team settings the kit applied last time
# A value is the developer's own choice only if it differs from what the kit
# applied last time; those are kept. Everything else follows the team file,
# including settings the team has since removed.
def merge(team; prev):
  reduce (team | leaves[]) as $p (.;
    if getpath($p) == null or getpath($p) == (prev | getpath($p))
    then setpath($p; team | getpath($p))
    else . end)
  | reduce (prev | leaves[]) as $p (.;
    if (team | getpath($p)) == null and getpath($p) == (prev | getpath($p))
    then delpaths([$p])
    else . end);

# One line per team setting the developer has overridden.
def overrides(team):
  . as $mine
  | team | leaves[] as $p
  | select(($mine | getpath($p)) != (team | getpath($p)))
  | "\($p | join(".")) = \($mine | getpath($p) | tojson) (team default: \(team | getpath($p) | tojson))";
