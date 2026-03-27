Manage maintenance mode for a Kubernetes app.

Usage examples:
- `/maintenance frigate` → suspend
- `/maintenance frigate off` → resume

Arguments received: $ARGUMENTS

If the arguments are just an app name (one word), run:
`task argocd:suspend APP=<appname> SCALE=true`

If the arguments include "off" or "resume", run:
`task argocd:resume APP=<appname> SCALE=true`

Confirm the task completed successfully.
