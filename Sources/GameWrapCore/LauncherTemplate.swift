/// The executable inside every built game (Contents/MacOS/launcher).
/// It reads Resources/gamewrap.json, prepares the Wine prefix on first launch, then starts the game.
enum LauncherTemplate {
    static let script = #"""
#!/bin/zsh
# GameWrap launcher: runs the bundled Windows game through the bundled Wine runtime.
# Settings come from Contents/Resources/gamewrap.json.
RES="${0:A:h:h}/Resources"
MANIFEST="$RES/gamewrap.json"

read -r -d '' PARSE_JS <<'JS'
function run(argv) {
  ObjC.import('Foundation');
  const text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  const m = JSON.parse(ObjC.unwrap(text));
  const q = s => "'" + String(s).split("'").join("'\\''") + "'";
  const lines = [
    'GW_NAME=' + q(m.name),
    'GW_EXE=' + q(m.exe),
    'GW_SHOWFPS=' + (m.showFPS ? 1 : 0),
    'GW_ARGS=(' + (m.args || []).map(q).join(' ') + ')',
    'GW_REDISTS=(' + (m.redists || []).map(q).join(' ') + ')'
  ];
  for (const k of Object.keys(m.env || {})) {
    if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(k)) lines.push('export ' + k + '=' + q(m.env[k]));
  }
  return lines.join('\n');
}
JS

eval "$(/usr/bin/osascript -l JavaScript -e "$PARSE_JS" "$MANIFEST" 2>/dev/null)"
if [[ -z "$GW_EXE" ]]; then
  /usr/bin/osascript -e 'display alert "This game is damaged" message "Its gamewrap.json could not be read. Rebuild it with GameWrap." as critical' >/dev/null 2>&1
  exit 1
fi

SAFE_NAME="${GW_NAME//[\/:]/-}"
SUPPORT="$HOME/Library/Application Support/$SAFE_NAME"
LOG="$SUPPORT/last-run.log"
WINE="$RES/wine/bin/wine64"
EXE_DIR="$RES/game/${GW_EXE:h}"
export WINEPREFIX="$SUPPORT/prefix"
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
export WINEDEBUG=-all
(( GW_SHOWFPS )) && export MTL_HUD_ENABLED=1
cmd=("$WINE" "${GW_EXE:t}" "${GW_ARGS[@]}")

alert() {
  /usr/bin/osascript -e 'on run argv' -e 'display alert (item 1 of argv) message (item 2 of argv) as critical' -e 'end run' "$GW_NAME" "$1" >/dev/null 2>&1
}

if [[ -n "$GAMEWRAP_DRY_RUN" ]]; then
  env | grep -E '^(WINE|MTL_HUD|ROSETTA_)' | sort
  print -r -- "REDISTS=${(j:|:)GW_REDISTS}"
  print -r -- "CWD=$EXE_DIR"
  print -r -- "EXEC=${(j:|:)cmd}"
  exit 0
fi

if ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  alert "Rosetta 2 is required. Install it by running this in Terminal: softwareupdate --install-rosetta"
  exit 1
fi

mkdir -p "$SUPPORT"

if [[ ! -f "$WINEPREFIX/.gamewrap-ready" ]]; then
  /usr/bin/osascript -e 'on run argv' -e 'display notification "Setting up for first launch, this takes a minute…" with title (item 1 of argv)' -e 'end run' "$GW_NAME" >/dev/null 2>&1
  if ! "$WINE" wineboot --init > "$LOG" 2>&1; then
    alert "First-time setup failed. Details are in $LOG"
    exit 1
  fi
  for redist in "${GW_REDISTS[@]}"; do
    "$WINE" "$RES/game/$redist" /install /quiet /norestart >> "$LOG" 2>&1
  done
  "$RES/wine/bin/wineserver" -w
  touch "$WINEPREFIX/.gamewrap-ready"
fi

cd "$EXE_DIR" || { alert "The game files are missing: $EXE_DIR"; exit 1; }
start=$SECONDS
"${cmd[@]}" > "$LOG" 2>&1
rc=$?
if (( rc != 0 && SECONDS - start < 10 )); then
  alert "$GW_NAME quit unexpectedly. Log: $LOG"
fi
exit $rc
"""#
}
