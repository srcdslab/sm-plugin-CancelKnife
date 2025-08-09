#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <multicolors>
#include <zombiereloaded>
#include <KnockbackRestrict>

#undef REQUIRE_PLUGIN
#tryinclude <knifemode>
#define REQUIRE_PLUGIN

#define WEAPONS_MAX_LENGTH 32

enum struct CKnifeRevert {
	int humanId;
	float pos[3];
	char humanName[32];
}

enum struct CKnife {
	int attackerUserId;
	int victimUserId;
	char attackerName[32];
	char victimName[32];
	float victimOrigin[3];
	int time;
	ArrayList deadPeople;
}

enum WeaponAmmoGrenadeType {
	GrenadeType_HEGrenade           = 11,   /** CSS - HEGrenade slot */
	GrenadeType_Flashbang           = 12,   /** CSS - Flashbang slot. */
	GrenadeType_Smokegrenade        = 13,   /** CSS - Smokegrenade slot. */
};

Handle g_hCheckAllKnivesTimer;

ArrayList g_arAllKnives;

ConVar g_cvKnifeTime;
ConVar g_cvSlayKnifer;
ConVar g_cvKbanKnifer;
ConVar g_cvKbanReason;
ConVar g_cvPrintMessageType;

bool g_bKnifeModeEnabled = false;
bool g_bMotherZombie = false;

enum struct PlayerData {
	char weaponPrimaryStr[WEAPONS_MAX_LENGTH];
	char weaponSecondaryStr[WEAPONS_MAX_LENGTH];

	int time;
	int knifer;
	int health;
	int helmet;
	int armor;
	int nvg;
	int hegrenade;
	int flash;
	int smoke;

	int weaponSecondary;
	int infectDamage;

	void Reset() {
		this.weaponPrimaryStr[0] = '\0'; this.weaponSecondaryStr[0] = '\0';
		this.time = 0; this.knifer = 0; this.health = 0;
		this.helmet = 0; this.armor = 0; this.nvg = 0; this.hegrenade = 0; this.flash = 0; this.smoke = 0;
		this.weaponSecondary = -1;
		this.infectDamage = 0;
	}
}

PlayerData g_PlayerData[MAXPLAYERS + 1];

public Plugin myinfo = {
	name		= "Cancel Knife",
	author		= "Dolly, .Rushaway",
	description	= "Allows admins to cancel the knife and revert all things that happened caused by that knife",
	version		= "1.6.2",
	url			= "https://github.com/srcdslab/sm-plugin-CancelKnife"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("CancelKnife");
	return APLRes_Success;
}

public void OnPluginStart() {
	RegAdminCmd("sm_cknife", Command_CKnife, ADMFLAG_KICK, "Open the menu to cancel a knife action");
	RegAdminCmd("sm_cancelknife", Command_CKnife, ADMFLAG_KICK, "Open the menu to cancel a knife action");

	g_arAllKnives = new ArrayList(ByteCountToCells(128));

	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
	HookEvent("round_start", Event_RoundStart);

	CSetPrefix("{orchid}[Cancel Knife]{default}");

	g_cvKnifeTime = CreateConVar("sm_cknife_time", "15", "How many seconds to allow the admin to target the knifer after the incident?");
	g_cvSlayKnifer = CreateConVar("sm_cknife_slay_knifer", "1", "Should we slay the knifer after canceling the knife?");
	g_cvKbanKnifer = CreateConVar("sm_cknife_kban_knifer", "1", "Open kban menu after canceling the knife?");
	g_cvKbanReason = CreateConVar("sm_cknife_kban_reason", "Knifing (Admin reverting knife actions)", "Kban Reason");
	g_cvPrintMessageType = CreateConVar("sm_cknife_print_message_type", "1", "Print Message type [0 = All Players | 1 = Admins only");

	AutoExecConfig();

	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i)) {
			continue;
		}

		OnClientPutInServer(i);
	}
}

public void OnMapStart() {
	delete g_hCheckAllKnivesTimer;
	g_hCheckAllKnivesTimer = CreateTimer(60.0, CheckAllKnives_Timer, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public void OnMapEnd() {
	g_hCheckAllKnivesTimer = null;

	for (int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));
		delete knife.deadPeople;
	}

	g_arAllKnives.Clear();
}

