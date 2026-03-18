# VEGA tmux session manager - source from ~/.bashrc or copy function there

# VEGA tmux session manager
vega() {
  local session="${1:-vega}"
  local dir
  case "$session" in
    family-hub)      dir="/home/mschlipp/family-hub" ;;
    crypto-monitor)  dir="/home/mschlipp/crypto-monitor" ;;
    business-lunch)  dir="/home/mschlipp/business-lunch" ;;
    minipc-setup)    dir="/home/mschlipp/minipc-setup" ;;
    vega)            dir="/home/mschlipp" ;;
    *)
      echo "Unbekanntes Projekt: $session"
      echo "Bekannt: family-hub, crypto-monitor, business-lunch, minipc-setup"
      return 1
      ;;
  esac

  if tmux has-session -t "$session" 2>/dev/null; then
    tmux attach -t "$session"
  else
    tmux new -s "$session" -c "$dir" \; send-keys "claude" Enter
  fi
}
