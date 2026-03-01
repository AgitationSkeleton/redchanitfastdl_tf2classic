// tf2c_merc_soldier_randomizer.nut
// Author: ChatGPT
//
// Server-side TF2 (Source 1) VScript intended to be run by a logic_vscript entity.
// Enforces Soldier-only, sets spawn max HP to 150, sets move speed to Medic speed,

function __IncludeScriptOnce(scriptName)
{
    local rt = getroottable();
    if (!("__includedScripts" in rt))
        rt.__includedScripts <- {};
    if (scriptName in rt.__includedScripts)
        return;
    rt.__includedScripts[scriptName] <- true;

    if ("DoIncludeScript" in rt)
    {
        DoIncludeScript(scriptName, rt);
    }
}

//__IncludeScriptOnce("tf2c_giveweapon_cmd")
__IncludeScriptOnce("tf2c_weapondefs")

// forces a custom player model, and forces custom c_model arms.
//
// Notes:
// - This script avoids using the "::" root-table syntax because some older VScript
//   builds reject it (the earlier "expected '='" compile error).
// - Uses __CollectGameEventCallbacks(this) when available; otherwise falls back to
//   ListenToGameEvent.
//
// Place in: tf/scripts/vscripts/tf2c_merc_soldier_randomizer.nut (or game/scripts/vscripts/...)

const TEAM_UNASSIGNED = 0

// TF2 class IDs (classic Source 1 TF2 numbering)
const TF_CLASS_SOLDIER = 3

// Desired models
const MERC_PLAYER_MODEL = "models/player/hwm/merc_deathmatch.mdl"
const MERC_ARMS_MODEL   = "models/weapons/c_models/c_merc_arms.mdl"

// Jump VO
const MERC_JUMP_SOUND_PREFIX = "vo/mercenary_jump0"
const MERC_JUMP_SOUND_SUFFIX = ".mp3"
const MERC_JUMP_SOUND_COUNT  = 3

// Tuning
// Medic base maxspeed is 320; Soldier is 240 => 320/240 = 1.333333...
const MEDIC_SPEED_MULT = 1.333333

// Stock item definition indexes (TF2/TF2C default)
const ITEMDEF_ENGINEER_PISTOL = 22
const ITEMDEF_SHOVEL = 6
const ITEMDEF_MEDIGUN = 29
const ITEMDEF_KRITZKRIEG = 31
const ITEMDEF_REJUVINATOR = 2018



// If your build doesn't have NetProps, you can comment out the arms override block.
g_scriptHost <- null

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function DebugPrint(msg)
{
    // Toggle this to 1 if you want console spam while testing
    local DEBUG = 0
    if (DEBUG)
        printl("[tf2c_merc_soldieronly] " + msg)
}

// Counts connected players on a team (including the given player if on that team).
function __DMRando_CountPlayersOnTeam(teamNum)
{
    local count = 0
    local ply = null
    while ((ply = Entities.FindByClassname(ply, "player")) != null)
    {
        try
        {
            if (!ply.IsValid()) continue
            if (ply.GetTeam() == teamNum)
                count++
        }
        catch (e0) { }
    }
    return count
}

// True if the player has at least one teammate (i.e., team size > 1).
function __DMRando_TeamHasTeammate(player)
{
    if (player == null || !player.IsValid())
        return false
    local teamNum = 0
    try { teamNum = player.GetTeam() } catch (e0) { teamNum = 0 }
    if (teamNum <= 1)
        return false
    return (__DMRando_CountPlayersOnTeam(teamNum) > 1)
}


// ---------------------------------------------------------------------------
// Weapon helpers
// ---------------------------------------------------------------------------

function StripAllWeapons(player)
{
    if (player == null || !player.IsValid())
        return

    if (!("NetProps" in getroottable()))
        return

    for (local i = 0; i < 8; i++)
    {
        local wpn = null
        try { wpn = NetProps.GetPropEntityArray(player, "m_hMyWeapons", i) } catch (e) { wpn = null }
        if (wpn == null)
            continue

        try { wpn.Destroy() } catch (e) { try { wpn.Kill() } catch (e2) { } }
        try { NetProps.SetPropEntityArray(player, "m_hMyWeapons", null, i) } catch (e) { }
    }
}

getroottable()["FillWeaponAmmo"] <- function(player, weapon, clipCount, reserveCount)
{
	if (!player || !weapon) return;

	// Clip
	try
	{
		NetProps.SetPropInt(weapon, "m_iClip1", clipCount);
	}
	catch (e) {}

	// Reserve ammo
	try
	{
		local ammoType = NetProps.GetPropInt(weapon, "m_iPrimaryAmmoType");
		if (ammoType >= 0)
		{
			NetProps.SetPropIntArray(player, "m_iAmmo", reserveCount, ammoType);
		}
	}
	catch (e) {}
}



