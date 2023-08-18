#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <multicolors>
#include <zombiereloaded>
#include <KnockbackRestrict>

#pragma newdecls required

static const char commands[][] = {
	"sm_bknife",
	"sm_cancelknife",
	"sm_cknife"
};

enum struct CKnife {
	int attackerUserId;
	int victimUserId;
	
	char attackerName[32];
	char victimName[32];
	
	float victimOrigin[3];
	
	int time;
	
	ArrayList deadPeople;
}

enum struct CKnifeRevert {
	int humanId;
	float pos[3];
}

Handle g_hCheckAllKnivesTimer;

ArrayList g_arAllKnives;

ConVar g_cvKnifeTime;
ConVar g_cvSlayKnifer;
ConVar g_cvKbanKnifer;

bool g_bKnifeModeEnabled = false;

int g_iClientTime[MAXPLAYERS + 1];
int g_iClientKnifer[MAXPLAYERS + 1];

public Plugin myinfo = {
	name		= "CancelKnife",
	author		= "Dolly",
	description	= "Allows admins to cancel the knife and revert all things that happened caused by that knife",
	version		= "1.0",
	url			= ""
};

public void OnPluginStart() {
	for(int i = 0; i < sizeof(commands); i++) {
		RegAdminCmd(commands[i], Command_CKnife, ADMFLAG_BAN);
	}
	
	g_arAllKnives = new ArrayList(ByteCountToCells(128));
	
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
	
	CSetPrefix("{cyan}[Knife Cancel]");
	
	g_cvKnifeTime = CreateConVar("sm_cknife_time", "20", "How many seconds to allow the admin to target the knifer after the incident?");
	g_cvSlayKnifer = CreateConVar("sm_cknife_slay_knifer", "1", "Should we slay the knifer after canceling the knife?");
	g_cvKbanKnifer = CreateConVar("sm_cknife_kban_knifer", "1", "Should we kban the knifer after canceling the knife?");
	
	AutoExecConfig();
}

public void OnMapEnd() {
	g_hCheckAllKnivesTimer = null;
	
	for(int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));
		delete knife.deadPeople;
	}
	
	g_arAllKnives.Clear();
}

public void OnClientPutInServer(int client) {
	g_iClientTime[client] = 0;
	g_iClientKnifer[client] = 0;
}

Action CheckAllKnives_Timer(Handle timer) {
	if(g_bKnifeModeEnabled) {
		g_hCheckAllKnivesTimer = null;
		return Plugin_Stop;
	}
	
	// not supposed to happen
	if(g_arAllKnives == null) {
		return Plugin_Handled;
	}
	
	/* We want to remove any knife that is expired */
	int knivesCount = g_arAllKnives.Length;
	if(!knivesCount) {
		return Plugin_Handled;
	}
	
	for(int i = 0; i < knivesCount; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));
		if(knife.time < GetTime()) {
			ClearData(knife);
			delete knife.deadPeople;
			g_arAllKnives.Erase(i);
		}
	}
	
	return Plugin_Continue;
}

Action Command_CKnife(int client, int args) {
	if(!client) {
		return Plugin_Handled;
	}
	
	if(g_arAllKnives == null || g_arAllKnives.Length == 0) {
		CReplyToCommand(client, "{white}No active knives found!");
		return Plugin_Handled;
	}
	 
	/* Check if admin typed the command only with arguments, we will open a menu */
	if(args < 1) {
		OpenCKnifeMenu(client);
		return Plugin_Handled;
	}
	
	char targetName[32];
	GetCmdArg(1, targetName, sizeof(targetName));
	
	int count = GetKnivesCount(targetName);
	if(count < 1) {
		CReplyToCommand(client, "{white}No Active Knives were found with this name.");
		return Plugin_Handled;
	}
	
	OpenCKnifeMenu(client, targetName);
	return Plugin_Handled;
}

