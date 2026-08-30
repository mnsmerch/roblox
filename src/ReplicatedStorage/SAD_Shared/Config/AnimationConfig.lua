--!nonstrict
--[[
	AnimationConfig
	ReplicatedStorage/SAD_Shared/Config/AnimationConfig  (ModuleScript)

	docs/15 §2's clip catalogue, and the procedural motion that stands in for it
	until those clips exist.

	═══ NO ASSET IDS ARE INVENTED HERE ═════════════════════════════════════════
	The table below names clips and says what each one is for. It contains no
	`rbxassetid://` numbers, because there are no animations yet and a made-up
	id is a silent 404 that looks like working code - the same stance
	`SoundController` takes for audio and `ProductConfig` for products.

	Each clip is looked up by NAME in `SAD_Assets/Animations`. Drop an
	`Animation` instance called `Run` in there and every rigged dinosaur runs;
	until then the call falls through to the procedural motion below.
	═══════════════════════════════════════════════════════════════════════════

	═══ THE PLACEHOLDER MODELS CANNOT PLAY ANIMATIONS AT ALL ═══════════════════
	This is the part worth reading before anything else here.

	`WildAIService`'s header says it plainly: guardians "are ANCHORED and moved
	by CFrame rather than driven by Humanoids. The placeholder models have no
	rig." A Roblox `Animation` needs an `Animator`, an `Animator` needs a
	`Humanoid` or `AnimationController`, and both need joints to move. A block
	with a head welded on has none of that.

	So no amount of asset work makes the CURRENT models animate. What can move
	them is a local CFrame offset on top of the server-driven position - a bob,
	a lean, a crouch - and that is what `AnimationController` actually does
	today. When rigged models land, the same call plays the real clip and the
	procedural path stops being used for that model.

	Two paths, one call site, and which one runs is decided by whether the model
	has a rig rather than by a flag somebody has to remember to flip.
	═══════════════════════════════════════════════════════════════════════════

	Depends on: nothing.
]]

local AnimationConfig = {}

--[[
	docs/15 §2's "6 core clips" per dinosaur. `Priority` is that section's own
	ordering: "Idle/Walk/Run for all species → Carry Egg → Trip → Roar → Egg
	crack → everything else. The first four carry 90% of the game's
	readability."

	`Procedural` names the fallback motion that stands in for a missing clip.
	`nil` means there is no honest stand-in and the call is simply a no-op -
	better than a wrong motion, which reads as a bug rather than as absence.
]]
local clips = {}
local clipOrder = {}

local function clip(entry)
	assert(clips[entry.Name] == nil, "duplicate clip: " .. entry.Name)
	clips[entry.Name] = entry
	table.insert(clipOrder, entry.Name)
	return entry
end

-- ── Per dinosaur: the six core clips (docs/15 §2) ───────────────────────────

clip({ Name = "Idle", Group = "core", Priority = 1, Looped = true, Procedural = "breathe" })
clip({ Name = "Walk", Group = "core", Priority = 2, Looped = true, Procedural = "stride" })
clip({ Name = "Run", Group = "core", Priority = 3, Looped = true, Procedural = "stride" })
clip({ Name = "Roar", Group = "core", Priority = 6, Looped = false, Procedural = "rear" })
clip({ Name = "Eat", Group = "core", Priority = 9, Looped = true, Procedural = "graze" })
clip({ Name = "Sleep", Group = "core", Priority = 9, Looped = true, Procedural = "settle" })

-- ── Shared archetype clips (docs/15 §2) ─────────────────────────────────────

clip({ Name = "ChargeWindup", Group = "archetype", Priority = 7, Looped = false, Procedural = "crouch" })
clip({ Name = "Charge", Group = "archetype", Priority = 7, Looped = false, Procedural = "lunge" })
clip({ Name = "TailSweep", Group = "archetype", Priority = 8, Looped = false, Procedural = "sweep" })
clip({ Name = "DiveSwoop", Group = "archetype", Priority = 8, Looped = false, Procedural = "lunge" })
clip({ Name = "Burrow", Group = "archetype", Priority = 8, Looped = false, Procedural = "settle" })
clip({ Name = "Spit", Group = "archetype", Priority = 8, Looped = false, Procedural = "rear" })
clip({ Name = "Honk", Group = "archetype", Priority = 8, Looped = false, Procedural = "rear" })
clip({ Name = "Stomp", Group = "archetype", Priority = 8, Looped = false, Procedural = "slam" })
clip({ Name = "PackCall", Group = "archetype", Priority = 8, Looped = false, Procedural = "rear" })
clip({ Name = "TitanRoar", Group = "archetype", Priority = 5, Looped = false, Procedural = "rear" })

