--[[
	Step 1 specification.

	Runs the pure shared modules (Format, TableUtil, RNG, Signal, Trove) outside
	Roblox against real assertions, so their logic is verified before anything is
	pasted into Studio.

	Run with:  ./tests/run.sh

	Only genuinely pure modules are covered here. Net, Log and both Bootstraps
	depend on Roblox services and are verified by the in-Studio test list in
	docs/13-build-order.md Step 1.
]]

typeof = type

local _spawn = function(fn, ...) local co = coroutine.create(fn) coroutine.resume(co, ...) end
task = { spawn = _spawn, cancel = function(co) coroutine.close(co) end }

-- Deterministic LCG standing in for Roblox's Random
local RandomMT = {}
RandomMT.__index = RandomMT
function RandomMT:NextNumber(a, b)
    self.s = (self.s * 16807) % 2147483647
    local x = self.s / 2147483647
    if a then return a + x * (b - a) end
    return x
end
function RandomMT:NextInteger(a, b)
    return a + math.floor(self:NextNumber() * (b - a + 1))
end
Random = { new = function(seed) return setmetatable({ s = seed or 12345 }, RandomMT) end }

--@INJECT Format=src/ReplicatedStorage/SAD_Shared/Modules/Format.lua TableUtil=src/ReplicatedStorage/SAD_Shared/Modules/TableUtil.lua RNG=src/ReplicatedStorage/SAD_Shared/Modules/RNG.lua Signal=src/ReplicatedStorage/SAD_Shared/Modules/Signal.lua Trove=src/ReplicatedStorage/SAD_Shared/Modules/Trove.lua@
local passed, failed = 0, 0
local function eq(label, got, want)
    if got == want then passed = passed + 1
    else failed = failed + 1; print(string.format("  FAIL %-42s got %s want %s", label, tostring(got), tostring(want))) end
end
local function ok(label, cond)
    if cond then passed = passed + 1
    else failed = failed + 1; print("  FAIL " .. label) end
end
local function section(name) print("\n== " .. name) end

------------------------------------------------------------------ Format
section("Format.Number")
eq("0",            Format.Number(0), "0")
eq("999",          Format.Number(999), "999")
eq("1000",         Format.Number(1000), "1K")
eq("1234",         Format.Number(1234), "1.23K")
eq("12345",        Format.Number(12345), "12.3K")
eq("123456",       Format.Number(123456), "123K")
eq("999999 rolls", Format.Number(999999), "1M")
eq("1e6",          Format.Number(1000000), "1M")
eq("45.6M",        Format.Number(45600000), "45.6M")
eq("1e9",          Format.Number(1e9), "1B")
eq("1e12",         Format.Number(1e12), "1T")
eq("1e15",         Format.Number(1e15), "1Qa")
eq("1e33",         Format.Number(1e33), "1Dc")
eq("1e36 letters", Format.Number(1e36), "1aa")
eq("negative",     Format.Number(-1234), "-1.23K")
eq("infinity",     Format.Number(math.huge), "MAX")
eq("2200 F/s",     Format.Number(2200), "2.2K")
eq("44747 example",Format.Number(44747), "44.7K")

section("Format.Comma / Time / Clock / Odds / Percent / Multiplier")
eq("comma 1234567", Format.Comma(1234567), "1,234,567")
eq("comma 999",     Format.Comma(999), "999")
eq("comma 1000",    Format.Comma(1000), "1,000")
eq("time 42s",      Format.Time(42), "42s")
eq("time 330",      Format.Time(330), "5m 30s")
eq("time 11520",    Format.Time(11520), "3h 12m")
eq("time 187200",   Format.Time(187200), "2d 4h")
eq("clock 272",     Format.Clock(272), "04:32")
eq("clock 3872",    Format.Clock(3872), "1:04:32")
eq("odds void",     Format.Odds(50, 100000000), "1 IN 2,000,000")
eq("odds ancient",  Format.Odds(100, 100000000), "1 IN 1,000,000")
eq("odds golden",   Format.Odds(12000000, 100000000), "1 IN 8")
eq("odds zero",     Format.Odds(0, 100), "IMPOSSIBLE")
eq("percent",       Format.Percent(0.35), "35%")
eq("multiplier",    Format.Multiplier(3.5), "x3.5")
eq("multiplier int",Format.Multiplier(2), "x2")