public void OnClientPutInServer(int client) {
	g_PlayerData[client].Reset();
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

Action CheckAllKnives_Timer(Handle timer) {
	if (g_bKnifeModeEnabled) {
		g_hCheckAllKnivesTimer = null;
		return Plugin_Stop;
	}

	// not supposed to happen
	if (g_arAllKnives == null) {
		return Plugin_Handled;
	}

	/* We want to remove any knife that is expired */
	int knivesCount = g_arAllKnives.Length;
	if (!knivesCount) {
		return Plugin_Handled;
	}

	for (int i = 0; i < knivesCount; i++) {
		// Just incase a knife was deleted while this timer is being called
		if (knivesCount != g_arAllKnives.Length) {
			return Plugin_Handled;
		}

		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));
		if (knife.time < GetTime()) {
			ClearData(knife);
			delete knife.deadPeople;
			g_arAllKnives.Erase(i);
		}
	}

	return Plugin_Continue;
}

Action Command_CKnife(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}

	if (!g_bMotherZombie) {
		CReplyToCommand(client, "Idiot, how come would there be knife actions if no zombie got infected yet?");
		return Plugin_Handled;
	}

	if (g_arAllKnives == null || g_arAllKnives.Length == 0) {
		CReplyToCommand(client, "No active knives found!");
		return Plugin_Handled;
	}

	/* Check if admin typed the command only with arguments, we will open a menu */
	if (args < 1) {
		OpenCKnifeMenu(client);
		return Plugin_Handled;
	}

	char targetName[32];
	GetCmdArg(1, targetName, sizeof(targetName));

	int count = GetKnivesCount(targetName);
	if (count < 1) {
		CReplyToCommand(client, "No Active Knives were found with this name.");
		return Plugin_Handled;
	}

	OpenCKnifeMenu(client, targetName);
	return Plugin_Handled;
}

void OpenCKnifeMenu(int client, char[] targetName = "") {
	Menu menu = new Menu(Menu_Callback);
	menu.SetTitle("[Cancel Knife] Active Knives!");

	bool found = false;
	for (int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));

		if (knife.time < GetTime()) {
			continue;
		}

		found = true;
		char itemTitle[120];
		FormatEx(itemTitle, sizeof(itemTitle), "[Expire in: %ds] Knifer: %s | Zombie: %s", knife.time - GetTime(), knife.attackerName, knife.victimName);

		char itemInfo[8];
		IntToString(knife.attackerUserId, itemInfo, sizeof(itemInfo));

		if (targetName[0]) {
			if (StrContains(knife.attackerName, targetName, false) != -1 || StrContains(knife.victimName, targetName, false) != -1) {
				menu.AddItem(itemInfo, itemTitle);
			}
		} else {
			menu.AddItem(itemInfo, itemTitle);
		}
	}

	if (!found) {
		CPrintToChat(client, "No active knives found!");
	}

	menu.ExitButton = true;
	menu.Display(client, g_cvKnifeTime.IntValue);
}

int Menu_Callback(Menu menu, MenuAction action, int param1, int param2) {
	switch(action) {
		case MenuAction_End: {
			delete menu;
		}

		case MenuAction_Select: {
			if (!g_bMotherZombie) {
				CPrintToChat(param1, "Idiot, how come would there be knife actions if no zombie got infected yet?");
				return 0;
			}

			char info[8];
			menu.GetItem(param2, info, sizeof(info));
			int kniferUserid = StringToInt(info);

			RevertEverything(param1, kniferUserid);
			Command_CKnife(param1, 0);
		}
	}

	return 0;
}