g_WeaponAmmoDefaults <- {
	"tf2c_weapon_doubleshotgun" : { clip = -1, max = 8 },
	"tf2c_weapon_cyclops" : { clip = 1, max = 16 },
	"tf_weapon_cannon" : { clip = 4, max = null },
	"tf_weapon_compound_bow" : { clip = -1, max = 12 },
	"tf_weapon_drg_pomson" : { clip = 6, max = null },
	"tf_weapon_flamethrower" : { clip = -1, max = 200 },
	"tf_weapon_flaregun" : { clip = -1, max = 16 },
	"tf_weapon_grenade_mirv" : { clip = -1, max = null },
	"tf_weapon_grenadelauncher" : { clip = 4, max = 16 },
	"tf_weapon_handgun_scout_primary" : { clip = 4, max = null },
	"tf_weapon_laser_pointer" : { clip = -1, max = null },
	"tf_weapon_lunchbox" : { clip = -1, max = null },
	"tf_weapon_medigun" : { clip = -1, max = null },
	"tf_weapon_minigun" : { clip = -1, max = 200 },
	"tf_weapon_pep_brawler_blaster" : { clip = 6, max = null },
	"tf_weapon_pipebomblauncher" : { clip = 8, max = 24 },
	"tf_weapon_pistol" : { clip = 12, max = 200 },
	"tf_weapon_pistol_scout" : { clip = 12, max = 36 },
	"tf_weapon_raygun" : { clip = 6, max = null },
	"tf_weapon_revolver" : { clip = 6, max = 24 },
	"tf_weapon_robot_arm" : { clip = -1, max = null },
	"tf_weapon_rocketlauncher" : { clip = 4, max = 20 },
	"tf_weapon_scattergun" : { clip = 6, max = 32 },
	"tf_weapon_sentry_revenge" : { clip = 6, max = null },
	"tf_weapon_shotgun_building_rescue" : { clip = 6, max = null },
	"tf_weapon_shotgun_hwg" : { clip = 6, max = 32 },
	"tf_weapon_shotgun_primary" : { clip = 6, max = 32 },
	"tf_weapon_shotgun_pyro" : { clip = 6, max = 32 },
	"tf_weapon_shotgun_soldier" : { clip = 6, max = 32 },
	"tf_weapon_smg" : { clip = 25, max = 75 },
	"tf_weapon_sniperrifle" : { clip = -1, max = 25 },
	"tf_weapon_sniperrifle_classic" : { clip = -1, max = null },
	"tf_weapon_sniperrifle_decap" : { clip = -1, max = null },
	"tf_weapon_soda_popper" : { clip = 6, max = null },
	"tf_weapon_syringegun_medic" : { clip = 40, max = 150 },
	"tf_weapon_wrench" : { clip = -1, max = null },
}

// ---------------------------------------------------------------------------
// Ammo normalization
// ---------------------------------------------------------------------------

// Clear *all* reserve ammo buckets to avoid inheriting nonsense when swapping random weapons.
function ClearPlayerReserveAmmo(player)
{
    if (!("NetProps" in getroottable()) || player == null || !player.IsValid())
        return

    // TF2 ammo array is small (<= 32). Over-clearing harmlessly fails in try/catch.
    for (local i = 0; i < 32; i++)
    {
        try { NetProps.SetPropIntArray(player, "m_iAmmo", 0, i) } catch (e) { }
    }
}

function __ComputeReserveFromDefaults(clipCount, maxCount)
{
    if (maxCount == null)
        return null
    if (clipCount == null)
        return maxCount

    // If clipless (clip = -1), treat all ammo as reserve.
    if (clipCount < 0)
        return maxCount

    local reserve = maxCount - clipCount
    if (reserve < 0)
        reserve = 0
    return reserve
}

// Apply "fresh spawn" ammo for the weapon based on scripts/weapon_*.txt defaults.
// This prevents inheriting inflated reserve ammo from a previous weapon with the same ammo type.
function ApplyWeaponAmmoDefaults(player, weapon, weaponClassName)
{
    if (!("NetProps" in getroottable()) || player == null || weapon == null)
        return

    if (!("g_WeaponAmmoDefaults" in getroottable()))
        return
    if (!(weaponClassName in g_WeaponAmmoDefaults))
        return

    local def = g_WeaponAmmoDefaults[weaponClassName]
    local clipCount = null
    local maxCount = null

    try { clipCount = def.clip } catch (e) { clipCount = null }
    try { maxCount = def.max } catch (e) { maxCount = null }

    // Clip
    if (clipCount != null)
    {
        try { NetProps.SetPropInt(weapon, "m_iClip1", clipCount) } catch (e) { }
    }

    // Reserve based on max and clip
    local reserveCount = __ComputeReserveFromDefaults(clipCount, maxCount)
    if (reserveCount == null)
        return

    try
    {
        local ammoType = NetProps.GetPropInt(weapon, "m_iPrimaryAmmoType")
        if (ammoType >= 0)
        {
            NetProps.SetPropIntArray(player, "m_iAmmo", reserveCount, ammoType)
        }
    }
    catch (e2) { }
}

