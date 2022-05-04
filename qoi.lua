-- Works with Lua 5.2, Lua 5.3, Lua 5.4 and LuaJIT out of the box.
-- For Lua 5.1 load the bits module.

local band, bor, lshift, rshift

local bit = bit
if bit32 then bit = bit32 end

if bit then
  band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
end

if _VERSION == "Lua 5.3" or _VERSION == "Lua 5.4" then
  band = load"return function(a,b) return a&b end"()
  bor = load"return function(a,b) return a|b end"()
  lshift = load"return function(a,b) return a<<b end"()
  rshift = load"return function(a,b) return a>>b end"()
end

local function makeu32(a, b, c, d)
  return bor(bor(lshift(a, 24), lshift(b, 16)), bor(lshift(c, 8), d))
end

local byte = string.byte

local function wrap(n)
  return n % 256
end

local function bits(value, index, size)
  return band(rshift(value, index), rshift(255, 8 - size))
end

local function read(f)
  local position = 1
  local readu32, readu8
  if type(f) == "string" then
    readu32 = function()
      local a, b, c, d = byte(s, position, position + 3)
      position = position + 4
      return makeu32(a, b, c, d)
    end
    readu8 = function()
      position = position + 1
      return byte(s, position - 1, position - 1)
    end
  else
    assert(type(f.read) == "function")
    readu32 = function()
      local s = f:read(4)
      local a, b, c, d = byte(s, 1, 4)
      return makeu32(a, b, c, d)
    end

    readu8 = function()
      return byte(f:read(1), 1, 1)
    end
  end
  
  local magic = f:read(4)

  assert(magic == "qoif")
  local w, h = readu32(), readu32()
  local channels, colorspace = readu8(), readu8()

  local array = {}
  for i = 0, 63 do array[i] = {r = 0, g = 0, b = 0, a = 0} end
  
  -- first one at index 0? cool trick, length will be 0
  local pixels = {width = w, height = h, [0] = {r = 0, b = 0, g = 0, a = 255}}
  
  local function addpixel(r, g, b, a)
    local ps = { r = r, g = g, b = b, a = a}
    array[(r * 3 + g * 5 + b * 7 + a * 11) % 64] = ps
    pixels[#pixels + 1] = ps
  end
  
  local function prevpixel()
    return pixels[#pixels]
  end
  
  local numpixels = w * h
  
  while true do
    local b1 = readu8()
    if #pixels == numpixels then
      assert(b1 == 0 and f:read(7) == "\0\0\0\0\0\0\1")
      break
    end
    
    if b1 < 64 then
      -- QOI_OP_INDEX
      local index = b1
      local p = array[index]
      addpixel(p.r, p.g, p.b, p.a)
    elseif b1 < 128 then
      -- QOI_OP_DIFF
      local dr, dg, db = bits(b1, 4, 2) - 2, bits(b1, 2, 2) - 2, bits(b1, 0, 2) - 2
      local prev = prevpixel()
      addpixel(wrap(prev.r + dr), wrap(prev.g + dg), wrap(prev.b + db), prev.a)
    elseif b1 < 192 then
      -- QOI_OP_LUMA
      local b2 = readu8()
      local dg = bits(b1, 0, 6) - 32 -- b1 & 63
      local dr = bits(b2, 4, 4) - 8 + dg
      local db = bits(b2, 0, 4) - 8 + dg
      local prev = prevpixel()
      addpixel(wrap(prev.r + dr), wrap(prev.g + dg), wrap(prev.b + db), prev.a)
    elseif b1 < 254 then
      -- QOI_OP_RUN
      local run = bits(b1, 0, 6) + 1
      for i = 1, run do
        local prev = prevpixel()
        addpixel(prev.r, prev.g, prev.b, prev.a)
      end
    elseif b1 == 254 then
      -- QOI_OP_RGB
      addpixel(readu8(), readu8(), readu8(), prevpixel().a)
    elseif b1 == 255 then
      -- QOI_OP_RGBA
      addpixel(readu8(), readu8(), readu8(), readu8())
    end
  end
  pixels[0] = nil -- clean up
  return pixels
end

if ... then
  local f = io.open(select(1,...), "rb")
  local image = read(f)
  f:close()
  
  print("P3")
  print(image.width, image.height)
  print(255)
  for _, pixel in ipairs(image) do
    print(pixel.r, pixel.g, pixel.b)
  end
end

return read