void OpenCKnifeMenu(int client, char[] targetName = "") {
	Menu menu = new Menu(Menu_Callback);
	menu.SetTitle("[Knife Cancel] Active Knives!");
	
	for(int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));
		
		if(knife.time < GetTime()) {
			continue;
		}
		
		char itemTitle[120];
		FormatEx(itemTitle, sizeof(itemTitle), "Knifer: %s | Zombie: %s | [%d seconds left]", knife.attackerName, knife.victimName, knife.time - GetTime());
		
		char itemInfo[8];
		IntToString(knife.attackerUserId, itemInfo, sizeof(itemInfo));
		
		if(targetName[0]) {
			if(StrContains(knife.attackerName, targetName) != -1 || StrContains(knife.victimName, targetName) != -1) {
				menu.AddItem(itemInfo, itemTitle);
			}
		} else {
			menu.AddItem(itemInfo, itemTitle);
		}
	}
	
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Menu_Callback(Menu menu, MenuAction action, int param1, int param2) {
	switch(action) {
		case MenuAction_End: {
			delete menu;
		}
		
		case MenuAction_Select: {
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
	for(int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));
		if(knife.attackerUserId != userid) {
			continue;
		}
		
		ClearData(knife);
		
		CPrintToChatAll("{white}Canceling the Knife [{blue}%s {white}X {red}%s{white}] in progress...", knife.attackerName, knife.victimName);
		
		int knifer;
		if(g_cvSlayKnifer.BoolValue) {
			knifer = GetClientOfUserId(userid);
			
			if(knifer) {
				ForcePlayerSuicide(knifer);
				CPrintToChatAll("{white}Successfully slayed {red}%s {white}for {olive}knifing.", knife.attackerName);
			}	
		}
		
		if(g_cvKbanKnifer.BoolValue) {
			if(!knifer) {
				knifer = GetClientOfUserId(userid);
			}
			
			if(knifer) {
				KR_BanClient(admin, knifer, 120, "Knifing");
			}
		}
		
		int zombie = GetClientOfUserId(knife.victimUserId);
		if(zombie) {
			TeleportEntity(zombie, knife.victimOrigin);
			CPrintToChatAll("{white}Successfully teleported {olive}%s {white}back to the old position", knife.victimName);
		}
		
		for(int j = 0; j < knife.deadPeople.Length; j++) {
			CKnifeRevert knifeRevert;
			knife.deadPeople.GetArray(j, knifeRevert, sizeof(knifeRevert));
			int human = GetClientOfUserId(knifeRevert.humanId);
			if(human) {
				TeleportEntity(human, knifeRevert.pos);
				ZR_HumanClient(human);
				
				CPrintToChatAll("{white}Successfully turned {olive}%N {white}into {olive}human.", human);
			}
		}
	}
}

int GetKnivesCount(char[] targetName) {
	int count;
	for(int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));
		if(StrContains(knife.attackerName, targetName) != -1 || StrContains(knife.victimName, targetName) != -1) {
			count++;
		}
	}
	
	return count;
}

Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	if(g_bKnifeModeEnabled) {
		return Plugin_Continue;
	}
	
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	
	if(victim < 1 || victim > MaxClients || !IsClientInGame(victim) || attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker)) {
		return Plugin_Continue;
	}
	
	if(!(GetClientTeam(victim) == CS_TEAM_T && GetClientTeam(attacker) == CS_TEAM_CT)) {
		return Plugin_Continue;
	}
	
	char weapon[32];
	event.GetString("weapon", weapon, sizeof(weapon));
	if(!StrEqual(weapon, "knife")) {
		return Plugin_Continue;
	}
	
	int damage = event.GetInt("dmg_health");
	if(damage < 35.0) {
		return Plugin_Continue;
	}
	
	if(g_iClientTime[victim] != 0 && g_iClientTime[victim] < GetTime()) {
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
	
	for(int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife tempKnife;
		g_arAllKnives.GetArray(i, tempKnife, sizeof(tempKnife));
		
		if(tempKnife.attackerUserId == knife.attackerUserId && tempKnife.victimUserId == knife.victimUserId) {
			delete tempKnife.deadPeople;
			g_arAllKnives.Erase(i);
			break;
		}
	}
	
	knife.deadPeople = new ArrayList(ByteCountToCells(64));
	g_arAllKnives.PushArray(knife);
	return Plugin_Continue;
}

public void ZR_OnClientInfected(int client, int attacker, bool motherInfect) {
	if(motherInfect) {
		return;
	}
	
	if(g_iClientTime[attacker] < GetTime()) {
		return;
	}
	
	g_iClientTime[client] = g_iClientTime[attacker];
	g_iClientKnifer[client] = g_iClientKnifer[attacker];
	
	int humanId = GetClientUserId(client); 
	
	float humanOrigin[3];
	GetClientAbsOrigin(client, humanOrigin);
	
	for(int i = 0; i < g_arAllKnives.Length; i++) {
		CKnife knife;
		g_arAllKnives.GetArray(i, knife, sizeof(knife));
		
		if(knife.attackerUserId == g_iClientKnifer[attacker]) {
			CKnifeRevert knifeRevert;
			knifeRevert.humanId = humanId;
			knifeRevert.pos[0] = humanOrigin[0];
			knifeRevert.pos[1] = humanOrigin[1];
			knifeRevert.pos[2] = humanOrigin[2];
			
			knife.deadPeople.PushArray(knifeRevert);
		}
	}
}

public void OnLibraryAdded(const char[] name) {
	if(StrEqual(name, "KnifeMode")) {
		g_bKnifeModeEnabled = true;
	}
	
	delete g_hCheckAllKnivesTimer;
	g_hCheckAllKnivesTimer = CreateTimer(2.0, CheckAllKnives_Timer, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public void OnLibraryRemoved(const char[] name) {
	if(StrEqual(name, "KnifeMode")) {
		g_bKnifeModeEnabled = false;
	}
}

void ClearData(CKnife knife) {
	int zombie = GetClientOfUserId(knife.victimUserId);
	if(zombie) {
		g_iClientTime[zombie] = 0;
		g_iClientKnifer[zombie] = 0;
	}
	
	for(int i = 0; i < knife.deadPeople.Length; i++) {
		CKnifeRevert revert;
		knife.deadPeople.GetArray(i, revert, sizeof(revert));
		int human = GetClientOfUserId(revert.humanId);
		if(human) {
			g_iClientTime[human] = 0;
			g_iClientKnifer[human] = 0;
		}
	}
}