-- ── Player clips (docs/15 §2) ───────────────────────────────────────────────

--[[
	These DO have a rig - the player's own R15 character - so they are the ones
	most likely to work the day an asset lands. No procedural stand-in for most
	of them: a comedic waddle cannot be faked with a CFrame offset without
	fighting Roblox's own character animation, which would look worse than the
	default walk it replaced.
]]
clip({ Name = "CarryEgg", Group = "player", Priority = 4, Looped = true, Procedural = nil })
clip({ Name = "CarryDino", Group = "player", Priority = 4, Looped = true, Procedural = nil })
clip({ Name = "Trip", Group = "player", Priority = 5, Looped = false, Procedural = nil })
clip({ Name = "WindedStagger", Group = "player", Priority = 8, Looped = true, Procedural = nil })
clip({ Name = "StealHold", Group = "player", Priority = 8, Looped = true, Procedural = nil })
clip({ Name = "PlaceDino", Group = "player", Priority = 9, Looped = false, Procedural = nil })
clip({ Name = "CollectIncome", Group = "player", Priority = 9, Looped = false, Procedural = nil })

-- ── Sequences (docs/15 §2) ──────────────────────────────────────────────────

clip({ Name = "EggWobble", Group = "sequence", Priority = 6, Looped = true, Procedural = "wobble" })
clip({ Name = "EggCrack", Group = "sequence", Priority = 7, Looped = false, Procedural = "shudder" })
clip({ Name = "MutationBloom", Group = "sequence", Priority = 7, Looped = false, Procedural = nil })
clip({ Name = "TitanHatch", Group = "sequence", Priority = 9, Looped = false, Procedural = nil })
clip({ Name = "RebirthSweep", Group = "sequence", Priority = 9, Looped = false, Procedural = nil })
clip({ Name = "GuardianDeAggro", Group = "sequence", Priority = 8, Looped = false, Procedural = "settle" })

AnimationConfig.Clips = clips
AnimationConfig.ClipOrder = clipOrder

--- Where `AnimationController` looks for `Animation` instances by name.
AnimationConfig.AssetFolder = "Animations"

-- ── Procedural motion ───────────────────────────────────────────────────────

--[[
	═══ WHAT EACH PROCEDURAL MOTION IS ═════════════════════════════════════════
	Each is a local CFrame offset applied on top of the model's server-driven
	pivot. `Height` is studs, `Pitch` and `Roll` are radians, `Hz` is cycles per
	second. Everything is a small number on purpose: this is a stand-in for
	animation, and a stand-in that draws attention to itself is worse than
	stillness.
	═══════════════════════════════════════════════════════════════════════════
]]
AnimationConfig.Motions = {
	--- A slow vertical breath. The only thing a stationary dinosaur does.
	breathe = { Hz = 0.45, Height = 0.18, Pitch = 0.012, Roll = 0 },

	--- Walking and running share one motion, scaled by speed at the call site:
	--- a faster dinosaur bobs harder and leans further, which is the whole
	--- readability difference between the two.
	stride = { Hz = 1.6, Height = 0.55, Pitch = 0.05, Roll = 0.045 },

	--- Rearing up: roars, honks, spits, pack calls. A pitch back and a lift.
	rear = { Hz = 0, Height = 1.1, Pitch = -0.28, Roll = 0, Secs = 0.9 },

	--- The charge wind-up. docs/03 §1.2 calls this "the tell the player reacts
	--- to", and until now it existed only as a speed change - which is a tell
	--- you feel a second late rather than one you see.
	--[[
		`Secs` is a FLOOR here, not the duration: `AnimationController` overrides
		it with the archetype's own `AbilityWindupSecs`, which range from 0.5 to
		1.0. The first version of this was a fixed 1.0 and the spec caught it -
		a crouch still running when the charge fired is a tell that lies.
	]]
	crouch = { Hz = 6, Height = -0.5, Pitch = 0.22, Roll = 0.03, Secs = 0.5 },

	--- The charge itself, and a dive-bomber's swoop. Nose down, low.
	lunge = { Hz = 0, Height = -0.35, Pitch = 0.30, Roll = 0, Secs = 0.5 },

	--- A spiker's tail sweep: a roll to one side and back.
	sweep = { Hz = 1.4, Height = 0, Pitch = 0, Roll = 0.35, Secs = 0.8 },

	--- A stomper's slam. Up, then hard down.
	slam = { Hz = 0, Height = -0.8, Pitch = 0.10, Roll = 0, Secs = 0.4 },

	--- Grazing and sleeping: nose down, nearly still.
	graze = { Hz = 0.35, Height = -0.25, Pitch = 0.20, Roll = 0, Secs = nil },
	settle = { Hz = 0.2, Height = -0.4, Pitch = 0.08, Roll = 0, Secs = nil },

	--- An incubating egg. docs/15 §2's "wobble → crack → burst".
	wobble = { Hz = 1.1, Height = 0.06, Pitch = 0, Roll = 0.14, Secs = nil },
	shudder = { Hz = 9, Height = 0.10, Pitch = 0, Roll = 0.22, Secs = 0.6 },
}