void RevertEverything(int admin, int userid) {
	bool found = false;
	char message[256];

	for (int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));
		if (knife.attackerUserId != userid) {
			continue;
		}

		found = true;

		FormatEx(message, sizeof(message), "Canceling the Knife Action.. [{blue}%s {default}X {red}%s{default}]", knife.attackerName, knife.victimName);
		CPrintToChatAdmins(message);

		int knifer = GetClientOfUserId(userid);
		if (g_cvSlayKnifer.BoolValue) {
			if (knifer && IsPlayerAlive(knifer)) {
				ForcePlayerSuicide(knifer);
				FormatEx(message, sizeof(message), "{red}%s {default}has been slayed for knifing {olive}%s{default}.", knife.attackerName, knife.victimName);
				PrintCKnifeMessage(message);
			} 
		}

		if (g_cvKbanKnifer.BoolValue) {
			if (knifer && IsClientInGame(knifer) && !KR_ClientStatus(knifer)) {
				KR_DisplayLengthsMenu(admin, knifer, KR_Menu_OnLengthClick);
			}
		}

		int zombie = GetClientOfUserId(knife.victimUserId);
		if (zombie && IsPlayerAlive(zombie)) {
			TeleportEntity(zombie, knife.victimOrigin);
		} else {
			LogAction(admin, -1, "[CancelKnife] \"%L\" tried to revert the knife made by %s but it failed. %s is not alive.", admin, knife.attackerName, knife.victimName);
		}

		for (int j = 0; j < knife.deadPeople.Length; j++) {
			CKnifeRevert knifeRevert;
			knife.deadPeople.GetArray(j, knifeRevert, sizeof(knifeRevert));
			int human = GetClientOfUserId(knifeRevert.humanId);
			if (human && IsPlayerAlive(human)) {
				TeleportEntity(human, knifeRevert.pos);
				ZR_HumanClient(human);

				RestoreHealthAndArmor(human);

				// Restore Equiements + Weapons
				SetEntProp(human, Prop_Send, "m_bHasNightVision", g_PlayerData[human].nvg);
				GivePlayerItem(human, g_PlayerData[human].weaponPrimaryStr);
				int secondaryWeapon;
				if ((secondaryWeapon = EntRefToEntIndex(g_PlayerData[human].weaponSecondary)) > 0 && IsValidEntity(secondaryWeapon)) {
					EquipPlayerWeapon(human, secondaryWeapon);
				} else {
					GivePlayerItem(human, g_PlayerData[human].weaponSecondaryStr);
				}

				// Nades
				GiveGrenadesToClient(human, g_PlayerData[human].hegrenade, GrenadeType_HEGrenade);
				GiveGrenadesToClient(human, g_PlayerData[human].flash, GrenadeType_Flashbang);
				GiveGrenadesToClient(human, g_PlayerData[human].smoke, GrenadeType_Smokegrenade);

				FormatEx(message, sizeof(message), "The knife has been reverted. {olive}%N {default}has been revived as a {green}Human!", human);
				PrintCKnifeMessage(message);
			} else {
				FormatEx(message, sizeof(message), "Can't switch back {olive}%s {default}as human. The player is not alive.", knifeRevert.humanName);
				CPrintToChatAdmins(message);
			}
		}

		LogAction(admin, -1, "[CancelKnife] \"%L\" has reverted the knife made by %s on %s.", admin, knife.attackerName, knife.victimName);
		ClearData(knife);
		delete knife.deadPeople;
		g_arAllKnives.Erase(i);
		break;
	}

	if (!found) {
		CPrintToChat(admin, "You want to deal with this knife ? F*ck you, be faster next time.");
	}
}

/* For the KBan Lengths Menu */
void KR_Menu_OnLengthClick(int admin, int target, int time) {
	char reason[64];
	g_cvKbanReason.GetString(reason, sizeof(reason));
	KR_BanClient(admin, target, time, reason);
}

void PrintCKnifeMessage(const char[] message) {
	if (g_cvPrintMessageType.IntValue == 0) {
		CPrintToChatAll(message);
	} else {
		CPrintToChatAdmins(message);
	}
}

void CPrintToChatAdmins(const char[] message) {
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i) || IsFakeClient(i) || !CheckCommandAccess(i, "sm_cknife", ADMFLAG_KICK)) {
			continue;
		}
		CPrintToChat(i, message);
	}
}

