--!strict
--[[
	Types
	ReplicatedStorage/SAD_Shared/Modules/Types  (ModuleScript)

	Shared Luau type definitions. Requiring this module gives you the vocabulary
	the whole codebase speaks:

		local Types = require(Modules.Types)
		local function grant(profile: Types.Profile, amount: number) ... end

	The Profile type mirrors docs/10-data-schema.md exactly. When that document
	changes, this file changes in the same commit.

	Depends on: nothing.
]]

local Types = {}

-- ── Primitives ──────────────────────────────────────────────────────────────
export type Dict<V> = { [string]: V }
export type Array<V> = { V }

export type RarityId = string -- "common" | "uncommon" | ... | "titan"
export type MutationId = string -- "none" | "golden" | ... | "void"
export type SpeciesId = string -- "trex", "velociraptor", ...
export type ZoneId = string -- "plains", "canyon", ...
export type UpgradeId = string
export type DefenceId = string
export type QuestId = string
export type BoostId = string
export type ItemId = string
export type Uid = string -- server-generated 8-char hex

-- ── Owned objects ───────────────────────────────────────────────────────────
export type DinoEntry = {
	SpeciesId: SpeciesId,
	Rarity: RarityId,
	Mutation: MutationId?,
	Mutation2: MutationId?, -- Prime only
	Stars: number, -- 1..5
	Placed: boolean,
	TileX: number?,
	TileZ: number?,
	Vault: number?, -- pedestal index when vaulted
	Locked: boolean,
	Favorite: boolean,
	HatchedAt: number,
	Rerolls: number,
	Origin: ZoneId,
}

export type EggEntry = {
	Rarity: RarityId,
	Origin: ZoneId,
	AcquiredAt: number,
}

export type IncubatorSlot = {
	EggUid: Uid,
	StartedAt: number,
	HatchAt: number,
}

export type IndexEntry = {
	Count: number,
	BestStar: number,
	Mutations: Dict<boolean>,
	FirstAt: number,
}

-- ── Loop content ────────────────────────────────────────────────────────────
export type QuestProgress = {
	Progress: number,
	Claimed: boolean,
}

export type DailyState = {
	LastClaimDay: number,
	DayIndex: number,
	Streak: number,
	BestStreak: number,
}

export type QuestState = {
	Daily: Dict<QuestProgress>,
	Weekly: Dict<QuestProgress>,
	DailyResetDay: number,
	WeeklyResetWeek: number,
	RerollsUsed: number,
}

export type TutorialState = {
	Step: number,
	Completed: boolean,
	SkippedAt: number?,
}

export type Settings = {
	MusicVolume: number,
	SfxVolume: number,
	RareAnnouncements: boolean,
	StealNotifications: boolean,
	TradeRequests: boolean,
	CameraShake: boolean,
	Particles: string, -- "High" | "Medium" | "Off"
	LowGraphics: boolean,
	ShowNameTags: boolean,
	ScreenEffects: boolean,
	UiScale: number,
	AutoCollect: boolean,
}

export type Stats = {
	PlaytimeSecs: number,
	Joins: number,
	EggsStolen: number,
	EggsLost: number,
	EggsHatched: number,
	DinosHatched: number,
	DinosPlaced: number,
	DinosSold: number,
	DinosFused: number,
	DinosStolenFromOthers: number,
	DinosLostToOthers: number,
	RaidsSurvived: number,
	ChasesEscaped: number,
	ChasesCaught: number,
	FossilsEarned: number,
	FossilsSpent: number,
	DnaEarned: number,
	EventsJoined: number,
	RarestRarity: RarityId,
	BestMutation: MutationId,
	PeakIncomePerSec: number,
}

-- ── The profile ─────────────────────────────────────────────────────────────
export type Profile = {
	SchemaVersion: number,

	Fossils: number,
	DNA: number,

	Rebirths: number,
	ZonesUnlocked: Dict<boolean>,
	Upgrades: Dict<number>,
	Defences: Dict<number>,
	LuckNodes: number,

	Dinos: Dict<DinoEntry>,
	Eggs: Dict<EggEntry>,
	Incubators: { [number]: IncubatorSlot },

	Index: Dict<IndexEntry>,
	IndexMilestones: Dict<boolean>,

	Boosts: Dict<number>, -- [boostId] = expiry os.time()
	Items: Dict<number>,
	ShieldUntil: number,
	ShieldBankSecs: number,

	Daily: DailyState,
	Quests: QuestState,
	Tutorial: TutorialState,

	Gamepasses: Dict<boolean>,
	ProcessedReceipts: Array<string>,
	RobuxSpent: number,

	Settings: Settings,
	Stats: Stats,

	LastSeen: number,
	BankedFossils: number,
	BankedAt: number,
	BankedRate: number,
	FirstJoinAt: number,
	NewPlayerProtectionDone: boolean,
}

-- ── Runtime (never saved) ───────────────────────────────────────────────────
export type CarryKind = "egg" | "dino"

export type CarryToken = {
	Kind: CarryKind,
	Uid: Uid,
	OwnerUserId: number,
	OriginKind: string, -- "nest" | "park"
	OriginRef: string, -- nest id, or the victim's userId as a string
	GrantedAt: number,
	ExpiresAt: number,
}

--- The handle Bootstrap injects into every service's Init/Start.
export type App = {
	Get: (name: string) -> any,
	Log: any,
	Net: any,
	Config: any,
	IsServer: boolean,
}

--- Contract every service and controller module must satisfy.
export type Service = {
	Init: ((App) -> ())?,
	Start: ((App) -> ())?,
}

return Types
