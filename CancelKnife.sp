#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <multicolors>
#include <zombiereloaded>
#include <KnockbackRestrict>

#define WEAPONS_MAX_LENGTH 32
#define WEAPONS_SLOTS_MAX 5

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

enum WeaponAmmoGrenadeType
{
	GrenadeType_Invalid             = -1,   /** Invalid grenade slot. */
	GrenadeType_HEGrenade           = 11,   /** CSS - HEGrenade slot */
	GrenadeType_Flashbang           = 12,   /** CSS - Flashbang slot. */
	GrenadeType_Smokegrenade        = 13,   /** CSS - Smokegrenade slot. */
	GrenadeType_HEGrenadeCSGO       = 14,   /** CSGO - HEGrenade slot. */
	GrenadeType_FlashbangCSGO       = 15,   /** CSGO - Flashbang slot. */
	GrenadeType_SmokegrenadeCSGO    = 16,   /** CSGO - Smokegrenade slot. */
	GrenadeType_Incendiary          = 17,   /** CSGO - Incendiary and Molotov slot. */
	GrenadeType_Decoy               = 18,   /** CSGO - Decoy slot. */
	GrenadeType_Tactical            = 22,   /** CSGO - Tactical slot. */
}

enum WeaponsSlot
{
	Slot_Invalid        = -1,   /** Invalid weapon (slot). */
	Slot_Primary        = 0,    /** Primary weapon slot. */
	Slot_Secondary      = 1,    /** Secondary weapon slot. */
	Slot_Melee          = 2,    /** Melee (knife) weapon slot. */
	Slot_Projectile     = 3,    /** Projectile (grenades, flashbangs, etc) weapon slot. */
	Slot_Explosive      = 4,    /** Explosive (c4) weapon slot. */
	Slot_NVGs           = 5,    /** NVGs (fake) equipment slot. */
	Slot_DangerZone     = 11,   /** Dangerzone equipment slot. (CSGO only) */
	Slot_MAXSIZE
}

Handle g_hCheckAllKnivesTimer;

ArrayList g_arAllKnives;

ConVar g_cvKnifeTime;
ConVar g_cvSlayKnifer;
ConVar g_cvKbanKnifer;
ConVar g_cvKbanTime;
ConVar g_cvKbanReason;
ConVar g_cvPrintMessageType;

bool g_bIsCSGO = false;
bool g_bKnifeModeEnabled = false;
bool g_bMotherZombie = false;

char g_sWeapon_Primary[MAXPLAYERS + 1][WEAPONS_MAX_LENGTH];
char g_sWeapon_Secondary[MAXPLAYERS + 1][WEAPONS_MAX_LENGTH];

int g_iClientTime[MAXPLAYERS + 1];
int g_iClientKnifer[MAXPLAYERS + 1];
int g_iClientHealth[MAXPLAYERS + 1];
int g_iClientHelmet[MAXPLAYERS + 1];
int g_iClientArmor[MAXPLAYERS + 1];
int g_iClientNvg[MAXPLAYERS + 1];
int g_iClientHEGrenade[MAXPLAYERS + 1];
int g_iClientFlashbang[MAXPLAYERS + 1];
int g_iClientSmokegrenade[MAXPLAYERS + 1];
int g_iClientIncendiary[MAXPLAYERS + 1];
int g_iClientDecoy[MAXPLAYERS + 1];
int g_iClientTactial[MAXPLAYERS + 1];
int g_iClientInfectDamage[MAXPLAYERS + 1];


public Plugin myinfo = {
	name		= "Cancel Knife",
	author		= "Dolly, .Rushaway",
	description	= "Allows admins to cancel the knife and revert all things that happened caused by that knife",
	version		= "1.4",
	url			= ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bIsCSGO = (GetEngineVersion() == Engine_CSGO);
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
	g_cvKbanKnifer = CreateConVar("sm_cknife_kban_knifer", "1", "Should we kban the knifer after canceling the knife?");
	g_cvKbanTime = CreateConVar("sm_cknife_kban_duration", "-1", "Kban duration in minutes [-1 = temp | 0 = perm]");
	g_cvKbanReason = CreateConVar("sm_cknife_kban_reason", "Knifing (Admin reverting knife actions)", "Kban Reason");
	g_cvPrintMessageType = CreateConVar("sm_cknife_print_message_type", "1", "Print Message type [0 = All Players | 1 = Admins only");

	AutoExecConfig();
	
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i)) {
			continue;
		}
		
		OnClientPutInServer(i);
	}
}

