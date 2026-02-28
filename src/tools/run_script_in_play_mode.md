Run a script in play mode and automatically stop play after script finishes or timeout.

Returns the output of the script.

Result format:
```
{ success: boolean, value: string, error: string, logs: { level: string, message: string, ts: number }[], errors: { level: string, message: string, ts: number }[], duration: number, isTimeout: boolean }
```

Prefer using `start_stop_play` tool instead.
After calling, the datamodel status will be reset to stop mode.

If it returns `StudioTestService: Previous call to start play session has not been completed`,
call `start_stop_play` to stop first then try again.
