// tf2c_b4dm_music.nut
// TF2C DM Music Controller (server-side)
// - Start WAIT once at least one real-team player (team >= 2) exists.
// - Switch to MAIN exactly 30 seconds after WAIT first starts.
// - Ignore round start events entirely.
// - Late joiners: on player_team/player_spawn, play current track for that player.
// - Stop on round end/win/stalemate/game_over.
//
// TF2C notes:
// - StopSoundOn signature: StopSoundOn(soundName, entity)
// - RunScriptCode executes in root scope: anything it touches must be in root (::).

if (!IsServer())
    return;

// ---------------- Root constants (RunScriptCode-safe) ----------------
::B4DM_SOUND_WAIT <- "Deathmatch.B4DM_AFG_Wait";
::B4DM_SOUND_MAIN <- "Deathmatch.B4DM_AFG";
::B4DM_WAIT_TO_MAIN_SECONDS <- 30.0;

// ---------------- Persistent root state (do NOT reset on re-exec) ----------------
if (!("B4DM_Music" in getroottable()))
{
    ::B4DM_Music <-
    {
        state = "none",            // "none" | "wait" | "main"
        waitStartToken = 0,
        waitStartArmed = false,
        eventsRegistered = false
    };
}

// ---------------- Small helpers ----------------
function B4DM_ForEachPlayer(funcCallback)
{
    local playerEnt = null;
    while ((playerEnt = Entities.FindByClassname(playerEnt, "player")) != null)
    {
        if (playerEnt == null) continue;
        funcCallback(playerEnt);
    }
}

function B4DM_IsRealTeamPlayer(playerEnt)
{
    return (playerEnt != null && playerEnt.GetTeam() >= 2);
}

function B4DM_CountRealTeamPlayers()
{
    local count = 0;
    B4DM_ForEachPlayer(function(p) {
        if (B4DM_IsRealTeamPlayer(p)) count++;
    });
    return count;
}

function B4DM_StopOnPlayer(playerEnt)
{
    // TF2C: StopSoundOn(soundName, entity)
    StopSoundOn(::B4DM_SOUND_WAIT, playerEnt);
    StopSoundOn(::B4DM_SOUND_MAIN, playerEnt);
}

function B4DM_PlayOnPlayer(playerEnt, soundName)
{
    B4DM_StopOnPlayer(playerEnt);

    local params =
    {
        sound_name = soundName,
        entity = playerEnt,
        channel = CHAN_STATIC,
        volume = 1.0,
        pitch = 100,
        soundlevel = SNDLVL_NONE
    };

    EmitSoundEx(params);
}

function B4DM_PlayCurrentForPlayer(playerEnt)
{
    if (!B4DM_IsRealTeamPlayer(playerEnt)) return;

    if (::B4DM_Music.state == "wait")
        B4DM_PlayOnPlayer(playerEnt, ::B4DM_SOUND_WAIT);
    else if (::B4DM_Music.state == "main")
        B4DM_PlayOnPlayer(playerEnt, ::B4DM_SOUND_MAIN);
}

function B4DM_StopAll()
{
    B4DM_ForEachPlayer(function(p) { B4DM_StopOnPlayer(p); });

    ::B4DM_Music.state = "none";
    ::B4DM_Music.waitStartArmed = false;
    ::B4DM_Music.waitStartToken++; // invalidate any pending fallback
}

function B4DM_PlayWaitForAllRealTeamPlayers()
{
    B4DM_ForEachPlayer(function(p) {
        if (B4DM_IsRealTeamPlayer(p))
            B4DM_PlayOnPlayer(p, ::B4DM_SOUND_WAIT);
    });

    ::B4DM_Music.state = "wait";
    B4DM_ArmWaitToMainFallback();
}

function B4DM_PlayMainForAllRealTeamPlayers()
{
    B4DM_ForEachPlayer(function(p) {
        if (B4DM_IsRealTeamPlayer(p))
            B4DM_PlayOnPlayer(p, ::B4DM_SOUND_MAIN);
    });

    ::B4DM_Music.state = "main";
    ::B4DM_Music.waitStartArmed = false;
    ::B4DM_Music.waitStartToken++; // invalidate pending fallback
}

function B4DM_Evaluate()
{
    // No real-team players -> stop.
    if (B4DM_CountRealTeamPlayers() < 1)
    {
        if (::B4DM_Music.state != "none")
            B4DM_StopAll();
        return;
    }

    // First time anyone is on a real team -> start WAIT.
    if (::B4DM_Music.state == "none")
    {
        B4DM_PlayWaitForAllRealTeamPlayers();
        return;
    }

    // If still waiting, ensure the 30s fallback is armed.
    if (::B4DM_Music.state == "wait")
        B4DM_ArmWaitToMainFallback();
}

