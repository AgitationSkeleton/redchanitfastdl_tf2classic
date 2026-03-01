// tf2c_respawn_particles.nut
// Respawn particle effects from particles/respawn.pcf (must be loaded via particles_manifest)
// Author: ChatGPT

// Particle system names present in respawn.pcf
::g_respawnParticles <- [
	"dm_respawn_01","dm_respawn_02","dm_respawn_03","dm_respawn_04","dm_respawn_05","dm_respawn_06","dm_respawn_07","dm_respawn_08",
	"dm_respawn_09","dm_respawn_10","dm_respawn_11","dm_respawn_12","dm_respawn_13","dm_respawn_14","dm_respawn_15","dm_respawn_16",
	"dm_respawn_17","dm_respawn_18","dm_respawn_19","dm_respawn_20","dm_respawn_21","dm_respawn_22","dm_respawn_23","dm_respawn_24",
	"dm_respawn_25","dm_respawn_26","dm_respawn_27","dm_respawn_28","dm_respawn_29","dm_respawn_30","dm_respawn_31","dm_respawn_32",
	"dm_respawn_34","dm_respawn_34","dm_respawn_35","dm_respawn_36","dm_respawn_37","dm_respawn_38","dm_respawn_39","dm_respawn_40",
	"dm_respawn_41","dm_respawn_42"
];

// Throttle: prevent multiple spawns from spamming particles.
// TF2C sometimes fires player_spawn multiple times during forced class/model enforcement.
::g_respawnFxLastTimeByUserId <- {};
::g_respawnFxLastEntByUserId <- {};
const RESPAWN_FX_COOLDOWN = 0.75; // seconds

function RespawnParticles_GetRandom()
{
	if (!("g_respawnParticles" in getroottable()) || ::g_respawnParticles.len() <= 0)
		return null;

	local idx = 0;
	try { idx = RandomInt(0, ::g_respawnParticles.len() - 1); } catch (e) { idx = 0; }
	return ::g_respawnParticles[idx];
}

function RespawnParticles_PrecacheAll()
{
	if (!("g_respawnParticles" in getroottable()))
		return;

	foreach (pname in ::g_respawnParticles)
	{
		try
		{
			if ("PrecacheParticleSystem" in getroottable())
				PrecacheParticleSystem(pname);
			else if ("PrecacheParticle" in getroottable())
				PrecacheParticle(pname);
		}
		catch (e) {}
	}
}

// Play one random respawn particle at the player's origin, throttled to 1 per spawn burst.
function RespawnParticles_PlayRandomOnPlayer(player)
{
	if (player == null || !player.IsValid() || !player.IsPlayer())
		return false;

	local team = 0;
	try { team = player.GetTeam(); } catch (eT) { team = 0; }
	if (team < 2)
		return false;

	local userId = 0;
	try { userId = player.GetUserID(); } catch (eU) { userId = 0; }
	if (userId <= 0)
		return false;

	local now = 0.0;
	try { now = Time(); } catch (eTime) { now = 0.0; }

	// Cooldown
	if (userId in ::g_respawnFxLastTimeByUserId)
	{
		local lastTime = ::g_respawnFxLastTimeByUserId[userId];
		if ((now - lastTime) < RESPAWN_FX_COOLDOWN)
			return false;
	}

	::g_respawnFxLastTimeByUserId[userId] <- now;

	// Kill previous FX entity if it still exists
	if (userId in ::g_respawnFxLastEntByUserId)
	{
		local prev = ::g_respawnFxLastEntByUserId[userId];
		try { if (prev != null && prev.IsValid()) EntFireByHandle(prev, "Kill", "", 0.0, null, null); } catch (eK) {}
	}

	local pname = RespawnParticles_GetRandom();
	if (pname == null)
		return false;

	local origin = Vector(0,0,0);
	try { origin = player.GetOrigin(); } catch (eO) {}

	local fx = null;
	try
	{
		fx = SpawnEntityFromTable("info_particle_system",
		{
			effect_name = pname,
			start_active = "0"
		});
	}
	catch (e2) { fx = null; }

	if (fx == null)
		return false;

	::g_respawnFxLastEntByUserId[userId] <- fx;

	try { fx.SetAbsOrigin(origin); } catch (e3) {}

	// Start immediately, then kill shortly after (keep short to avoid lingering FX)
	try { EntFireByHandle(fx, "Start", "", 0.0, null, null); } catch (e4) {}
	try { EntFireByHandle(fx, "Kill",  "", 2.0, null, null); } catch (e5) {}

	return true;
}