--[[
	Per-archetype character. Multiplies the motion above, so a Bulldozer lumbers
	at the same code path a Skitterer scurries through.

	docs/15 §2 asks for "shared archetype clips (reused across species)" - this
	is the same idea one layer down: one motion, twenty characters, rather than
	twenty motions.

	Anything not listed uses `Default`. That is deliberate: a new archetype
	should look plausible immediately rather than invisible until somebody
	remembers to tune it.
]]
AnimationConfig.ArchetypeStyle = {
	Default = { HzScale = 1.0, HeightScale = 1.0, LeanScale = 1.0 },

	grazer = { HzScale = 0.75, HeightScale = 0.9, LeanScale = 0.7 },
	skitterer = { HzScale = 2.1, HeightScale = 0.55, LeanScale = 1.3 },
	sprinter = { HzScale = 1.5, HeightScale = 0.8, LeanScale = 1.2 },
	honker = { HzScale = 0.9, HeightScale = 1.1, LeanScale = 0.9 },
	bulldozer = { HzScale = 0.55, HeightScale = 1.5, LeanScale = 0.6 },
	charger = { HzScale = 1.2, HeightScale = 1.0, LeanScale = 1.4 },
	spiker = { HzScale = 0.85, HeightScale = 1.0, LeanScale = 1.1 },
	packhunter = { HzScale = 1.4, HeightScale = 0.75, LeanScale = 1.2 },
	spitter = { HzScale = 1.0, HeightScale = 0.85, LeanScale = 1.0 },
	wader = { HzScale = 0.7, HeightScale = 1.2, LeanScale = 0.8 },
	swimmer = { HzScale = 1.3, HeightScale = 0.6, LeanScale = 1.5 },
	divebomber = { HzScale = 1.8, HeightScale = 0.5, LeanScale = 1.6 },
	glider = { HzScale = 0.6, HeightScale = 0.4, LeanScale = 1.7 },
	ambusher = { HzScale = 1.1, HeightScale = 0.7, LeanScale = 1.1 },
	slasher = { HzScale = 1.35, HeightScale = 0.85, LeanScale = 1.25 },
	stomper = { HzScale = 0.5, HeightScale = 1.7, LeanScale = 0.5 },
	apex = { HzScale = 0.8, HeightScale = 1.3, LeanScale = 0.9 },
	blinker = { HzScale = 2.4, HeightScale = 0.5, LeanScale = 1.1 },
	glitcher = { HzScale = 3.0, HeightScale = 0.35, LeanScale = 1.4 },
	--[[
		A Titan moves SLOWLY and hugely. Making the biggest thing in the game
		bob fastest would read as comic rather than as threatening, which is the
		opposite of what a Titan is for.
	]]
	titan = { HzScale = 0.35, HeightScale = 2.4, LeanScale = 0.45 },
}

function AnimationConfig.StyleFor(archetypeId: string?)
	if not archetypeId then
		return AnimationConfig.ArchetypeStyle.Default
	end
	return AnimationConfig.ArchetypeStyle[archetypeId] or AnimationConfig.ArchetypeStyle.Default
end

-- ── State from observed motion ──────────────────────────────────────────────

