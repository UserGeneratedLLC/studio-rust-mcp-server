Start or stop play mode or run the server.

Don't enter `run_server` mode unless you are sure no client/player is needed.

Modes:
- `start_play` — enters play testing
- `run_server` — starts a server without a client
- `stop` — exits any active session

If it returns "Previous call to start play session has not been completed",
call with `stop` first, then retry the original mode.
