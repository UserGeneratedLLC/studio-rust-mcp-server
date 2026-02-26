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
	Compares two values deeply for equality, supporting all Lua language paradigms,
	including cyclic table references.

	It requires that two tables have the same metatable to be considered equal.
	If the metatable provides an `__eq` metamethod, it will be used for comparison.

	@param left T - The first value to compare.
	@param right T - The second value to compare.
	@return boolean - True if the values are deeply equal, false otherwise.
]]
local function DeepEquals<T>(left: T, right: T, seen_: { [any]: { [any]: boolean } }?): boolean
  -- Handle primitive types and same-reference tables.
  if rawequal(left, right) then
    return true
  end

  -- If not tables, perform a simple comparison, accounting for NaN.
  if type(left) ~= "table" or type(right) ~= "table" then
    if (left :: any ~= left :: any) and (right :: any ~= right :: any) then -- nan
      return true
    end
    return false
  end

  -- Tables with different array lengths are not equal.
  if rawlen(left) ~= rawlen(right) then
    return false
  end

  -- Metatables must be identical.
  local leftMT = getmetatable(left)
  local rightMT = getmetatable(right)
  if leftMT ~= rightMT then
    return false
  end

  -- If a metatable with __eq is present, use standard equality.
  if leftMT ~= nil and leftMT.__eq then
    return left == right
  end

  -- Initialize or update the cache to detect cycles.
  local seen: { [any]: { [any]: boolean } } = seen_ or {}
  seen[left] = seen[left] or {}
  seen[right] = seen[right] or {}
  if seen[left][right] then
    return true
  end
  seen[left][right] = true
  seen[right][left] = true

  -- Compare key-value pairs from the left table to the right.
  for k, v in next, left do
    local ov = rawget(right, k)
    if ov == nil or not DeepEquals(v, ov, seen) then
      return false
    end
  end

  -- Ensure the right table does not have extra keys.
  for k, v in next, right do
    local ov = rawget(left, k)
    if ov == nil then
      return false
    end
  end

  -- All checks passed.
  return true
end

return DeepEquals