--[[
	═══ THE STATE IS DERIVED, NOT SENT ═════════════════════════════════════════
	Which clip a dinosaur should be playing is decided from how fast it is
	actually moving, measured on the client between frames. Not from a remote.

	Two reasons. A guardian's position is already replicated - adding a
	"now I'm running" packet would be sending information the client can
	already see. And a derived state cannot desync: if the model is moving, it
	is running, by definition.

	The thresholds are fractions of `GameConfig.BaseWalkSpeed`, passed in, so
	they follow the game's speed rather than being absolute numbers that stop
	meaning anything the day walk speed changes.
	═══════════════════════════════════════════════════════════════════════════
]]
AnimationConfig.IdleBelowFraction = 0.08
AnimationConfig.RunAboveFraction = 0.55

function AnimationConfig.StateFor(speed: number, baseSpeed: number): string
	if baseSpeed <= 0 then
		return "Idle"
	end
	local fraction = speed / baseSpeed
	if fraction < AnimationConfig.IdleBelowFraction then
		return "Idle"
	elseif fraction < AnimationConfig.RunAboveFraction then
		return "Walk"
	end
	return "Run"
end

--[[
	Which clip an archetype's ability plays. `WildAIService` stamps `Ability` on
	the guardian model when a wind-up starts; this maps it to docs/15 §2's
	shared archetype clips.

	An ability with no entry plays nothing, deliberately: a wrong tell is worse
	than no tell, because a player learns it and then it lies to them.
]]
AnimationConfig.AbilityClip = {
	--[[
		Keyed by `ChaseConfig`'s OWN `Ability` strings, all nine of them. The
		first draft of this table guessed plausible names - `dive`, `packcall`,
		`stomp` - and the spec found six of the nine mapping to nothing, which
		would have been six archetypes whose wind-up led into no tell at all.
		Guessing the key of a table you can read is how that happens.
	]]
	charge = "Charge",       -- Charger: winds up, then a straight line
	swoop = "DiveSwoop",     -- Divebomber
	slow = "Honk",           -- Honker and Spitter: they make you catchable
	roar = "TitanRoar",      -- Titan
	pack = "PackCall",       -- Packhunter's flank call
	burst = "Charge",        -- Apex: a short sprint, the same read as a charge
	--[[
		Blink and Glitch are teleports. `Burrow` is the closest shared clip
		docs/15 §2 lists - a disappearance - and it is the honest choice over
		inventing a tenth clip nobody will animate.
	]]
	blink = "Burrow",
	glitch = "Burrow",
	--[[
		Ambusher's `predict` is a steering change rather than a move: it aims
		where you will be. `TailSweep` reads as a lunge to the side, which is
		what it looks like from the outside.
	]]
	predict = "TailSweep",
}

--- The clip every wind-up plays, whatever the ability that follows it is.
--- One crouch means a player learns the tell once rather than nine times.
AnimationConfig.WindupClip = "ChargeWindup"

-- ── Budget ──────────────────────────────────────────────────────────────────

--[[
	How many models may be animated per frame. `ChaseConfig.MaxActiveGuardians`
	is 20 and a park can hold dozens more, so on a phone this is the one thing
	here that could actually cost frames.

	Models past the budget are simply not offset that frame - they sit at their
	server position, which is where they would be anyway. Nothing breaks; the
	furthest ones just stop breathing.
]]
AnimationConfig.MaxAnimatedPerFrame = 24

--- Beyond this, no procedural motion at all. Smaller than the VFX cull
--- distance because a bob is a subtler thing than a particle and stops being
--- visible sooner.
AnimationConfig.CullDistance = 90

--- Low Graphics cuts both, since this is exactly the budget that setting exists
--- to protect.
AnimationConfig.LowGraphicsScale = 0.45

do
	for _, name in clipOrder do
		local entry = clips[name]
		assert(entry.Priority ~= nil, name .. " has no priority")
		if entry.Procedural then
			assert(AnimationConfig.Motions[entry.Procedural],
				("clip '%s' names procedural motion '%s', which does not exist - "
					.. "it would silently do nothing"):format(name, entry.Procedural))
		end
	end

	assert(AnimationConfig.IdleBelowFraction < AnimationConfig.RunAboveFraction,
		"the idle threshold must sit below the run threshold, or Walk is unreachable")
end

return AnimationConfig