------------------------------------------------------------------ TableUtil
section("TableUtil")
local src = { a = 1, nested = { x = { deep = true } } }
local copy = TableUtil.DeepCopy(src)
copy.nested.x.deep = false
eq("DeepCopy independent", src.nested.x.deep, true)

local template = { Fossils = 0, DNA = 0, Settings = { MusicVolume = 60, SfxVolume = 80 }, Dinos = {} }
local saved    = { Fossils = 500, Settings = { MusicVolume = 20 }, Dinos = { abc = { x = 1 } } }
local rec = TableUtil.Reconcile(saved, template)
eq("Reconcile keeps existing",   rec.Fossils, 500)
eq("Reconcile fills missing",    rec.DNA, 0)
eq("Reconcile nested keeps",     rec.Settings.MusicVolume, 20)
eq("Reconcile nested fills",     rec.Settings.SfxVolume, 80)
ok("Reconcile leaves owned dict", rec.Dinos.abc ~= nil and rec.Dinos.abc.x == 1)
eq("Reconcile no extra in Dinos", TableUtil.Count(rec.Dinos), 1)

eq("Count",    TableUtil.Count({a=1,b=2,c=3}), 3)
ok("IsEmpty",  TableUtil.IsEmpty({}))
ok("not empty",not TableUtil.IsEmpty({a=1}))
local sk = TableUtil.SortedKeys({ zeta = 1, alpha = 1, mid = 1 })
eq("SortedKeys deterministic", table.concat(sk, ","), "alpha,mid,zeta")
local frozen = TableUtil.DeepFreeze({ a = { b = 1 } })
ok("DeepFreeze top",    table.isfrozen(frozen))
ok("DeepFreeze nested", table.isfrozen(frozen.a))
ok("DeepEquals true",   TableUtil.DeepEquals({a={b=1}}, {a={b=1}}))
ok("DeepEquals false",  not TableUtil.DeepEquals({a={b=1}}, {a={b=2}}))
ok("DeepEquals extra",  not TableUtil.DeepEquals({a=1}, {a=1,b=2}))

------------------------------------------------------------------ RNG
section("RNG")
local rng = RNG.new(99)
local ORDER = {"common","uncommon","rare","epic","legendary","mythic","ancient","secret","titan"}
local Z1 = { common=62000000, uncommon=27000000, rare=9000000, epic=1800000,
             legendary=190000, mythic=9500, ancient=480, secret=19, titan=1 }
local sum = 0; for _, k in ipairs(ORDER) do sum = sum + Z1[k] end
eq("Zone1 weights sum to 1e8", sum, 100000000)

local counts = {}
for _, k in ipairs(ORDER) do counts[k] = 0 end
local N = 400000
for _ = 1, N do
    local r = RNG.WeightedPick(Z1, rng, ORDER)
    counts[r] = counts[r] + 1
end
local commonPct = counts.common / N * 100
local uncommonPct = counts.uncommon / N * 100
ok(string.format("common ~62%% (got %.2f%%)",   commonPct),   math.abs(commonPct - 62) < 0.6)
ok(string.format("uncommon ~27%% (got %.2f%%)", uncommonPct), math.abs(uncommonPct - 27) < 0.6)
ok("rare bucket populated", counts.rare > 0 and counts.epic > 0)

-- determinism
local a = RNG.new(7); local b = RNG.new(7)
local same = true
for _ = 1, 500 do
    if RNG.WeightedPick(Z1, a, ORDER) ~= RNG.WeightedPick(Z1, b, ORDER) then same = false break end
end
ok("same seed -> same sequence", same)

-- luck
local POWERS = { common=-0.5, uncommon=-0.25, rare=0.15, epic=0.35,
                 legendary=0.55, mythic=0.70, ancient=0.80, secret=0.55, titan=0.40 }
