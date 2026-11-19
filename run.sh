#!/bin/zsh
# Start, stop or inspect the installed DeskPad.
#   ./run.sh [start|stop|restart|status|log [n]]
# Start it from a shell that holds Screen Recording and Accessibility (Claude Code's Bash on base-mac does):
# DeskPad inherits both, so macOS asks for nothing. Opening the app from Finder would need its own grants.
BIN=$HOME/Applications/DeskPad.app/Contents/MacOS/DeskPad
LOG=$HOME/Library/Logs/DeskPad/deskpad.log
running() { pgrep -f "^$BIN" }
case ${1:-start} in
  start)
    if running >/dev/null; then echo "DeskPad already running (pid $(running))"; exit 0; fi
    mkdir -p ${LOG:h}
    nohup $BIN >> $LOG 2>&1 &
    disown
    sleep 4; tail -6 $LOG ;;
  stop)
    pkill -TERM -f "^$BIN" && echo "stopping DeskPad"
    for i in {1..20}; do running >/dev/null || break; sleep 0.25; done ;;
  restart) $0 stop; $0 start ;;
  status) running >/dev/null && echo "running (pid $(running))" || echo "not running"; tail -4 $LOG ;;
  log) tail -${2:-30} $LOG ;;
  *) echo "usage: $0 [start|stop|restart|status|log [n]]"; exit 1 ;;
esac
