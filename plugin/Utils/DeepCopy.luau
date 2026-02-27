--!strict
--!optimize 2
--[[
	Copyright 2025 Joseph Melsha

	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at

	    http://www.apache.org/licenses/LICENSE-2.0

	Unless required by applicable law or agreed to in writing, software
	distributed under the License is distributed on an "AS IS" BASIS,
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and
	limitations under the License.
]]

--[[
	Deeply copies a value, creating a new instance of all tables within it.
	This function handles cycles and repeated references correctly, ensuring that
	shared tables in the source remain shared in the copy.

	- Keys and values of tables are recursively copied.
	- Metatables are not copied; the new tables will reference the original metatables.
	- Non-table values are returned directly without modification.

	@param value The value to be copied. Can be of any type.
	@param cache_ [Internal] A table used for tracking already-copied tables to handle cycles and shared references.
	@return A deep copy of the input value.
]]
function DeepCopy<T>(value: T, cache_: { [any]: any }?): T
  -- For non-table types, return the value as-is, as they are effectively passed by value.
  if type(value) ~= "table" then
    return value
  end

  -- Use the provided cache or create a new one for this top-level copy operation.
  local cache: { [any]: any } = cache_ or {}

  -- If this table has already been encountered, return the cached copy
  -- to preserve reference structure and avoid infinite loops in cyclic tables.
  local cachedResult = cache[value]
  if cachedResult then
    return cachedResult
  end

  -- Create a new table to store the copy.
  local result = {}
  -- Store the new table in the cache before recursing to handle cycles.
  cache[value] = result

  -- Recursively copy key-value pairs into the new table.
  for k, v in next, value do
    result[DeepCopy(k, cache)] = DeepCopy(v, cache)
  end

  -- Retrieve the original metatable.
  local valueMT = getmetatable(value)
  -- If a metatable exists, assign it to the new table by reference.
  if valueMT then
    setmetatable(result, valueMT :: any)
  end

  return result :: any
end

return DeepCopy
