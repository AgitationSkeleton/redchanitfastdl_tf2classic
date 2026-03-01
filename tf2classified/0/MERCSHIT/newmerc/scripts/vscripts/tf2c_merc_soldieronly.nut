// IMPORTANT:
// This script is often re-fired on real round restarts (e.g. WaitingForPlayers ending).
// Round restarts can reset entities and wipe runtime AddOutput hooks (like the pill overheal fix).
// So even if we've already defined all functions, we must still run "runtime init" again.
getroottable()["TF2C_MercSoldierOnly_RuntimeInit"] <- function(hostEnt)
{
    // Overheal (pill) idle fix hooker (rehook on each re-fire)
    try
    {
        if (!("g_includedOverhealIdleFix" in getroottable())) ::g_includedOverhealIdleFix <- false;
        if (!::g_includedOverhealIdleFix)
            ::g_includedOverhealIdleFix <- __IncludeScriptSafe("tf2c_overheal_idlefix.nut", getroottable());

        if ("OverhealIdleFix_Init" in getroottable())
        {
            try { OverhealIdleFix_Init(hostEnt); } catch (e2) {}
            // Late re-init to survive entity reset ordering during round restart
            try { EntFireByHandle(hostEnt, "RunScriptCode", "try{ OverhealIdleFix_Init(self); }catch(e){}", 1.5, null, null); } catch (e3) {}
            try { EntFireByHandle(hostEnt, "RunScriptCode", "try{ OverhealIdleFix_Init(self); }catch(e){}", 3.0, null, null); } catch (e4) {}
        }
    }
    catch (e) {}
}

if ("TF2C_MercSoldierOnly_Initialized" in getroottable())
{
    // Functions already defined; only do runtime init and exit.
    try { TF2C_MercSoldierOnly_RuntimeInit(self); } catch (eRI) {}
    return;
}

::TF2C_MercSoldierOnly_Initialized <- true;

// tf2c_merc_soldieronly.nut (base)
// Enforces Soldier + Merc DM model, but ONLY when player is on a real team (team index >= 2).
// If ::randomizerEnabled == 0: strips weapons, gives Engineer pistol + Shovel.
// If ::randomizerEnabled == 1: delegates weapons to tf2c_dmrando.nut (separate file).

::randomizerEnabled <- 1; // 1 = enabled (default), 0 = disabled
::debugLoadoutPrint <- 1; // 1 = print what weapons were given
::g_MercLastLoadoutTime <- {};      // entindex -> last Time() we randomized weapons
::g_MercLastRespawnFxTime <- {};    // entindex -> last Time() we played respawn particle
::g_includedRespawnParticles <- false;


// ---- constants ----
const TF_CLASS_SOLDIER = 3;
const MERC_MODEL = "models/player/hwm/merc_deathmatch.mdl";


// Jump VO
const MERC_JUMP_SOUND_PREFIX = "vo/mercenary_jump0"
const MERC_JUMP_SOUND_SUFFIX = ".mp3"
const MERC_JUMP_SOUND_COUNT  = 3
// Anti-loop guard for forced class regen
::g_forceClassLastTime <- {};

// Include guards
::g_includedDMRando <- false;
::g_includedOverhealIdleFix <- false;

// ---- safe include ----
function __IncludeScriptSafe(scriptName, scopeTable)
{
	// Some TF2C builds have DoIncludeScript(script, scope), others may have 1-arg.
	// Try in decreasing specificity; swallow failures.
	try
	{
		if ("DoIncludeScript" in getroottable())
		{
			// Try 2-arg first
			try { DoIncludeScript(scriptName, scopeTable); return true; } catch (e2) {}
			// Try 1-arg
			try { DoIncludeScript(scriptName); return true; } catch (e1) {}
		}

		if ("IncludeScript" in getroottable())
		{
			// IncludeScript typically takes (name, scope) but some take 1 arg.
			try { IncludeScript(scriptName, scopeTable); return true; } catch (e4) {}
			try { IncludeScript(scriptName); return true; } catch (e3) {}
		}
	}
	catch (e) {}

	return false;
}

// Jump VO
// ---------------------------------------------------------------------------