local lucky = RNG.ApplyLuck(Z1, POWERS, 1.0)
ok("luck drains common",   lucky.common < Z1.common)
ok("luck raises legendary",lucky.legendary > Z1.legendary)
ok("luck does not mutate config", Z1.common == 62000000)
local pBase  = RNG.ProbabilityOf(Z1, "mythic")
local pLucky = RNG.ProbabilityOf(lucky, "mythic")
ok(string.format("mythic prob rises %.6f%% -> %.6f%%", pBase*100, pLucky*100), pLucky > pBase)
-- Secret must gain LESS than Mythic at the same luck (the tail guard)
local gainMythic = RNG.ProbabilityOf(lucky,"mythic") / RNG.ProbabilityOf(Z1,"mythic")
local gainSecret = RNG.ProbabilityOf(lucky,"secret") / RNG.ProbabilityOf(Z1,"secret")
ok(string.format("tail guard: mythic x%.3f > secret x%.3f", gainMythic, gainSecret), gainMythic > gainSecret)

local mods = RNG.ApplyModifiers({ electric = 100, golden = 100 }, { electric = 25 }, 40)
eq("modifier applied", mods.electric, 2500)
eq("modifier untouched", mods.golden, 100)
eq("modifier capped", RNG.ApplyModifiers({e=100},{e=90},40).e, 4000)

local zeroPick = RNG.WeightedPick({ a = 0, b = 0 }, rng, {"a","b"})
eq("all-zero weights -> nil", zeroPick, nil)

------------------------------------------------------------------ Signal
section("Signal")
local sig = Signal.new()
local got = {}
local c1 = sig:Connect(function(v) table.insert(got, "a" .. v) end)
sig:Connect(function(v) table.insert(got, "b" .. v) end)
sig:Fire(1)
eq("two handlers fired", #got, 2)
c1:Disconnect()
got = {}
sig:Fire(2)
eq("disconnect works", #got, 1)
ok("connection flag cleared", c1.Connected == false)

local onceCount = 0
local s2 = Signal.new()
s2:Once(function() onceCount = onceCount + 1 end)
s2:Fire(); s2:Fire(); s2:Fire()
eq("Once fires exactly once", onceCount, 1)

-- a handler disconnecting itself mid-fire must not break the iteration
local s3 = Signal.new()
local hits = 0
local self1
self1 = s3:Connect(function() hits = hits + 1; self1:Disconnect() end)
s3:Connect(function() hits = hits + 1 end)
s3:Fire()
eq("self-disconnect mid-fire safe", hits, 2)
s3:Fire()
eq("and it stayed disconnected", hits, 3)

local s4 = Signal.new()
s4:Connect(function() end); s4:Connect(function() end)
s4:DisconnectAll()
local after = 0
s4:Fire()
eq("DisconnectAll", after, 0)

------------------------------------------------------------------ Trove
section("Trove")
local trove = Trove.new()
local calls = {}
trove:Add(function() table.insert(calls, "fn") end)
local fakeInstance = { Destroy = function(self) table.insert(calls, "destroy") end }
trove:Add(fakeInstance)
local fakeConn = { Disconnect = function(self) table.insert(calls, "disconnect") end }
trove:Add(fakeConn)
trove:Clean()
eq("cleaned 3 objects", #calls, 3)
eq("reverse order: conn first", calls[1], "disconnect")
eq("then destroy",             calls[2], "destroy")
eq("then function",            calls[3], "fn")
eq("trove reusable after Clean", #trove._objects, 0)

local t2 = Trove.new()
local removed = false
local obj = { Destroy = function() removed = true end }
t2:Add(obj)
ok("Remove finds object", t2:Remove(obj))
ok("Remove cleaned it", removed)
ok("Remove on missing returns false", t2:Remove({}) == false)

local t3 = Trove.new()
local childCleaned = false
local child = t3:Extend()
child:Add(function() childCleaned = true end)
t3:Clean()
ok("Extend cleans child trove", childCleaned)

local t4 = Trove.new()
local sigT = Signal.new()
local fired = 0
t4:Connect(sigT, function() fired = fired + 1 end)
sigT:Fire(); eq("trove:Connect works", fired, 1)
t4:Clean(); sigT:Fire(); eq("trove cleanup disconnects", fired, 1)

local okAdd = pcall(function() Trove.new():Add(42) end)
ok("Add rejects uncleanable value", not okAdd)

print(string.format("\n%s\n  %d passed, %d failed\n", string.rep("=", 46), passed, failed))
if failed > 0 then error("TESTS FAILED") end
