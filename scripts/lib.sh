# Sourced by scripts in this folder. Bash 3.2 compatible (macOS).

# ask VAR "Question" [default]
# Leaves VAR alone if it's already set (from an argument). Otherwise asks in a
# terminal. Without a terminal (cron, pipes), takes the default, or exits with
# "VAR required" if there isn't one.
ask() {
  local var=$1 question=$2 default=${3:-} reply
  [[ -n "${!var:-}" ]] && return 0
  if [[ ! -t 0 ]]; then
    if [[ -n "$default" ]]; then
      printf -v "$var" '%s' "$default"
      return 0
    fi
    echo "$var required" >&2
    exit 1
  fi
  read -r -p "$question${default:+ [$default]}: " reply
  printf -v "$var" '%s' "${reply:-$default}"
  if [[ -z "${!var}" ]]; then
    echo "$var required" >&2
    exit 1
  fi
}