int GetKnivesCount(const char[] targetName) {
	int count;
	for (int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));
		if (StrContains(knife.attackerName, targetName, false) != -1 || StrContains(knife.victimName, targetName, false) != -1) {
			count++;
		}
	}

	return count;
}

Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	if (g_bKnifeModeEnabled) {
		return Plugin_Continue;
	}

	if (!g_bMotherZombie) {
		return Plugin_Continue;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if (victim < 1 || victim > MaxClients || !IsClientInGame(victim) || attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker)) {
		return Plugin_Continue;
	}

	if(!(GetClientTeam(victim) == CS_TEAM_T && GetClientTeam(attacker) == CS_TEAM_CT)) {
		return Plugin_Continue;
	}

	char weapon[WEAPONS_MAX_LENGTH];
	event.GetString("weapon", weapon, sizeof(weapon));
	if (strcmp(weapon, "knife", false) != 0) {
		return Plugin_Continue;
	}

	int damage = event.GetInt("dmg_health");
	if (damage < 35.0) {
		return Plugin_Continue;
	}

	// due to the new zombiereloaded knockback natives, damage will still be the same, only knockback will be changed
	if (KR_ClientStatus(attacker)) {
		return Plugin_Continue;
	}

	if (g_PlayerData[victim].time != 0 && g_PlayerData[victim].time < GetTime()) {
		return Plugin_Continue;
	}

	/* So knife happened now, we want to save the data of the knife */
	CKnife knife;
	GetClientAbsOrigin(victim, knife.victimOrigin);

	GetClientName(attacker, knife.attackerName, sizeof(CKnife::attackerName));
	GetClientName(victim, knife.victimName, sizeof(CKnife::victimName));
	knife.attackerUserId = event.GetInt("attacker");
	knife.victimUserId = event.GetInt("userid");

	knife.time = GetTime() + g_cvKnifeTime.IntValue;
	g_PlayerData[victim].time = knife.time;
	g_PlayerData[victim].knifer = knife.attackerUserId;

	for (int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife tempKnife;
		g_arAllKnives.GetArray(i, tempKnife, sizeof(tempKnife));

		// if cknife action existed before with the same knifer and zombie
		if (tempKnife.attackerUserId == knife.attackerUserId && tempKnife.victimUserId == knife.victimUserId) {
			tempKnife.time = knife.time;
			g_arAllKnives.SetArray(i, tempKnife, sizeof(tempKnife));
			return Plugin_Continue;
		}
	}

	char message[256];
	FormatEx(message, sizeof(message), "New action available. ({blue}%s {default}X {red}%s{default})", knife.attackerName, knife.victimName);
	CPrintToChatAdmins(message);

	knife.deadPeople = new ArrayList(ByteCountToCells(64));
	g_arAllKnives.PushArray(knife);
	return Plugin_Continue;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	for (int i = 1; i <= MaxClients; i++) {
		g_PlayerData[i].Reset();
	}

	g_bMotherZombie = false;
}

Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	if (!g_bMotherZombie) {
		return Plugin_Continue;
	}

	if (victim <= 0 || victim > MaxClients || attacker <= 0 || attacker > MaxClients) {
		return Plugin_Continue;
	}

	if (!(IsPlayerAlive(attacker) && IsPlayerAlive(victim) && ZR_IsClientZombie(attacker) && ZR_IsClientHuman(victim))) {
		return Plugin_Continue;
	}

	g_PlayerData[victim].health = GetClientHealth(victim);
	g_PlayerData[victim].infectDamage = RoundToNearest(damage);
	return Plugin_Continue;
}

public void ZR_OnClientInfected(int client, int attacker, bool motherInfect, bool respawnOverride, bool respawn) {
	if (motherInfect) {
		g_bMotherZombie = true;
		return;
	}

	if (attacker <= 0 || attacker > MaxClients) {
		return;
	}

	if (g_PlayerData[attacker].time < GetTime()) {
		return;
	}

	if (client == g_PlayerData[attacker].knifer) {
		return;
	}

	g_PlayerData[client].time = g_PlayerData[attacker].time;
	g_PlayerData[client].knifer = g_PlayerData[attacker].knifer;

	int humanId = GetClientUserId(client); 

	float humanOrigin[3];
	GetClientAbsOrigin(client, humanOrigin);

	for (int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));

		if (knife.attackerUserId == g_PlayerData[attacker].knifer) {
			CKnifeRevert knifeRevert;
			knifeRevert.humanId = humanId;
			knifeRevert.pos[0] = humanOrigin[0];
			knifeRevert.pos[1] = humanOrigin[1];
			knifeRevert.pos[2] = humanOrigin[2];
			GetClientName(client, knifeRevert.humanName, sizeof(CKnifeRevert::humanName));
			SaveClientData(client);
			knife.deadPeople.PushArray(knifeRevert);
		}
	}
}