// ---------------- Root-safe fallback scheduling ----------------
function B4DM_ArmWaitToMainFallback()
{
    if (::B4DM_Music.waitStartArmed) return;
    if (::B4DM_Music.state != "wait") return;

    ::B4DM_Music.waitStartArmed = true;
    ::B4DM_Music.waitStartToken++;

    local token = ::B4DM_Music.waitStartToken;

    local worldEnt = Entities.FindByClassname(null, "worldspawn");
    if (worldEnt == null) return;

    local code = "::B4DM_WaitToMainFallback(" + token + ")";
    EntFireByHandle(worldEnt, "RunScriptCode", code, ::B4DM_WAIT_TO_MAIN_SECONDS, null, null);
}

// Must be root for RunScriptCode. Root-safe: does not call non-root helpers.
::B4DM_WaitToMainFallback <- function(token)
{
    if (token != ::B4DM_Music.waitStartToken) return;
    if (::B4DM_Music.state != "wait") return;

    // Only switch if at least one real-team player still exists.
    local realTeamCount = 0;
    local playerEnt = null;
    while ((playerEnt = Entities.FindByClassname(playerEnt, "player")) != null)
    {
        if (playerEnt != null && playerEnt.GetTeam() >= 2)
            realTeamCount++;
    }

    if (realTeamCount < 1)
        return;

    // Switch everyone on real teams to MAIN (root-safe)
    playerEnt = null;
    while ((playerEnt = Entities.FindByClassname(playerEnt, "player")) != null)
    {
        if (playerEnt == null) continue;
        if (playerEnt.GetTeam() < 2) continue;

        StopSoundOn(::B4DM_SOUND_WAIT, playerEnt);
        StopSoundOn(::B4DM_SOUND_MAIN, playerEnt);

        local params =
        {
            sound_name = ::B4DM_SOUND_MAIN,
            entity = playerEnt,
            channel = CHAN_STATIC,
            volume = 1.0,
            pitch = 100,
            soundlevel = SNDLVL_NONE
        };

        EmitSoundEx(params);
    }

    ::B4DM_Music.state = "main";
    ::B4DM_Music.waitStartArmed = false;
    ::B4DM_Music.waitStartToken++; // invalidate any other pending fallback
};

// ---------------- Event callbacks ----------------
function B4DM_OnPlayerSpawn(params)
{
    B4DM_Evaluate();

    // Late joiners: play current track for that spawning player
    if (!("userid" in params)) return;

    local playerEnt = null;
    try { playerEnt = GetPlayerFromUserID(params.userid); } catch (e) { playerEnt = null; }
    B4DM_PlayCurrentForPlayer(playerEnt);
}

function B4DM_OnPlayerTeam(params)
{
    B4DM_Evaluate();

    // Late joiners / team switches: play current track if they joined a real team
    if (!("userid" in params)) return;

    local playerEnt = null;
    try { playerEnt = GetPlayerFromUserID(params.userid); } catch (e) { playerEnt = null; }
    B4DM_PlayCurrentForPlayer(playerEnt);
}

function B4DM_OnPlayerDisconnect(params)
{
    B4DM_Evaluate();
}

function B4DM_OnRoundEnd(params)
{
    // Keep your previous “stop at end” behavior.
    B4DM_StopAll();
}

// ---------------- Init (idempotent) ----------------
function B4DM_Init()
{
    // If the file is re-executed by the game, do not reset state or re-register events.
    if (::B4DM_Music.eventsRegistered)
    {
        // Resync: ensure current track is applied to real-team players.
        B4DM_Evaluate();
        B4DM_ForEachPlayer(function(p) { B4DM_PlayCurrentForPlayer(p); });
        return;
    }

    ::B4DM_Music.eventsRegistered = true;

    // Intentionally NOT listening to teamplay_round_start / waiting_begins.
    ListenToGameEvent("player_spawn",      "B4DM_OnPlayerSpawn",      "");
    ListenToGameEvent("player_team",       "B4DM_OnPlayerTeam",       "");
    ListenToGameEvent("player_disconnect", "B4DM_OnPlayerDisconnect", "");

    ListenToGameEvent("teamplay_round_win",       "B4DM_OnRoundEnd", "");
    ListenToGameEvent("teamplay_round_stalemate", "B4DM_OnRoundEnd", "");
    ListenToGameEvent("teamplay_game_over",       "B4DM_OnRoundEnd", "");

    B4DM_Evaluate();
}

B4DM_Init();