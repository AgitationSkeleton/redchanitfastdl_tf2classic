// tf2c_weaponspawners.nut
// Weapon spawner + pickup system for TF2C (Mapbase VScript).
// - Requires tf2c_weapondefs.nut (weapon definitions table)
// - Optionally integrates with tf2c_giveweapon_cmd.nut (server console commands)
// Author: ChatGPT

// -------------------------------
// Include helpers
// -------------------------------
if (!("__IncludeScriptOnce" in getroottable()))
{
    function __IncludeScriptOnce(scriptName)
    {
        if (!("__includedScripts" in getroottable()))
            ::__includedScripts <- {}
        if (scriptName in ::__includedScripts)
            return true

        local rt = getroottable()
        local ok = false
        try { ok = DoIncludeScript(scriptName, rt) } catch (e) { ok = false }
        if (ok)
            ::__includedScripts[scriptName] <- true
        return ok
    }
}

// Always include weapon defs first.
__IncludeScriptOnce("tf2c_weapondefs.nut")

// Provide GivePlayerWeapon fallback ONLY if missing (so other scripts can own it).
if (!("GivePlayerWeapon" in getroottable()))
{
    function GivePlayerWeapon(player, classname, itemDefIndex)
    {
        if (player == null || !player.IsValid())
            return null

        local weapon = null
        try { weapon = Entities.CreateByClassname(classname) } catch (e) { weapon = null }
        if (weapon == null)
            return null

        if ("NetProps" in getroottable())
        {
            try { NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", itemDefIndex) } catch (e) { }
            try { NetProps.SetPropBool(weapon, "m_AttributeManager.m_Item.m_bInitialized", true) } catch (e) { }
            try { NetProps.SetPropBool(weapon, "m_bValidatedAttachedEntity", true) } catch (e) { }
        }

        try { weapon.SetTeam(player.GetTeam()) } catch (e) { }
        try { weapon.DispatchSpawn() } catch (e) { }

        // Remove existing weapon in the same slot, if we can.
        if ("NetProps" in getroottable())
        {
            local newSlot = -1
            try { newSlot = weapon.GetSlot() } catch (e) { newSlot = -1 }

            if (newSlot != -1)
            {
                for (local i = 0; i < 8; i++)
                {
                    local held = null
                    try { held = NetProps.GetPropEntityArray(player, "m_hMyWeapons", i) } catch (e) { held = null }
                    if (held == null)
                        continue

                    local heldSlot = -2
                    try { heldSlot = held.GetSlot() } catch (e) { heldSlot = -2 }
                    if (heldSlot != newSlot)
                        continue

                    try { held.Destroy() } catch (e) { try { held.Kill() } catch (e2) { } }
                    try { NetProps.SetPropEntityArray(player, "m_hMyWeapons", null, i) } catch (e) { }
                    break
                }
            }
        }

        try { player.Weapon_Equip(weapon) } catch (e) { }
        return weapon
    }
}

// Optional: load giveweapon command script if present.
// If it doesn't exist in your pack, include fails silently and that's OK.
__IncludeScriptOnce("tf2c_giveweapon_cmd.nut")

// -------------------------------
// Config
// -------------------------------
g_weaponSpawnerPrefix <- "weaponspawner_"
g_weaponSpawnerRespawnSeconds <- 15.0
g_weaponSpawnerRotateDegreesPerSec <- 45.0
g_weaponSpawnerTouchPickup <- true // true = touch to pickup

// -------------------------------
// Internal state
// -------------------------------
g_weaponKeyToDef <- {}     // weaponKey -> def table
g_spawnedSpawners <- []    // list of { key, targetEnt, propEnt, trigEnt, nextTime }

// -------------------------------
// String helpers (avoid rfind/replace; TF2C squirrel is older)
// -------------------------------
function _StartsWith(strValue, prefix)
{
    if (strValue == null) return false
    local a = strValue.tostring()
    local b = prefix.tostring()
    if (a.len() < b.len()) return false
    return a.slice(0, b.len()) == b
}

// -------------------------------
// Build indexes from weapon defs
// -------------------------------
function __BuildWeaponIndex()
{
    g_weaponKeyToDef.clear()

    if (!("g_weaponDefs" in getroottable()))
    {
        printl("[tf2c_weaponspawners] ERROR: g_weaponDefs not found. Did tf2c_weapondefs.nut include properly?")
        return
    }

    foreach (key, def in ::g_weaponDefs)
    {
        local weaponKey = key.tostring()
        g_weaponKeyToDef[weaponKey] <- def
    }
}

// -------------------------------
// Precache weapon assets
// -------------------------------
function PrecacheWeaponAssets()
{
    if (!("g_weaponDefs" in getroottable()))
        return

    foreach (key, def in ::g_weaponDefs)
    {
        local worldModel = null
        if ("modelWorld" in def) worldModel = def.modelWorld
        else if ("worldModel" in def) worldModel = def.worldModel

        if (worldModel == null)
            continue

        try { PrecacheModel(worldModel) } catch (e) { }
    }
}

// -------------------------------
// Spawner creation
// -------------------------------
function __CreateSpawnerProp(origin, angles, modelPath, spawnerName)
{
    local kv =
    {
        targetname = spawnerName + "_prop",
        origin = origin,
        angles = angles,
        model = modelPath,
        solid = 0,
        disableshadows = 1,
        rendermode = 0,
        renderamt = 255
    }

    local ent = null
    try { ent = SpawnEntityFromTable("prop_dynamic_override", kv) } catch (e) { ent = null }
    if (ent == null)
        try { ent = SpawnEntityFromTable("prop_dynamic", kv) } catch (e2) { ent = null }

    return ent
}

function __CreateSpawnerTrigger(origin, spawnerName)
{
    local kv =
    {
        targetname = spawnerName + "_trig",
        origin = origin,
        spawnflags = 1,
        StartDisabled = 0
    }

    local trig = null
    try { trig = SpawnEntityFromTable("trigger_multiple", kv) } catch (e) { trig = null }
    if (trig == null)
        return null

    try { trig.SetSize(Vector(-24,-24,0), Vector(24,24,48)) } catch (e2) { }
    try { trig.SetSolid(2) } catch (e3) { }
    return trig
}

function __SpawnerThink()
{
    local now = Time()
    foreach (sp in g_spawnedSpawners)
    {
        if (sp == null) continue
        if (sp.propEnt == null || !sp.propEnt.IsValid()) continue

        local ang = sp.propEnt.GetAngles()
        local delta = g_weaponSpawnerRotateDegreesPerSec * FrameTime()
        sp.propEnt.SetAngles(ang.x, ang.y + delta, ang.z)

        if (now < sp.nextTime)
        {
            try { sp.propEnt.SetRenderAlpha(80) } catch (e) { }
        }
        else
        {
            try { sp.propEnt.SetRenderAlpha(255) } catch (e2) { }
        }
    }
    return 0.0
}

function __FindSpawnerByName(spawnerName)
{
    foreach (sp in g_spawnedSpawners)
    {
        if (sp == null) continue
        if (("targetEnt" in sp) && sp.targetEnt != null && sp.targetEnt.IsValid())
        {
            local tn = ""
            try { tn = sp.targetEnt.GetName() } catch (e) { tn = "" }
            if (tn == spawnerName)
                return sp
        }
    }
    return null
}

function __OnPlayerTouchedSpawner(player, spawnerName, weaponKey)
{
    local sp = __FindSpawnerByName(spawnerName)
    if (sp == null)
        return

    local now = Time()
    if (now < sp.nextTime)
        return

    if (!(weaponKey in g_weaponKeyToDef))
        return

    local def = g_weaponKeyToDef[weaponKey]

    local className = null
    if ("className" in def) className = def.className
    else if ("classname" in def) className = def.classname

    local itemDef = -1
    if ("itemDef" in def) itemDef = def.itemDef
    else if ("itemDefIndex" in def) itemDef = def.itemDefIndex
    else if ("defIndex" in def) itemDef = def.defIndex

    if (className == null || itemDef < 0)
    {
        printl("[tf2c_weaponspawners] WARN: weapon '" + weaponKey + "' missing className/itemDef.")
        return
    }

    local w = GivePlayerWeapon(player, className, itemDef)
    if (w == null)
        return

    sp.nextTime = now + g_weaponSpawnerRespawnSeconds
}

function __SpawnSpawnersFromInfoTargets()
{
    __BuildWeaponIndex()
    PrecacheWeaponAssets()

    local foundTargets = []
    local ent = null
    while ((ent = Entities.FindByClassname(ent, "info_target")) != null)
    {
        local tn = ""
        try { tn = ent.GetName() } catch (e) { tn = "" }
        if (tn == null) tn = ""
        if (!_StartsWith(tn, g_weaponSpawnerPrefix))
            continue

        foundTargets.append(ent)
    }

    local spawned = 0
    foreach (t in foundTargets)
    {
        local tn = t.GetName()
        local weaponKey = tn.slice(g_weaponSpawnerPrefix.len()).tostring()

        if (!(weaponKey in g_weaponKeyToDef))
        {
            printl("[tf2c_weaponspawners] WARN: No weapon def for key '" + weaponKey + "' (target '" + tn + "')")
            continue
        }

        local def = g_weaponKeyToDef[weaponKey]

        local worldModel = null
        if ("modelWorld" in def) worldModel = def.modelWorld
        else if ("worldModel" in def) worldModel = def.worldModel

        if (worldModel == null)
        {
            printl("[tf2c_weaponspawners] WARN: weapon '" + weaponKey + "' has no world model.")
            continue
        }

        local origin = t.GetOrigin()
        local angles = t.GetAngles()

        local prop = __CreateSpawnerProp(origin, angles, worldModel, tn)
        local trig = __CreateSpawnerTrigger(origin, tn)
        if (prop == null || trig == null)
        {
            if (prop != null) try { prop.Kill() } catch (e2) { }
            if (trig != null) try { trig.Kill() } catch (e3) { }
            continue
        }

        local sc = trig.GetScriptScope()
        sc.spawnerKey <- weaponKey
        sc.spawnerName <- tn

        sc.OnStartTouch <- function(toucher)
        {
            if (!g_weaponSpawnerTouchPickup)
                return

            if (toucher == null || !toucher.IsValid())
                return
            if (!("IsPlayer" in toucher) || !toucher.IsPlayer())
                return

            __OnPlayerTouchedSpawner(toucher, spawnerName, spawnerKey)
        }

        g_spawnedSpawners.append({ key = weaponKey, targetEnt = t, propEnt = prop, trigEnt = trig, nextTime = 0.0 })
        spawned++
    }

    printl(format("[tf2c_weaponspawners] found %d weaponspawner_ targets; spawned %d", foundTargets.len(), spawned))

    if (spawned > 0)
    {
        local thinkEnt = g_spawnedSpawners[0].propEnt
        if (thinkEnt != null && thinkEnt.IsValid())
        {
            try { AddThinkToEnt(thinkEnt, "__SpawnerThink") } catch (e) { }
        }
    }
}

// -------------------------------
// Lifecycle
// -------------------------------
function Activate()
{
    // Delay so all info_targets exist.
    local host = null
    try { host = Entities.FindByClassname(null, "logic_vscript") } catch (e) { host = null }

    if (host != null && host.IsValid())
    {
        EntFireByHandle(host, "RunScriptCode", "__SpawnSpawnersFromInfoTargets()", 0.10, null, null)
    }
    else
    {
        __SpawnSpawnersFromInfoTargets()
    }
}

function main()
{
    Activate()
}