// ---------------------------------------------------------------------------
// Jump VO
// ---------------------------------------------------------------------------

getroottable()["PlayMercJumpSound"] <- function(player)
{
    local n = 1
    try { n = RandomInt(1, MERC_JUMP_SOUND_COUNT) } catch (e) { n = 1 }

    local snd = MERC_JUMP_SOUND_PREFIX + n.tostring() + MERC_JUMP_SOUND_SUFFIX

    // Emit as a world sound from the jumping player's entity.
    // (If the soundscript has SNDLVL_NONE / attenuation 0, it will still be audible anywhere;
    //  in that case fix the soundscript soundlevel/attenuation.)
    try { EmitSoundOn(snd, player) } catch (e2) { }
}

getroottable()["MercJumpThink"] <- function()
{
    // 'self' is player entity here when bound into scope
    local player = self

    // Read buttons + flags via netprops (most reliable across branches)
    local buttons = 0
    local flags = 0
    try { buttons = NetProps.GetPropInt(player, "m_nButtons") } catch (e) { buttons = 0 }
    try { flags = NetProps.GetPropInt(player, "m_fFlags") } catch (e) { flags = 0 }

    // Constants (avoid relying on Constants.* being present)
    const IN_JUMP = 2
    const FL_ONGROUND = 1

    local onGroundNow = ((flags & FL_ONGROUND) != 0)
    local jumpNow = ((buttons & IN_JUMP) != 0)

    // Use player scope for edge detection
    player.ValidateScriptScope()
    local sc = player.GetScriptScope()
    if (!("lastButtons" in sc)) sc.lastButtons <- 0
    if (!("lastOnGround" in sc)) sc.lastOnGround <- true

    local jumpPrev = ((sc.lastButtons & IN_JUMP) != 0)

    // Play when we actually leave the ground while jump is held.
    // This supports holding space (autojump/bhop) because it triggers on the ground->air transition.
    if (sc.lastOnGround && !onGroundNow && jumpNow)
    {
        PlayMercJumpSound(player)
    }
sc.lastButtons = buttons
    sc.lastOnGround = onGroundNow

    return -1
}

getroottable()["EnsureJumpThink"] <- function(player)
{
    if (player == null || !player.IsValid())
        return

    player.ValidateScriptScope()
    local sc = player.GetScriptScope()
    if ("hasJumpThink" in sc && sc.hasJumpThink)
        return

    sc.MercJumpThink <- MercJumpThink
    AddThinkToEnt(player, "MercJumpThink")
    sc.hasJumpThink <- true
}