getroottable()["PlayMercJumpSound"] <- function(player)
{
    local n = 1
    try { n = RandomInt(1, MERC_JUMP_SOUND_COUNT) } catch (e) { n = 1 }

    local snd = MERC_JUMP_SOUND_PREFIX + n.tostring() + MERC_JUMP_SOUND_SUFFIX

    // Try common sound emit paths
    try
    {
        if ("EmitSound" in player)
            player.EmitSound(snd)
        else
            EmitSoundOn(snd, player)
    }
    catch (e)
    {
        try { EmitSoundOn(snd, player) } catch (e2) { }
    }
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



// ---- helpers ----
function __IsValidPlayer(p)
{
	return (p != null && p.IsValid() && p.IsPlayer());
}

function __Now()
{
	try { return Time(); } catch (e) { return 0.0; }
}

function __IsOnPlayableTeam(player)
{
	if (!__IsValidPlayer(player))
		return false;

	local team = 0;
	try { team = player.GetTeam(); } catch (e) { team = 0; }
	return (team >= 2);
}

function __ForceSoldier(player)
{
	if (!__IsValidPlayer(player))
		return false;
	if (!__IsOnPlayableTeam(player))
		return false;

	// Desired class (helps stickiness)
	try { NetProps.SetPropInt(player, "m_Shared.m_iDesiredPlayerClass", TF_CLASS_SOLDIER); } catch (e) {}

	local currentClass = null;
	try { currentClass = NetProps.GetPropInt(player, "m_PlayerClass.m_iClass"); } catch (e) { currentClass = null; }

	if (currentClass == null || currentClass == TF_CLASS_SOLDIER)
		return false;

	// Guard regen spam
	local entIdx = player.entindex();
	local now = __Now();
	if (entIdx in ::g_forceClassLastTime)
	{
		if ((now - ::g_forceClassLastTime[entIdx]) < 0.35)
			return true;
	}
	::g_forceClassLastTime[entIdx] <- now;

	// Change class + regen
	try { if ("SetPlayerClass" in player) player.SetPlayerClass(TF_CLASS_SOLDIER); } catch (e) {}
	try
	{
		if ("ForceRegenerateAndRespawn" in player) player.ForceRegenerateAndRespawn();
		else if ("ForceRespawn" in player) player.ForceRespawn();
	}
	catch (e) {}

	return true;
}

function __ApplyMercModelNow(player)
{
	if (!__IsValidPlayer(player))
		return;
	if (!__IsOnPlayableTeam(player))
		return;

	local applied = false;

	// Prefer class-anim custom model if present
	try
	{
		if ("SetCustomModelWithClassAnimations" in player)
		{
			player.SetCustomModelWithClassAnimations(MERC_MODEL);
			applied = true;
		}
	}
	catch (e) {}

	// TF2C SetCustomModel appears to be 1-arg only.
	if (!applied)
	{
		try
		{
			if ("SetCustomModel" in player)
			{
				player.SetCustomModel(MERC_MODEL);
				applied = true;
			}
		}
		catch (e) {}
	}

	// Fallback
	try { player.SetModel(MERC_MODEL); } catch (e) {}
}

function __ScheduleReapplyModel(player, delay, suffix)
{
	if (!__IsValidPlayer(player))
		return;

	local thinkName = format("MercModelReapply_%d_%s", player.entindex(), suffix);

	player.SetContextThink(thinkName, function()
	{
		if (!__IsOnPlayableTeam(player))
			return null;

		try { NetProps.SetPropInt(player, "m_Shared.m_iDesiredPlayerClass", TF_CLASS_SOLDIER); } catch (e) {}
		__ApplyMercModelNow(player);
		return null;
	}, delay);
}

function __StripWeaponsAll(player)
{
	if ("StripWeapons" in getroottable())
	{
		StripWeapons(player);
		return;
	}
	if ("StripWeaponSlot" in getroottable())
	{
		StripWeaponSlot(player, 0);
		StripWeaponSlot(player, 1);
		StripWeaponSlot(player, 2);
	}
}

function __GiveFallbackLoadout(player)
{
	// Engineer pistol (22) + Shovel (6)
	if ("GivePlayerWeapon" in getroottable())
	{
		try { GivePlayerWeapon(player, 22, 1); } catch (e) {}
		try { GivePlayerWeapon(player, 6,  2); } catch (e2) {}
	}
}

function __LoadDMRando()
{
	if (!::g_includedDMRando)
		::g_includedDMRando <- __IncludeScriptSafe("tf2c_dmrando.nut", getroottable());
	return ::g_includedDMRando;
}

function __DebugPrintLoadout(player, reason)
{
	if (!::debugLoadoutPrint)
		return;
	if (!__IsValidPlayer(player))
		return;

	local pieces = [];
	for (local slot = 0; slot <= 5; slot++)
	{
		local w = null;
		try { if ("GetPlayerWeaponSlot" in player) w = player.GetPlayerWeaponSlot(slot); } catch (e) { w = null; }
		if (w == null) { try { if ("GetWeaponBySlot" in player) w = player.GetWeaponBySlot(slot); } catch (e2) { w = null; } }

		if (w != null)
		{
			local cls = "unknown";
			try { cls = w.GetClassname(); } catch (e3) {}

			local def = -1;
			try { def = NetProps.GetPropInt(w, "m_iItemDefinitionIndex"); } catch (e4) { def = -1; }

			pieces.append(format("S%d:%s(%d)", slot, cls, def));
		}
	}

	printl(format("[TF2C] Loadout %s for #%d: %s",
		reason, player.entindex(), pieces.len() ? pieces.join(" ") : "(no weapons)"));
}

function ApplyMercTweaks(player, reason)
{
	if (!__IsValidPlayer(player))
		return;
	if (!__IsOnPlayableTeam(player))
		return;

	// Enforce class first; if regen triggered, bail.
	if (__ForceSoldier(player))
		return;

	// Always enforce model
	__ApplyMercModelNow(player);
	__ScheduleReapplyModel(player, 0.05, "a");
	__ScheduleReapplyModel(player, 0.12, "b");

	
	// Jump VO think (plays jump sounds)
	try { EnsureJumpThink(player) } catch (e) { }

// Weapons (throttle so we don't shuffle multiple times during spawn bursts)
	local doShuffle = true;
	local nowT = 0.0;
	try { nowT = Time(); } catch (eT) { nowT = 0.0; }
	local entIdx = -1;
	try { entIdx = player.entindex(); } catch (eE) { entIdx = -1; }
	if (entIdx >= 0)
	{
		local lastT = 0.0;
		if (entIdx in ::g_MercLastLoadoutTime)
			lastT = ::g_MercLastLoadoutTime[entIdx];

		if (reason == "spawn" || reason == "post_inventory" || reason == "teamchange")
		{
			// If we already shuffled very recently, skip shuffling again.
			if (nowT > 0.0 && (nowT - lastT) < 0.60)
				doShuffle = false;
			else
				::g_MercLastLoadoutTime[entIdx] <- nowT;
		}
	}

	if (doShuffle)
	{
		__StripWeaponsAll(player);
		// Some weapons spawn wearables/attachments; remove them so transient grants don't stick.
		try { __RemoveWearablesAll(player); } catch (eW) {}

		if (::randomizerEnabled)
		{
			__LoadDMRando();

			if ("GiveMercPrimarySecondary" in getroottable())
				GiveMercPrimarySecondary(player);
			else if ("tf2c_dmrando" in getroottable())
				tf2c_dmrando(player);
			else if ("GiveMercLoadout" in getroottable())
				GiveMercLoadout(player);
			else
				__GiveFallbackLoadout(player);
		}
		else
		{
			__GiveFallbackLoadout(player);
		}
	}

	__ScheduleReapplyModel(player, 0.20, "c");

	// Debug after brief delay
	player.SetContextThink(format("MercDbg_%d_%s", player.entindex(), reason), function()
	{
		__DebugPrintLoadout(player, reason);
		return null;
	}, 0.02);
}

function OnGameEvent_player_spawn(params)
{
	local player = GetPlayerFromUserID(params.userid);
	ApplyMercTweaks(player, "spawn");

	// One random respawn particle per spawn burst
	if (player != null && player.IsValid() && ("RespawnParticles_PlayRandomOnPlayer" in getroottable()))
	{
		local nowT = 0.0;
		try { nowT = Time(); } catch (eT) { nowT = 0.0; }
		local entIdx = -1;
		try { entIdx = player.entindex(); } catch (eE) { entIdx = -1; }
		local doFx = true;
		if (entIdx >= 0)
		{
			local lastFx = 0.0;
			if (entIdx in ::g_MercLastRespawnFxTime)
				lastFx = ::g_MercLastRespawnFxTime[entIdx];
			if (nowT > 0.0 && (nowT - lastFx) < 0.60)
				doFx = false;
			else
				::g_MercLastRespawnFxTime[entIdx] <- nowT;
		}
		if (doFx)
		{
			try { RespawnParticles_PlayRandomOnPlayer(player); } catch (eRP) {}
		}
	}
}


function OnGameEvent_post_inventory_application(params)
{
	local player = GetPlayerFromUserID(params.userid);
	ApplyMercTweaks(player, "post_inventory");
}

function OnGameEvent_player_team(params)
{
	local player = GetPlayerFromUserID(params.userid);
	ApplyMercTweaks(player, "teamchange");
}

function Activate()
{
	try { PrecacheModel(MERC_MODEL); } catch (e) {}

	// Precache jump sounds
	try { PrecacheSound("vo/mercenary_jump01.mp3") } catch (e) { }
	try { PrecacheSound("vo/mercenary_jump02.mp3") } catch (e) { }
	try { PrecacheSound("vo/mercenary_jump03.mp3") } catch (e) { }


	// Respawn particles (respawn.pcf) hook
	if (!::g_includedRespawnParticles)
		::g_includedRespawnParticles <- __IncludeScriptSafe("tf2c_respawn_particles.nut", getroottable());
	if ("RespawnParticles_PrecacheAll" in getroottable())
	{
		try { RespawnParticles_PrecacheAll(); } catch (eRP) {}
	}

	// Overheal (pill) idle fix hooker
	if (!::g_includedOverhealIdleFix)
		::g_includedOverhealIdleFix <- __IncludeScriptSafe("tf2c_overheal_idlefix.nut", getroottable());
	if ("OverhealIdleFix_Init" in getroottable())
	{
		try { OverhealIdleFix_Init(self); } catch (e2) {}
	}

	__CollectEventCallbacks(this, "OnGameEvent_", "GameEventCallbacks", RegisterScriptGameEventListener);
	printl("[TF2C] tf2c_merc_soldieronly base loaded. randomizerEnabled=" + ::randomizerEnabled);
}