void ClearData(CKnife knife) {
	int zombie = GetClientOfUserId(knife.victimUserId);
	if (zombie) {
		g_PlayerData[zombie].Reset();
	}

	for (int i = 0; i < knife.deadPeople.Length; i++) {
		CKnifeRevert revert;
		knife.deadPeople.GetArray(i, revert, sizeof(revert));
		int human = GetClientOfUserId(revert.humanId);
		if (human) {
			g_PlayerData[human].Reset();
		}
	}
}

stock void RestoreHealthAndArmor(int human) {
	// Restore Health + Armor value
	if (g_PlayerData[human].health >= 1) {
		int health = g_PlayerData[human].health - g_PlayerData[human].infectDamage;
		if (health <= 0) {
			health = 1;
		} else if (health > 100) {
			health = 100;
		}

		//PrintToChatAll("Stored health: %d \n Infect damage: %d \n New health: %d", g_PlayerData[human].health, g_PlayerData[human].infectDamage, health);
		SetEntProp(human, Prop_Send, "m_iHealth", health);
	} else {
		SetEntProp(human, Prop_Send, "m_iHealth", 100); // <1 = Create non dead player..
	}

	SetEntProp(human, Prop_Send, "m_ArmorValue", g_PlayerData[human].armor, 1);
	SetEntProp(human, Prop_Send, "m_bHasHelmet", g_PlayerData[human].helmet, 1);
}

stock void SaveClientData(int victim)
{
	g_PlayerData[victim].armor = GetEntProp(victim, Prop_Send, "m_ArmorValue");
	g_PlayerData[victim].helmet = GetEntProp(victim, Prop_Send, "m_bHasHelmet");
	g_PlayerData[victim].nvg = GetEntProp(victim, Prop_Send, "m_bHasNightVision");

	g_PlayerData[victim].hegrenade = GetEntProp(victim, Prop_Data, "m_iAmmo", _, view_as<int>(GrenadeType_HEGrenade));
	g_PlayerData[victim].flash = GetEntProp(victim, Prop_Data, "m_iAmmo", _, view_as<int>(GrenadeType_Flashbang));
	g_PlayerData[victim].smoke = GetEntProp(victim, Prop_Data, "m_iAmmo", _, view_as<int>(GrenadeType_Smokegrenade));

	GetClientMainWeapons(victim);
}

stock void GetClientMainWeapons(int client) {
	// we only want to get primary and secondary weapons...
	char className[WEAPONS_MAX_LENGTH];

	int primary = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
	if (primary != -1) {
		GetEntityClassname(primary, className, sizeof(className));
		g_PlayerData[client].weaponPrimaryStr = className;
	}

	int secondary = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	if (secondary != -1) {
		GetEntityClassname(secondary, className, sizeof(className));
		g_PlayerData[client].weaponSecondaryStr = className;
	}
}

stock void GiveGrenadesToClient(int client, int iAmount, WeaponAmmoGrenadeType type)
{
	int iToolsAmmo = FindSendPropInfo("CBasePlayer", "m_iAmmo");
	if (iToolsAmmo != -1)
	{
		int iGrenadeCount = GetEntData(client, iToolsAmmo + (view_as<int>(type) * 4));
		SetEntData(client, iToolsAmmo + (view_as<int>(type) * 4), iGrenadeCount + iAmount, _, true);
	}
}

#if defined _KnifeMode_Included
public void KnifeMode_OnToggle(bool bEnabled)
{
	g_bKnifeModeEnabled = bEnabled;
}
#endif