public void OnAllPluginsLoaded() {
	g_bKnifeModeEnabled = LibraryExists("KnifeMode");
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "KnifeMode")) {
		g_bKnifeModeEnabled = true;
	}

	delete g_hCheckAllKnivesTimer;
	g_hCheckAllKnivesTimer = CreateTimer(1.0, CheckAllKnives_Timer, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public void OnLibraryRemoved(const char[] name) {
	if (StrEqual(name, "KnifeMode")) {
		g_bKnifeModeEnabled = false;
	}
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
	ResetClient(client);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client) {
	ResetClient(client);
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
		if(knivesCount != g_arAllKnives.Length) {
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

	if(!g_bMotherZombie) {
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
	menu.SetTitle("[Knife Cancel] Active Knives!");

	for (int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));

		if (knife.time < GetTime()) {
			continue;
		}

		char itemTitle[120];
		FormatEx(itemTitle, sizeof(itemTitle), "[Expire in: %ds] Knifer: %s | Zombie: %s", knife.time - GetTime(), knife.attackerName, knife.victimName);

		char itemInfo[8];
		IntToString(knife.attackerUserId, itemInfo, sizeof(itemInfo));

		if (targetName[0]) {
			if (StrContains(knife.attackerName, targetName) != -1 || StrContains(knife.victimName, targetName) != -1) {
				menu.AddItem(itemInfo, itemTitle);
			}
		} else {
			menu.AddItem(itemInfo, itemTitle);
		}
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
			if(!g_bMotherZombie) {
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
			if (knifer && IsClientInGame(knifer)) {
				char reason[64];
				g_cvKbanReason.GetString(reason, sizeof(reason));
				KR_BanClient(admin, knifer, g_cvKbanTime.IntValue, reason);
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
				SetEntProp(human, Prop_Send, "m_bHasNightVision", g_iClientNvg[human]);
				GivePlayerItem(human, g_sWeapon_Primary[human]);
				GivePlayerItem(human, g_sWeapon_Secondary[human]);

				// Nades
				GiveGrenadesToClient(human, g_iClientHEGrenade[human], g_bIsCSGO ? GrenadeType_HEGrenadeCSGO : GrenadeType_HEGrenade);
				GiveGrenadesToClient(human, g_iClientFlashbang[human], g_bIsCSGO ? GrenadeType_FlashbangCSGO : GrenadeType_Flashbang);
				GiveGrenadesToClient(human, g_iClientSmokegrenade[human], g_bIsCSGO ? GrenadeType_SmokegrenadeCSGO : GrenadeType_Smokegrenade);
				if (g_bIsCSGO) {
					GiveGrenadesToClient(human, g_iClientIncendiary[human], GrenadeType_Incendiary);
					GiveGrenadesToClient(human, g_iClientDecoy[human], GrenadeType_Decoy);
					GiveGrenadesToClient(human, g_iClientTactial[human], GrenadeType_Tactical);
				}

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

int GetKnivesCount(char[] targetName) {
	int count;
	for (int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));
		if (StrContains(knife.attackerName, targetName) != -1 || StrContains(knife.victimName, targetName) != -1) {
			count++;
		}
	}
	
	return count;
}

Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	if (g_bKnifeModeEnabled) {
		return Plugin_Continue;
	}

	if(!g_bMotherZombie) {
		return Plugin_Continue;
	}
	
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if (victim < 1 || victim > MaxClients || !IsClientInGame(victim) || attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker)) {
		return Plugin_Continue;
	}

	bool isKnife = (GetClientTeam(victim) == CS_TEAM_T && GetClientTeam(attacker) == CS_TEAM_CT);

	if(!isKnife) {
		return Plugin_Continue;
	}
	
	char weapon[WEAPONS_MAX_LENGTH];
	event.GetString("weapon", weapon, sizeof(weapon));
	if (!StrEqual(weapon, "knife")) {
		return Plugin_Continue;
	}

	int damage = event.GetInt("dmg_health");
	if (damage < 35.0) {
		return Plugin_Continue;
	}

	if (g_iClientTime[victim] != 0 && g_iClientTime[victim] < GetTime()) {
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
	g_iClientTime[victim] = knife.time;
	g_iClientKnifer[victim] = knife.attackerUserId;

	for (int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife tempKnife;
		g_arAllKnives.GetArray(i, tempKnife, sizeof(tempKnife));

		if (tempKnife.attackerUserId == knife.attackerUserId && tempKnife.victimUserId == knife.victimUserId) {
			delete tempKnife.deadPeople;
			g_arAllKnives.Erase(i);
			break;
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
		ResetClient(i);
	}
	
	g_bMotherZombie = false;
}

Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	if(!g_bMotherZombie) {
		return Plugin_Continue;
	}
	
	if(victim <= 0 || victim > MaxClients || attacker <= 0 || attacker > MaxClients) {
		return Plugin_Continue;
	}
	
	if(!(ZR_IsClientZombie(attacker) && ZR_IsClientHuman(victim))) {
		return Plugin_Continue;
	}
	
	g_iClientHealth[victim] = GetClientHealth(victim);
	g_iClientInfectDamage[victim] = RoundToNearest(damage);
	return Plugin_Continue;
}

public Action ZR_OnClientInfect(int &client, int &attacker, bool &motherInfect) {
	if (motherInfect) {
		g_bMotherZombie = true;
		return Plugin_Continue;
	}

	if (attacker <= 0 || attacker > MaxClients) {
		return Plugin_Continue;
	}

	if (g_iClientTime[attacker] < GetTime()) {
		return Plugin_Continue;
	}

	if(client == g_iClientKnifer[attacker]) {
		return Plugin_Continue;
	}
	
	g_iClientTime[client] = g_iClientTime[attacker];
	g_iClientKnifer[client] = g_iClientKnifer[attacker];

	int humanId = GetClientUserId(client); 

	float humanOrigin[3];
	GetClientAbsOrigin(client, humanOrigin);

	for (int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));

		if (knife.attackerUserId == g_iClientKnifer[attacker]) {
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
	
	return Plugin_Continue;
}

void ResetClient(int client) {
	g_iClientInfectDamage[client] = 0;
	g_iClientTime[client] = 0;
	g_iClientKnifer[client] = 0;
	g_iClientHealth[client] = 0;
	g_iClientHelmet[client] = 0;
	g_iClientArmor[client] = 0;
	g_iClientNvg[client] = 0;
	g_iClientHEGrenade[client] = 0;
	g_iClientFlashbang[client] = 0;
	g_iClientSmokegrenade[client] = 0;
	FormatEx(g_sWeapon_Primary[client], sizeof(g_sWeapon_Primary[]), "");
	FormatEx(g_sWeapon_Secondary[client], sizeof(g_sWeapon_Secondary[]), "");

	if (g_bIsCSGO) {
		g_iClientIncendiary[client] = 0;
		g_iClientDecoy[client] = 0;
		g_iClientTactial[client] = 0;
	}
}

void ClearData(CKnife knife) {
	int zombie = GetClientOfUserId(knife.victimUserId);
	if (zombie) {
		ResetClient(zombie);
	}

	for (int i = 0; i < knife.deadPeople.Length; i++) {
		CKnifeRevert revert;
		knife.deadPeople.GetArray(i, revert, sizeof(revert));
		int human = GetClientOfUserId(revert.humanId);
		if (human) {
			ResetClient(human);
		}
	}
}

stock void RestoreHealthAndArmor(int human) {
	// Restore Health + Armor value
	if (g_iClientHealth[human] >= 1) {
		int health = g_iClientHealth[human] - g_iClientInfectDamage[human];
		if(health <= 0) {
			health = 1;
		} else if(health > 100) {
			health = 100;
		}
		
		//PrintToChatAll("Stored health: %d \n Infect damage: %d \n New health: %d", g_iClientHealth[human], g_iClientInfectDamage[human], health);
		SetEntProp(human, Prop_Send, "m_iHealth", health);
	} else {
		SetEntProp(human, Prop_Send, "m_iHealth", 100); // <1 = Create non dead player..
	}
	
	SetEntProp(human, Prop_Send, "m_ArmorValue", g_iClientArmor[human], 1);
	SetEntProp(human, Prop_Send, "m_bHasHelmet", g_iClientHelmet[human], 1);
}

stock void SaveClientData(int victim)
{
	//g_iClientHealth[victim] = GetClientHealth(victim);
	g_iClientArmor[victim] = GetEntProp(victim, Prop_Send, "m_ArmorValue");
	g_iClientHelmet[victim] = GetEntProp(victim, Prop_Send, "m_bHasHelmet");
	g_iClientNvg[victim] = GetEntProp(victim, Prop_Send, "m_bHasNightVision");

	g_iClientHEGrenade[victim] = GetEntProp(victim, Prop_Data, "m_iAmmo", _, g_bIsCSGO ? 14 : 11);
	g_iClientFlashbang[victim] = GetEntProp(victim, Prop_Data, "m_iAmmo", _, g_bIsCSGO ? 15: 12);
	g_iClientSmokegrenade[victim] = GetEntProp(victim, Prop_Data, "m_iAmmo", _, g_bIsCSGO ? 16: 13);
	if (g_bIsCSGO) {
		g_iClientIncendiary[victim] = GetEntProp(victim, Prop_Data, "m_iAmmo", _, 17);
		g_iClientDecoy[victim] = GetEntProp(victim, Prop_Data, "m_iAmmo", _, 18);
		g_iClientTactial[victim] = GetEntProp(victim, Prop_Data, "m_iAmmo", _, 22);
	}

	GetClientMainWeapons(victim);
}

stock void GetClientMainWeapons(int client)
{
	int weapons[Slot_MAXSIZE]; // x = weapon slot.
	for (int x = 0; x < WEAPONS_SLOTS_MAX; x++) {
		weapons[x] = GetPlayerWeaponSlot(client, x);
	}

	char entityname[WEAPONS_MAX_LENGTH];
	for (int x = 0; x < WEAPONS_SLOTS_MAX; x++) {
		if (weapons[x] == -1)
			continue;

		if (view_as<WeaponsSlot>(x) == Slot_Primary) {
			GetEdictClassname(weapons[x], entityname, sizeof(entityname));
			g_sWeapon_Primary[client] = entityname;
			continue;
		}

		if (view_as<WeaponsSlot>(x) == Slot_Secondary) {
			GetEdictClassname(weapons[x], entityname, sizeof(entityname));
			g_sWeapon_Secondary[client] = entityname;
			continue;
		}
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
