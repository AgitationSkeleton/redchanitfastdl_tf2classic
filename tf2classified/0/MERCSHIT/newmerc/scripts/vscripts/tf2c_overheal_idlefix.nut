// tf2c_overheal_idlefix.nut
// Author: ChatGPT
//
// Heal fix only:
// - Hooks trigger_hurt entities whose damage is -20 (healing trigger).
// - If a player is already at >= 200 HP when the trigger fires, add +5 HP.
// - Clamp resulting HP to 300.
// - Does not touch any prop models/animations/rotation.

// Dynamic baseline max health detection:
// We record the first Soldier spawn's health as the "base max health" so servers with modified Soldier HP
// are handled automatically. Fallback is 200 if we can't determine it.
const TF_CLASS_SOLDIER = 3;

::OverhealIdleFix_BaseMaxHealth <- null;
::OverhealIdleFix_FallbackAnnounced <- false;

// Ensure game event callbacks are collected (TF2C/Mapbase convention)
if (!("__CollectGameEventCallbacks" in getroottable()))
{
    getroottable()["__CollectGameEventCallbacks"] <- true;
}
else
{
    getroottable()["__CollectGameEventCallbacks"] = true;
}

function OverhealIdleFix_GetBaseMaxHealth()
{
    if (::OverhealIdleFix_BaseMaxHealth != null && ::OverhealIdleFix_BaseMaxHealth > 0)
        return ::OverhealIdleFix_BaseMaxHealth;

    if (!::OverhealIdleFix_FallbackAnnounced)
    {
        ::OverhealIdleFix_FallbackAnnounced = true;
        printl("[TF2C] OverhealIdleFix: Could not detect Soldier base max health yet; falling back to 200.");
    }
    return 200;
}

// Called when a player spawns; records baseline health from the first Soldier we see.
function OverhealIdleFix_TryRecordBaselineFromPlayer(player)
{
    if (::OverhealIdleFix_BaseMaxHealth != null)
        return;

    if (player == null || !player.IsValid() || !player.IsPlayer())
        return;

    local playerClass = null;
    try { playerClass = NetProps.GetPropInt(player, "m_PlayerClass.m_iClass"); } catch (e0) { playerClass = null; }

    if (playerClass == null || playerClass != TF_CLASS_SOLDIER)
        return;

    local detected = 0;
    try
    {
        if ("GetMaxHealth" in player)
            detected = player.GetMaxHealth().tointeger();
        else
            detected = player.GetHealth().tointeger();
    }
    catch (e1) { detected = 0; }

    if (detected <= 0)
        return;

    ::OverhealIdleFix_BaseMaxHealth = detected;
    printl("[TF2C] OverhealIdleFix: Detected Soldier base max health = " + detected + " (overheal cap remains 300).");
}

function OverhealIdleFix_ScanForBaseline()
{
    if (::OverhealIdleFix_BaseMaxHealth != null)
        return;

    local ply = null;
    while ((ply = Entities.FindByClassname(ply, "player")) != null)
    {
        OverhealIdleFix_TryRecordBaselineFromPlayer(ply);
        if (::OverhealIdleFix_BaseMaxHealth != null)
            return;
    }
}

function OverhealIdleFix_GetTriggerDamage(triggerEnt)
{
    local dmg = 0.0;

    try
    {
        if ("GetDamage" in triggerEnt)
            dmg = triggerEnt.GetDamage().tofloat();
        else if ("NetProps" in getroottable())
            dmg = NetProps.GetPropFloat(triggerEnt, "m_flDamage");
    }
    catch (e)
    {
        dmg = 0.0;
    }

    return dmg;
}

// Zero-arg handler: engine provides activator/caller globals when outputs fire.
getroottable()["OverhealIdleFix_OnTriggerHurt"] <- function()
{
    local rt = getroottable();

    local activatorEnt = ("activator" in rt) ? rt.activator : null;
    local callerEnt = ("caller" in rt) ? rt.caller : null;

    // If caller isn't provided, fall back to self (trigger context).
    if (callerEnt == null)
    {
        try { callerEnt = self; } catch (e0) { callerEnt = null; }
    }

    if (activatorEnt == null || callerEnt == null) return;
    if (!activatorEnt.IsValid() || !callerEnt.IsValid()) return;

    // Only players
    local isPlayer = false;
    try { isPlayer = activatorEnt.IsPlayer(); } catch (e1) { isPlayer = false; }
    if (!isPlayer) return;

    // Only healing triggers set to -20
    local dmg = OverhealIdleFix_GetTriggerDamage(callerEnt);
    if (dmg != -20.0)
        return;

    // Add +5 to CURRENT HP (accounts for already-overhealed)
    local currentHp = 0;
    try { currentHp = activatorEnt.GetHealth().tointeger(); } catch (e2) { currentHp = 0; }

    if (currentHp >= OverhealIdleFix_GetBaseMaxHealth())
    {
        local newHp = currentHp + 5;
        if (newHp > 300) newHp = 300;

        local didSet = false;

        try
        {
            if ("SetHealth" in activatorEnt)
            {
                activatorEnt.SetHealth(newHp);
                didSet = true;
            }
        }
        catch (e3) { didSet = false; }

        if (!didSet && ("NetProps" in rt))
        {
            try { NetProps.SetPropInt(activatorEnt, "m_iHealth", newHp); } catch (e4) { }
        }
    }
}

function OverhealIdleFix_HookOverhealTriggers()
{
    local trig = null;

    while ((trig = Entities.FindByClassname(trig, "trigger_hurt")) != null)
    {
        if (OverhealIdleFix_GetTriggerDamage(trig) != -20.0)
            continue;

        // Hook the trigger. Prefer OnHurtPlayer, fallback to OnStartTouch.
        try
        {
            EntFireByHandle(
                trig,
                "AddOutput",
                "OnHurtPlayer !self:RunScriptCode:OverhealIdleFix_OnTriggerHurt():0:-1",
                0.0,
                null,
                null
            );
        }
        catch (e1)
        {
            try
            {
                EntFireByHandle(
                    trig,
                    "AddOutput",
                    "OnStartTouch !self:RunScriptCode:OverhealIdleFix_OnTriggerHurt():0:-1",
                    0.0,
                    null,
                    null
                );
            }
            catch (e2) { }
        }
    }
}



// Game event hook: record baseline on first Soldier spawn.
getroottable()["OnGameEvent_player_spawn"] <- function(params)
{
    local player = null;
    try { player = GetPlayerFromUserID(params.userid); } catch (e0) { player = null; }
    OverhealIdleFix_TryRecordBaselineFromPlayer(player);
}

getroottable()["OverhealIdleFix_Init"] <- function(hostEnt)
{
    // Delay slightly so all entities exist before we scan/hook
    try
    {
        EntFireByHandle(
            hostEnt,
            "RunScriptCode",
            "OverhealIdleFix_HookOverhealTriggers();",
            0.20,
            null,
            null
        );

        EntFireByHandle(
            hostEnt,
            "RunScriptCode",
            "OverhealIdleFix_ScanForBaseline();",
            0.25,
            null,
            null
        );
        return;
    }
    catch (e) { }

    OverhealIdleFix_HookOverhealTriggers();
}