Get the currently selected Roblox Studio instance for this session.

Returns studio metadata if a studio is selected and still connected.
If no studio is selected or the selected studio disconnected, returns an error
with guidance to call `list_studios` and `set_studio`.