function GivePlayerWeapon(player, classname, itemDefIndex)
{
    if (player == null || !player.IsValid())
        return null

    local weapon = null
    try { weapon = Entities.CreateByClassname(classname) } catch (e) { weapon = null }
    if (weapon == null)
        return null

    // Setting item definition index is the most reliable way to get a real TF weapon.
    if ("NetProps" in getroottable())
    {
        try { NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", itemDefIndex) } catch (e) { }
        try { NetProps.SetPropBool(weapon, "m_AttributeManager.m_Item.m_bInitialized", true) } catch (e) { }
        try { NetProps.SetPropBool(weapon, "m_bValidatedAttachedEntity", true) } catch (e) { }
    }

    try { weapon.SetTeam(player.GetTeam()) } catch (e) { }
    try { weapon.DispatchSpawn() } catch (e) { }

    // Equip FIRST. If equip fails, do NOT delete the player's existing weapon.
    try { player.Weapon_Equip(weapon) } catch (e) { }

    // Verify that the weapon actually got equipped/owned.
    local equippedOk = false

    if ("NetProps" in getroottable())
    {
        for (local i = 0; i < 8; i++)
        {
            local held = null
            try { held = NetProps.GetPropEntityArray(player, "m_hMyWeapons", i) } catch (e) { held = null }
            if (held == null)
                continue

            if (held == weapon)
            {
                equippedOk = true
                break
            }
        }
    }
    else
    {
        try { equippedOk = (weapon.GetOwner() == player) } catch (e2) { equippedOk = false }
    }

    if (!equippedOk)
    {
        // Avoid leaving an orphaned entity around.
        try { weapon.Destroy() } catch (e3) { try { weapon.Kill() } catch (e4) { } }
        return null
    }

    // Now remove any OTHER weapon in the same slot (prevents duplicates without risking empty slots).
    if ("NetProps" in getroottable())
    {
        local newSlot = -1
        try { newSlot = weapon.GetSlot() } catch (e5) { newSlot = -1 }

        if (newSlot != -1)
        {
            for (local i = 0; i < 8; i++)
            {
                local held = null
                try { held = NetProps.GetPropEntityArray(player, "m_hMyWeapons", i) } catch (e6) { held = null }
                if (held == null)
                    continue
                if (held == weapon)
                    continue

                local heldSlot = -2
                try { heldSlot = held.GetSlot() } catch (e7) { heldSlot = -2 }
                if (heldSlot != newSlot)
                    continue

                try { held.Destroy() } catch (e8) { try { held.Kill() } catch (e9) { } }
                try { NetProps.SetPropEntityArray(player, "m_hMyWeapons", null, i) } catch (e10) { }
            }
        }
    }

    return weapon
}

function __BuildRandomWeaponPools()
{
    // Build once; caches primaries/secondaries from g_WeaponDefs.
    if ("g_RandomPrimaries" in getroottable() && "g_RandomSecondaries" in getroottable())
        return

    getroottable()["g_RandomPrimaries"] <- []
    getroottable()["g_RandomSecondaries"] <- []

    if (!("g_WeaponDefs" in getroottable()))
        return

    foreach (def in g_WeaponDefs)
    {
        if (def == null) continue
        if (!("itemSlot" in def)) continue
        if (!("id" in def)) continue
        if (!("itemClass" in def)) continue

        local cls = null
        try { cls = def.itemClass } catch (e0) { cls = null }
        if (cls == null) continue

        // Exclusions requested:
        // - no revolver
        // - no tranquilizer
        // - no scout pistol (engineer pistol is allowed; it is also tf_weapon_pistol but different itemdef)
        // - avoid non-weapons / wearables / utility items
        if (cls == "tf_weapon_revolver") continue
        if (cls == "tf2c_weapon_tranq") continue

        // Filter out obvious non-ranged weapons & non-weapon entities from tf2c_weapondefs.
        // (We only want things intended as primaries/secondaries.)
        if (cls.find("tf_weapon_wearable") == 0) continue
        if (cls.find("tf_wearable") == 0) continue
        if (cls == "tf_weapon_builder") continue
        if (cls == "tf_weapon_pda_engineer_build") continue
        if (cls == "tf_weapon_pda_engineer_destroy") continue
        if (cls == "tf_weapon_pda_spy") continue
        if (cls == "tf_weapon_sapper") continue
        if (cls == "tf_weapon_invis") continue
        if (cls == "tf_weapon_parachute") continue
        if (cls == "tf_weapon_lunchbox") continue
        // NOTE: mediguns are allowed (Medi Gun / Kritzkrieg).

        // Restrict pistol to Engineer's pistol only (itemdef 22). Exclude Scout pistol (23).
        if (cls == "tf_weapon_pistol" || cls == "tf_weapon_pistol_scout")
        {
            if (def.id != ITEMDEF_ENGINEER_PISTOL)
                continue
            cls = "tf_weapon_pistol"
        }

        if (def.itemSlot == "primary")
            g_RandomPrimaries.append(def)
        else if (def.itemSlot == "secondary")
            g_RandomSecondaries.append(def)
    }
}



function __ResolveWeaponClassForDef(def)
{
    if (def == null) return null

    local cls = null
    try { cls = def.itemClass } catch (e) { cls = null }
    if (cls == null) return null

    // TF2C quirk: the generic "tf_weapon_shotgun" entity may not exist as a creatable classname.
    // For Merc-as-Soldier, use soldier/primary variants so CreateEntityByName succeeds.
    if (cls == "tf_weapon_shotgun")
    {
        local slot = null
        try { slot = def.itemSlot } catch (e2) { slot = null }
        if (slot == "primary")
            return "tf_weapon_shotgun_primary"
        return "tf_weapon_shotgun_soldier"
    }

    return cls
}

function __IsShotgunClass(className)
{
    if (className == null) return false
    // Covers tf_weapon_shotgun_* and tf2c_weapon_doubleshotgun.
    return (className.find("shotgun") != null)
}

// Returns a small record { weapon, className, def, isShotgun }
function __GiveRandomWeaponFromPoolEx(player, pool, excludeShotgun)
{
    if (pool == null || pool.len() <= 0)
        return null

    // Try a few times in case a given def can't be equipped by this class/build.
    for (local tries = 0; tries < 60; tries++)
    {
        local pickIdx = 0
        try { pickIdx = RandomInt(0, pool.len() - 1) } catch (e) { pickIdx = 0 }

        local def = pool[pickIdx]
        if (def == null) continue

        local className = __ResolveWeaponClassForDef(def)
        if (className == null) continue

        // Team-size gate: avoid heal-weapons when the player has no teammates.
        // (Medi Gun, Kritzkrieg, Rejuvenator.)
        if (!__DMRando_TeamHasTeammate(player))
        {
            local defId = 0
            try { defId = def.id } catch (eG0) { defId = 0 }
            if (defId == ITEMDEF_MEDIGUN || defId == ITEMDEF_KRITZKRIEG || defId == ITEMDEF_REJUVINATOR)
                continue
        }

        local isShotgun = __IsShotgunClass(className)
        if (excludeShotgun && isShotgun)
            continue

        local wpn = GivePlayerWeapon(player, className, def.id)
        if (wpn != null)
        {
            // Normalize ammo to "fresh spawn" defaults for that weapon classname.
            try { ApplyWeaponAmmoDefaults(player, wpn, className) } catch (e2) { }
            return { weapon = wpn, className = className, def = def, isShotgun = isShotgun }
        }
    }

    return null
}




// ---------------------------------------------------------------------------
// Tandem entrypoints (used by tf2c_merc_soldieronly.nut)
// ---------------------------------------------------------------------------

// Ensure we have an entity that can run delayed RunScriptCode.
// When this file is included as a library (not run as a logic_vscript itself),
// Activate() will never be called, so g_scriptHost won't be set.
function __DMRando_EnsureScriptHost()
{
    if (g_scriptHost != null)
    {
        try { if (g_scriptHost.IsValid()) return } catch (e0) { }
    }

    local host = null
    try { host = Entities.FindByName(null, "__tf2c_dmrando_host") } catch (e1) { host = null }

    if (host == null)
    {
        try
        {
            // Most Source VScript branches allow spawning logic_script; if it fails, we'll just run without delays.
            host = SpawnEntityFromTable("logic_script", { targetname = "__tf2c_dmrando_host" })
        }
        catch (e2) { host = null }
    }

    g_scriptHost = host
}

function __DMRando_GetEntIndexSafe(ent)
{
    try { return ent.entindex() } catch (e0) { }
    try { return ent.GetEntityIndex() } catch (e1) { }
    return -1
}

// Runs after a short delay to ensure m_iPrimaryAmmoType has settled for newly-given weapons.
function __DMRando_AmmoFixByEntIndex(entIdx)
{
    if (!("EntIndexToHScript" in getroottable()))
        return

    local player = null
    try { player = EntIndexToHScript(entIdx) } catch (e0) { player = null }
    if (player == null || !player.IsValid())
        return

    // Apply defaults to primary + secondary slots if present.
    if (!("NetProps" in getroottable()))
        return

    for (local slot = 0; slot < 2; slot++)
    {
        local wpn = null
        try { wpn = NetProps.GetPropEntityArray(player, "m_hMyWeapons", slot) } catch (e1) { wpn = null }
        if (wpn == null) continue

        local cls = null
        try { cls = wpn.GetClassname() } catch (e2) { cls = null }
        if (cls == null) continue

        try { ApplyWeaponAmmoDefaults(player, wpn, cls) } catch (e3) { }
    }
}

function __DMRando_ScheduleAmmoFix(player, delaySeconds)
{
    __DMRando_EnsureScriptHost()
    if (g_scriptHost == null || !g_scriptHost.IsValid())
        return

    local entIdx = __DMRando_GetEntIndexSafe(player)
    if (entIdx < 0)
        return

    local code = format("__DMRando_AmmoFixByEntIndex(%d)", entIdx)
    EntFireByHandle(g_scriptHost, "RunScriptCode", code, delaySeconds, null, null)
}

// Public entry used by tf2c_merc_soldieronly.nut.
// IMPORTANT: the base script strips weapons before calling this.
// This function gives random PRIMARY + SECONDARY, and also gives the shovel
// so the player is never left without melee (base currently strips everything).
function GiveMercPrimarySecondary(player)
{
    if (player == null || !player.IsValid())
        return

    // Clear reserve ammo buckets so we don't inherit nonsense from prior weapons.
    ClearPlayerReserveAmmo(player)

    __BuildRandomWeaponPools()

    local primaryRec = null
    local secondaryRec = null
    local excludeShotgunForSecondary = false

    if ("g_RandomPrimaries" in getroottable())
    {
        primaryRec = __GiveRandomWeaponFromPoolEx(player, g_RandomPrimaries, false)
        if (primaryRec != null && ("weapon" in primaryRec) && primaryRec.weapon != null && ("isShotgun" in primaryRec) && primaryRec.isShotgun)
            excludeShotgunForSecondary = true
    }

    if ("g_RandomSecondaries" in getroottable())
    {
        secondaryRec = __GiveRandomWeaponFromPoolEx(player, g_RandomSecondaries, excludeShotgunForSecondary)
        if (secondaryRec == null && excludeShotgunForSecondary)
            secondaryRec = __GiveRandomWeaponFromPoolEx(player, g_RandomSecondaries, false)
    }
        // Defensive: if we still somehow ended up with two shotguns, reroll secondary without shotguns once.
        if (primaryRec != null && secondaryRec != null && ("isShotgun" in primaryRec) && ("isShotgun" in secondaryRec) && primaryRec.isShotgun && secondaryRec.isShotgun)
        {
            secondaryRec = __GiveRandomWeaponFromPoolEx(player, g_RandomSecondaries, true)
            if (secondaryRec == null)
                secondaryRec = __GiveRandomWeaponFromPoolEx(player, g_RandomSecondaries, false)
        }


    // Always provide shovel as a safe melee fallback.
    local shovel = null
    try { shovel = GivePlayerWeapon(player, "tf_weapon_shovel", ITEMDEF_SHOVEL) } catch (e0) { shovel = null }

    local primary = (primaryRec != null) ? primaryRec.weapon : null
    local secondary = (secondaryRec != null) ? secondaryRec.weapon : null

    // Delayed ammo fixes (ammo types for some weapons settle slightly after give).
    __DMRando_ScheduleAmmoFix(player, 0.00)
    __DMRando_ScheduleAmmoFix(player, 0.05)
    __DMRando_ScheduleAmmoFix(player, 0.12)

    // Switch preference: primary, then secondary, then shovel.
    try
    {
        if (primary != null) player.Weapon_Switch(primary)
        else if (secondary != null) player.Weapon_Switch(secondary)
        else if (shovel != null) player.Weapon_Switch(shovel)
    }
    catch (e1) { }
}


function GiveMercLoadout(player)
{
    // Random primary + random secondary + shovel
    StripAllWeapons(player)

    // Critical: clear reserve ammo buckets so we don't inherit absurd reserves
    // from whatever the game last had equipped in those ammo types.
    ClearPlayerReserveAmmo(player)

    __BuildRandomWeaponPools()

    local primaryRec = null
    local secondaryRec = null
    local shovel = null

    // Avoid giving *both* slots a shotgun if possible.
    local excludeShotgunForSecondary = false

    if ("g_RandomPrimaries" in getroottable())
    {
        primaryRec = __GiveRandomWeaponFromPoolEx(player, g_RandomPrimaries, false)
        if (primaryRec != null && ("weapon" in primaryRec) && primaryRec.weapon != null && ("isShotgun" in primaryRec) && primaryRec.isShotgun)
            excludeShotgunForSecondary = true
    }

    if ("g_RandomSecondaries" in getroottable())
    {
        secondaryRec = __GiveRandomWeaponFromPoolEx(player, g_RandomSecondaries, excludeShotgunForSecondary)

        // If the pool is basically shotguns and we failed, allow shotguns rather than leaving empty.
        if (secondaryRec == null && excludeShotgunForSecondary)
            secondaryRec = __GiveRandomWeaponFromPoolEx(player, g_RandomSecondaries, false)
    }
        // Defensive: if we still somehow ended up with two shotguns, reroll secondary without shotguns once.
        if (primaryRec != null && secondaryRec != null && ("isShotgun" in primaryRec) && ("isShotgun" in secondaryRec) && primaryRec.isShotgun && secondaryRec.isShotgun)
        {
            secondaryRec = __GiveRandomWeaponFromPoolEx(player, g_RandomSecondaries, true)
            if (secondaryRec == null)
                secondaryRec = __GiveRandomWeaponFromPoolEx(player, g_RandomSecondaries, false)
        }


    shovel = GivePlayerWeapon(player, "tf_weapon_shovel", ITEMDEF_SHOVEL)
    try { ApplyWeaponAmmoDefaults(player, shovel, "tf_weapon_shovel") } catch (e0) { }

    local primary = (primaryRec != null) ? primaryRec.weapon : null
    local secondary = (secondaryRec != null) ? secondaryRec.weapon : null

    // Switch preference: primary, then secondary, then shovel.
    try
    {
        if (primary != null)
            player.Weapon_Switch(primary)
        else if (secondary != null)
            player.Weapon_Switch(secondary)
        else if (shovel != null)
            player.Weapon_Switch(shovel)
    }
    catch (e) { }
}


function ScheduleApplyLoadoutByUserId(userId, delaySeconds)
{
    if (g_scriptHost == null || !g_scriptHost.IsValid())
        return

    local code = format("ApplyLoadoutByUserId(%d)", userId)
    EntFireByHandle(g_scriptHost, "RunScriptCode", code, delaySeconds, null, null)
}

function ApplyLoadoutByUserId(userId)
{
    local player = GetPlayerSafeFromUserId(userId)
    if (player == null)
        return

    local teamNum = 0
    try { teamNum = player.GetTeam() } catch (e) { teamNum = 0 }
    if (teamNum == TEAM_UNASSIGNED)
        return

    GiveMercLoadout(player)
}


function GetPlayerSafeFromUserId(userId)
{
    if (!("GetPlayerFromUserID" in getroottable()))
        return null

    local player = GetPlayerFromUserID(userId)
    if (player == null)
        return null
    if (!player.IsValid())
        return null
    return player
}

function ForceSoldier(player)
{
    // In TF2, the gameevent player_spawn gives you params.class, but players can
    // still swap classes at resupply or via joinclass. We enforce by forcing the
    // desired class and respawning if needed.
    //
    // We prefer netprops because various TF2 branches differ on which methods exist.
    try
    {
        // m_Shared.m_iDesiredPlayerClass is respected on respawn.
        if ("NetProps" in getroottable())
            NetProps.SetPropInt(player, "m_Shared.m_iDesiredPlayerClass", TF_CLASS_SOLDIER)
    }
    catch (e) { }

    // If they're not Soldier right now, force a class change and respawn.
    local currentClass = null
    try
    {
        if ("NetProps" in getroottable())
            currentClass = NetProps.GetPropInt(player, "m_PlayerClass.m_iClass")
    }
    catch (e) { currentClass = null }

    if (currentClass != null && currentClass != TF_CLASS_SOLDIER)
    {
        DebugPrint("Forcing Soldier for userid=" + player.GetUserID())
        try
        {
            // Some TF2 branches expose SetPlayerClass
            if ("SetPlayerClass" in player)
                player.SetPlayerClass(TF_CLASS_SOLDIER)
        }
        catch (e) { }

        // Force a respawn/regenerate to apply the change
        try
        {
            if ("ForceRegenerateAndRespawn" in player)
                player.ForceRegenerateAndRespawn()
            else if ("ForceRespawn" in player)
                player.ForceRespawn()
        }
        catch (e) { }
    }
}

function ApplySpawnTweaks(player)
{
    if (player == null || !player.IsValid())
        return

    // Enforce class first (so the regen doesn't wipe our later tweaks too often)
    ForceSoldier(player)

    // Player model
    try
    {
        // Many TF2 builds prefer SetCustomModel for players over SetModel.
        // (Signature varies by branch; we try the common ones.)
        if ("SetCustomModelWithClassAnimations" in player)
        {
            player.SetCustomModelWithClassAnimations(MERC_PLAYER_MODEL)
        }
        else if ("SetCustomModel" in player)
        {
            // Often: SetCustomModel(model, bUseClassAnimations)
            player.SetCustomModel(MERC_PLAYER_MODEL, true)
        }
        else if ("SetModel" in player)
        {
            player.SetModel(MERC_PLAYER_MODEL)
        }
    }
    catch (e) { }

    // Arms model (viewmodel c_model arms)
    try
    {
        if ("NetProps" in getroottable())
        {
            // This is the common netprop used for player arms.
            // If your branch differs, you'll see a netprop error in console.
            NetProps.SetPropString(player, "m_szArmsModel", MERC_ARMS_MODEL)
        }
    }
    catch (e) { }

    // Speed to Medic speed (multiplier)
    try
    {
        if ("RemoveCustomAttribute" in player)
            player.RemoveCustomAttribute("move speed bonus")
    }
    catch (e) { }

    try
    {
        if ("AddCustomAttribute" in player)
            player.AddCustomAttribute("move speed bonus", MEDIC_SPEED_MULT, -1)
    }
    catch (e) { }
    // Jump VO think (plays jump sounds)
    try { EnsureJumpThink(player) } catch (e) { }

}

function ScheduleApplyTweaksByUserId(userId, delaySeconds)
{
    if (g_scriptHost == null || !g_scriptHost.IsValid())
        return

    // RunScriptCode expects a string; do NOT pass null here.
    // We defer because TF2 clears certain attributes right at spawn.
    local code = format("ApplyTweaksByUserId(%d)", userId)
    EntFireByHandle(g_scriptHost, "RunScriptCode", code, delaySeconds, null, null)
}

function ApplyTweaksByUserId(userId)
{
    local player = GetPlayerSafeFromUserId(userId)
    if (player == null)
        return

    // Ignore the first spawn event where team is 0 (unassigned) / not fully in-game
    local teamNum = 0
    try { teamNum = player.GetTeam() } catch (e) { teamNum = 0 }
    if (teamNum == TEAM_UNASSIGNED)
        return

    ApplySpawnTweaks(player)

    // Loadout is frequently re-applied by the game right after spawn/regen.
    // Do two passes to win the race.
    GiveMercLoadout(player);// Loadout is frequently re-applied by the game right after spawn/regen.
    // Do a couple fast passes to win the race (prevents stock RL flashing).
    ScheduleApplyLoadoutByUserId(userId, 0.00)
    ScheduleApplyLoadoutByUserId(userId, 0.05)
    ScheduleApplyLoadoutByUserId(userId, 0.15)
}

// ---------------------------------------------------------------------------
// Game event callbacks
// ---------------------------------------------------------------------------

function OnGameEvent_player_spawn(params)
{
    // player_spawn includes userid and team; on initial entity creation team=0 (unassigned)
    // The TF2 Game Events page documents userid/team/class keys for player_spawn. fileciteturn16file10
    if (!("userid" in params))
        return

    // Delay slightly so loadout/class/regen has settled
    ScheduleApplyTweaksByUserId(params.userid, 0.05)
}

function OnGameEvent_player_changeclass(params)
{
    // player_changeclass includes userid and class. fileciteturn16file0
    if (!("userid" in params))
        return

    // If they try to change to anything else, force Soldier and then reapply tweaks.
    ScheduleApplyTweaksByUserId(params.userid, 0.01)
}

function OnGameEvent_player_team(params)
{
    if (!("userid" in params))
        return

    // TF2C supports GRN/YLW too; treat any team >= 2 as a "real" team.
    if (!("team" in params))
        return

    local teamNum = params.team
    if (teamNum == TEAM_UNASSIGNED || teamNum == 1)
        return

    // Force class as soon as they join a real team, then apply tweaks/loadout.
    ScheduleApplyTweaksByUserId(params.userid, 0.01)
}


function OnGameEvent_player_activate(params)
{
    // Fired when a player entity is created/joins (userid present). fileciteturn16file0
    if (!("userid" in params))
        return

    // Apply soon after they fully connect; they may still be unassigned.
    ScheduleApplyTweaksByUserId(params.userid, 0.25)
}

function OnGameEvent_post_inventory_application(params)
{
    // Fired after inventory is applied (resupply cabinet, class change, regen, etc.)
    if (!("userid" in params))
        return

    // Re-apply class enforcement, model/speed/hp tweaks, and our custom loadout.
    ScheduleApplyTweaksByUserId(params.userid, 0.00)
}


// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

function Activate()
{
    __IncludeScriptOnce("tf2c_weapondefs.nut");
    __IncludeScriptOnce("tf2c_weaponspawners.nut");
	if ("WeaponSpawners_Init" in getroottable()) { WeaponSpawners_Init(); }
	__IncludeScriptOnce("tf2c_overheal_idlefix.nut");
	if ("OverhealIdleFix_Init" in getroottable()) { OverhealIdleFix_Init(self); }
    // This script is intended to be run server-side by logic_vscript.
    // If it ends up running client-side too, bail out early.
    if ("IsClient" in getroottable())
    {
        try
        {
            if (IsClient())
                return
        }
        catch (e) { }
    }

    g_scriptHost = self
	// Register give-weapon commands once the script host is known.
	//try { TF2C_GiveWeaponCmd_Activate(g_scriptHost) } catch (e) { }

    // Precache models if the branch exposes PrecacheModel
    try
    {
        if ("PrecacheModel" in getroottable())
        {
            PrecacheModel(MERC_PLAYER_MODEL)
            PrecacheModel(MERC_ARMS_MODEL)

            // Precache jump sounds
            try { PrecacheSound("vo/mercenary_jump01.mp3") } catch (e) { }
            try { PrecacheSound("vo/mercenary_jump02.mp3") } catch (e) { }
            try { PrecacheSound("vo/mercenary_jump03.mp3") } catch (e) { }
        }
    }
    catch (e) { }

    // Register event callbacks the "official" TF2 way if available.
    if ("__CollectGameEventCallbacks" in getroottable())
    {
        __CollectGameEventCallbacks(this)
    }
    else if ("ListenToGameEvent" in getroottable())
    {
        // ListenToGameEvent requires the scope parameter to be a string, not null.
        ListenToGameEvent("player_spawn", OnGameEvent_player_spawn, "")
        ListenToGameEvent("player_changeclass", OnGameEvent_player_changeclass, "")
        ListenToGameEvent("player_team", OnGameEvent_player_team, "")
        ListenToGameEvent("player_activate", OnGameEvent_player_activate, "")
ListenToGameEvent("post_inventory_application", OnGameEvent_post_inventory_application, "")
    }
    else
    {
        printl("[tf2c_merc_soldieronly] ERROR: No game event registration function found.")
    }

    // Apply to any players already in server (e.g. script hot-reload)
    for (local i = 1; i <= MaxClients().tointeger(); i++)
    {
        local p = PlayerInstanceFromIndex(i)
        if (p == null)
            continue
        if (!p.IsValid())
            continue

        // schedule so we don't fight with current spawn processing
        try { ScheduleApplyTweaksByUserId(p.GetUserID(), 0.10) } catch (e) { }
    }

    DebugPrint("Activated and listening for events.")
}
