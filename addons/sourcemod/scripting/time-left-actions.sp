/*****************************************************************

Time Left Actions
Copyright (C) 2011 BCServ (plugins@bcserv.eu)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, 
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

*****************************************************************/

/*****************************************************************


C O M P I L E   O P T I O N S


*****************************************************************/
// enforce semicolons after each code statement
#pragma semicolon 1

/*****************************************************************


P L U G I N   I N C L U D E S


*****************************************************************/
#include <sourcemod>
#include <sdktools>
#include <smlib>
#include <smlib/pluginmanager>
#include <config>
#include <soundlib>

/*****************************************************************


P L U G I N   I N F O


*****************************************************************/
public Plugin:myinfo = 
{
	name = "Time Left Actions", 
	author = "Chanz", 
	description = "Actions like sounds and command are executed when a specified time has been reached.", 
	version = "3.0", 
	url = "http://forums.alliedmods.net/showthread.php?p=843377"
}

/*****************************************************************


P L U G I N   D E F I N E S


*****************************************************************/
#define MAX_COMMAND_LENGTH 		192
#define MAX_ACTIONS 			256
#define MAX_CHAT_LENGTH 		192
#define MAX_SOUNDS_PER_ACTION	8
#define THINK_INTERVAL 			1.0
#define MAX_CONDITION_LENGTH	128


/*****************************************************************


G L O B A L   V A R S


*****************************************************************/
//Use a good notation, constants for arrays, initialize everything that has nothing to do with clients!
//If you use something which requires client index init it within the function Client_InitVars (look below)
//Example: Bad: "decl servertime" Good: "new g_iServerTime = 0"
//Example client settings: Bad: "decl saveclientname[33][32] Good: "new g_szClientName[MAXPLAYERS+1][MAX_NAME_LENGTH];" -> later in Client_InitVars: GetClientName(client, g_szClientName, sizeof(g_szClientName));

//Engine Cvars
new Handle:g_cvarTimeLimit	= INVALID_HANDLE;
new Handle:g_cvarC4Timer	= INVALID_HANDLE;

//Cvars
new Handle:g_cvarEnable 					= INVALID_HANDLE;
new Handle:g_cvarPlugin_Config_Name = INVALID_HANDLE;

//Runtime Optimizer
new g_iPlugin_Enable 					= 1;
new String:g_szPlugin_Config_Name[MAX_NAME_LENGTH] = "default.conf";

//Fake strucks
enum TimeLeftSound {
	
	String:TimeLeftSound_Path[PLATFORM_MAX_PATH], 
	Float:TimeLeftSound_Length
};

enum TimeLeftType {
	
	TimeLeftType_None 		= 0, 
	TimeLeftType_Map 		= 1, 
	TimeLeftType_Round 		= 2, 
	TimeLeftType_Bomb 		= 4
};

enum TimeLeftAction {
	
	TimeLeftType:TimeLeftAction_Type, 
	Float:TimeLeftAction_Time, 
	String:TimeLeftAction_Condition[MAX_CONDITION_LENGTH], 
	String:TimeLeftAction_Cmd[MAX_COMMAND_LENGTH], 
	String:TimeLeftAction_Chat[MAX_CHAT_LENGTH]
};

new g_tlaActions[MAX_ACTIONS][TimeLeftAction];
new g_iActionsPos = 0;

new g_tlsActionSounds[MAX_ACTIONS][MAX_SOUNDS_PER_ACTION][TimeLeftSound];

//Map
new g_iMap_TimeLeft = 1200;
new bool:g_bMap_TimeLeft_Started = false;

//Round
new g_iRound_TimeLeft = 300;
new bool:g_bHooked_Round_Start = false;

//Bomb
new g_iBomb_TimeLeft = 45;
new bool:g_bHooked_Bomb_Planted = false;

//Think
new Handle:g_hThink_Map = INVALID_HANDLE;
new Handle:g_hThink_Round = INVALID_HANDLE;
new Handle:g_hThink_Bomb = INVALID_HANDLE;

/*****************************************************************


F O R W A R D   P U B L I C S


*****************************************************************/
public OnPluginStart() 
{
	// Initialization for SMLib
	PluginManager_Initialize("time-left-actions", "[SM] ");
	
	//Translations (you should use it always when printing something to clients)
	//Always with plugin. as prefix, the short name and .phrases as postfix.
	//decl String:translationsName[PLATFORM_MAX_PATH];
	//Format(translationsName, sizeof(translationsName), "plugin.%s.phrases", g_sPlugin_Short_Name);
	//File_LoadTranslations(translationsName);
	
	//Command Hooks (AddCommandListener) (If the command already exists, like the command kill, then hook it!)
	
	
	//Register New Commands (RegConsoleCmd) (If the command doesn't exist, hook it here)
	
	
	//Register Admin Commands (RegAdminCmd)
	
	
	//Cvars: Create a global handle variable.
	g_cvarEnable = PluginManager_CreateConVar("enable", "1", "Enables or disables this plugin");
	g_cvarPlugin_Config_Name = PluginManager_CreateConVar("config_name", "default.conf", "Filename of the action config to use (located in <moddir>/addons/sourcemod/configs/time-left-actions/)", FCVAR_PLUGIN);

	// Cvar change hook:
	HookConVarChange(g_cvarEnable, ConVarChange_Enable);
	HookConVarChange(g_cvarTimeLimit, ConVarChange_TimeLimit);
	HookConVarChange(g_cvarPlugin_Config_Name, ConVarChange_Config_Name);
	
	//Find ConVars
	g_cvarC4Timer = FindConVar("mp_c4timer");
	g_cvarTimeLimit = FindConVar("mp_timelimit");
	
	//Event Hooks
	g_bHooked_Round_Start = HookEventEx("round_start", 			Event_RoundStart);
	HookEventEx("round_freeze_end", 	Event_RoundFreezeEnd);
	HookEventEx("round_end", 			Event_RoundEnd);
	g_bHooked_Bomb_Planted = HookEventEx("bomb_planted", 		Event_BombPlanted);
}

public OnMapStart() 
{
	SetConVarString(Plugin_VersionCvar, Plugin_Version);
	
	RestartMapTimer();
}

public OnMapEnd() 
{
	g_bMap_TimeLeft_Started = false;
	
	if (g_hThink_Map != INVALID_HANDLE) {
		CloseHandle(g_hThink_Map);
		g_hThink_Map = INVALID_HANDLE;
	}
	
	if (g_hThink_Round != INVALID_HANDLE) {
		CloseHandle(g_hThink_Round);
		g_hThink_Round = INVALID_HANDLE;
	}
	
	if (g_hThink_Bomb != INVALID_HANDLE) {
		CloseHandle(g_hThink_Bomb);
		g_hThink_Bomb = INVALID_HANDLE;
	}
}

public OnConfigsExecuted() 
{
	//Set your ConVar runtime optimizers here
	g_iPlugin_Enable = GetConVarInt(g_cvarEnable);
	GetConVarString(g_cvarPlugin_Config_Name, g_szPlugin_Config_Name, sizeof(g_szPlugin_Config_Name));
	
	//Get Config
	Actions_Load();
	
	//Mind: this is only here for late load, since on map change or server start, there isn't any client.
	//Remove it if you don't need it.
	Client_InitializeAll();
}

public OnClientPutInServer(client) 
{
	if (!g_bMap_TimeLeft_Started && IsServerProcessing()) {
		
		RestartMapTimer();
	}
	
	Client_Initialize(client);
}

public OnClientPostAdminCheck(client) 
{
	Client_Initialize(client);
}

/****************************************************************


C A L L B A C K   F U N C T I O N S


****************************************************************/
public ConVarChange_Enable(Handle:cvar, const String:oldVal[], const String:newVal[])

{
	g_iPlugin_Enable = StringToInt(newVal);
}
public ConVarChange_TimeLimit(Handle:cvar, const String:oldVal[], const String:newVal[]) 
{
	RestartMapTimer();
}

public ConVarChange_Config_Name(Handle:cvar, const String:oldVal[], const String:newVal[]) 
{
	
	strcopy(g_szPlugin_Config_Name, sizeof(g_szPlugin_Config_Name), newVal);
	
	Actions_Load();
}

public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast) 
{
	if (g_hThink_Bomb != INVALID_HANDLE) {
		CloseHandle(g_hThink_Bomb);
		g_hThink_Bomb = INVALID_HANDLE;
	}
	
	g_iRound_TimeLeft = GetEventInt(event, "timelimit");
	return Plugin_Continue;
}

public Action:Event_RoundFreezeEnd(Handle:event, const String:name[], bool:dontBroadcast) 
{
	if (g_hThink_Round != INVALID_HANDLE) {
		CloseHandle(g_hThink_Round);
		g_hThink_Round = INVALID_HANDLE;
	}
	g_hThink_Round = CreateTimer(THINK_INTERVAL, Timer_Think_Round, INVALID_HANDLE, TIMER_REPEAT);
	return Plugin_Continue;
}

public Action:Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast) 
{
	if (g_hThink_Round != INVALID_HANDLE) {
		CloseHandle(g_hThink_Round);
		g_hThink_Round = INVALID_HANDLE;
	}
	
	if (g_hThink_Bomb != INVALID_HANDLE) {
		CloseHandle(g_hThink_Bomb);
		g_hThink_Bomb = INVALID_HANDLE;
	}
	return Plugin_Continue;
}

public Action:Event_BombPlanted(Handle:event, const String:name[], bool:dontBroadcast) 
{
	if (g_hThink_Round != INVALID_HANDLE) {
		CloseHandle(g_hThink_Round);
		g_hThink_Round = INVALID_HANDLE;
	}
	if (g_hThink_Bomb != INVALID_HANDLE) {
		CloseHandle(g_hThink_Bomb);
		g_hThink_Bomb = INVALID_HANDLE;
	}
	g_iBomb_TimeLeft = GetConVarInt(g_cvarC4Timer);
	g_hThink_Bomb = CreateTimer(THINK_INTERVAL, Timer_Think_Bomb, INVALID_HANDLE, TIMER_REPEAT);
	return Plugin_Continue;
}

public Action:Timer_Think_Map(Handle:timer) 
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}
	
	new Float:diff = -1.0;
	
	
	for (new pos=0;pos<g_iActionsPos;pos++) {
		
		if (g_tlaActions[pos][TimeLeftAction_Type] & TimeLeftType_Map) {
			
			diff = float(g_iMap_TimeLeft) - g_tlaActions[pos][TimeLeftAction_Time];
			if (diff >= 1.0 || diff < 0.0) {
				//PrintToServer("Think_Map -> diff >= 1.0 || diff < 0.0");
				continue;
			}
			
			//PrintToServer("Think_Map Execute Action");
			CreateTimer(diff, Timer_ExecuteAction, pos);
		}
	}
	
	g_iMap_TimeLeft--;
	return Plugin_Continue;
}

public Action:Timer_Think_Round(Handle:timer) 
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}
	
	new Float:diff = -1.0;
	
	
	for (new pos=0;pos<g_iActionsPos;pos++) {
		
		if (g_tlaActions[pos][TimeLeftAction_Type] & TimeLeftType_Round) {
			
			diff = float(g_iRound_TimeLeft) - g_tlaActions[pos][TimeLeftAction_Time] - 1.0;
			
			if (diff >= 1.0 || diff < 0.0) {
				//PrintToServer("Think_Round -> diff >= 1.0 || diff < 0.0 -> %f", diff);
				continue;
			}
			
			//PrintToServer("Think_Map Execute Action");
			CreateTimer(diff, Timer_ExecuteAction, pos);
		}
	}
	
	g_iRound_TimeLeft--;
	return Plugin_Continue;
}

public Action:Timer_Think_Bomb(Handle:timer) 
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}
	
	new Float:diff = -1.0;
	
	
	for (new pos=0;pos<g_iActionsPos;pos++) {
		
		if (g_tlaActions[pos][TimeLeftAction_Type] & TimeLeftType_Bomb) {
			
			diff = float(g_iBomb_TimeLeft) - g_tlaActions[pos][TimeLeftAction_Time] - 1.0;
			
			//if its 1 second or less activate the timer to execute the action, but if its below 0 (zero) don't execute it.
			if (diff >= 1.0 || diff < 0.0) {
				//PrintToServer("Think_Bomb -> diff >= 1.0 || diff < 0.0 -> %f", diff);
				continue;
			}
			
			//PrintToServer("Think_Bomb Execute Action");
			CreateTimer(diff, Timer_ExecuteAction, pos);
		}
	}
	
	g_iBomb_TimeLeft--;
	return Plugin_Continue;
}

public Action:Timer_ExecuteAction(Handle:timer, any:pos) 
{
	//Sound
	if (
		(g_tlaActions[pos][TimeLeftAction_Type] & TimeLeftType_Map && (!g_bHooked_Round_Start || !Team_HaveAllPlayers())) ||
		(g_tlaActions[pos][TimeLeftAction_Type] & TimeLeftType_Round && g_bHooked_Round_Start && Team_HaveAllPlayers()) ||
		(g_tlaActions[pos][TimeLeftAction_Type] & TimeLeftType_Bomb && g_bHooked_Bomb_Planted)
	) {
		
		new Float:nextSound = 0.0;
		new Handle:dataPack = INVALID_HANDLE;
		
		for (new j=0;j<MAX_SOUNDS_PER_ACTION;j++) {
			
			if (g_tlsActionSounds[pos][j][TimeLeftSound_Path][0] != '\0') {
				
				dataPack = CreateDataPack();
				WritePackString(dataPack, g_tlsActionSounds[pos][j][TimeLeftSound_Path]);
				ResetPack(dataPack);
				
				
				CreateTimer(nextSound, Timer_PlaySound, dataPack);
				
				nextSound += g_tlsActionSounds[pos][j][TimeLeftSound_Length];
			}
		}
	}
	//Command
	if (g_tlaActions[pos][TimeLeftAction_Cmd][0] != '\0') {
		
		new String:cmd[MAX_COMMAND_LENGTH];
		String_ReplaceTokens(g_tlaActions[pos][TimeLeftAction_Cmd], cmd, sizeof(cmd));
		ServerCommand(cmd);
	}
	//Chat
	if (g_tlaActions[pos][TimeLeftAction_Chat][0] != '\0') {
		
		new String:chat[MAX_CHAT_LENGTH];
		
		//LOOP_CLIENTS(client, CLIENTFILTER_INGAMEAUTH|CLIENTFILTER_NOBOTS) {
		
		for (new client=1;client<=MaxClients;client++) {
			
			if (IsClientInGame(client) && !IsFakeClient(client)) {
				
				chat[0] = '\0';
				String_ReplaceTokens(g_tlaActions[pos][TimeLeftAction_Chat], chat, sizeof(chat), client);
				Client_PrintToChat(client, false, chat);
			}
		}
	}
	return Plugin_Handled;
}

public Action:Timer_PlaySound(Handle:timer, any:dataPack) 
{
	new String:sound[PLATFORM_MAX_PATH];
	ReadPackString(dataPack, sound, sizeof(sound));
	CloseHandle(dataPack);
	
	new String:buffer[PLATFORM_MAX_PATH];
	
	LOOP_CLIENTS(client, CLIENTFILTER_INGAMEAUTH|CLIENTFILTER_NOBOTS) {
		
		String_ReplaceTokens(sound, buffer, sizeof(buffer), client);
		EmitSoundToClient(client, buffer);
	}
	return Plugin_Handled;
}
/*****************************************************************


P L U G I N   F U N C T I O N S


*****************************************************************/

stock RestartMapTimer() 
{
	//Map Timer
	if (g_hThink_Map != INVALID_HANDLE) {
		CloseHandle(g_hThink_Map);
		g_hThink_Map = INVALID_HANDLE;
	}
	
	new bool:gotTimeLeft = GetMapTimeLeft(g_iMap_TimeLeft);
	
	if (gotTimeLeft && g_iMap_TimeLeft > 0) {
		
		g_bMap_TimeLeft_Started = true;
		g_hThink_Map = CreateTimer(THINK_INTERVAL, Timer_Think_Map, INVALID_HANDLE, TIMER_REPEAT);
	}
}

Actions_ClearAll()
{
	g_iActionsPos = 0;
	
	for (new i=0;i<MAX_ACTIONS;i++) {
		
		g_tlaActions[i][TimeLeftAction_Type] 				= TimeLeftType_None;
		g_tlaActions[i][TimeLeftAction_Time] 				= 0.0;
		g_tlaActions[i][TimeLeftAction_Condition][0]		= '\0';
		g_tlaActions[i][TimeLeftAction_Cmd][0] 				= '\0';
		g_tlaActions[i][TimeLeftAction_Chat][0]				= '\0';
		
		for (new j=0;j<MAX_SOUNDS_PER_ACTION;j++) {
			
			g_tlsActionSounds[i][j][TimeLeftSound_Path][0] 	= '\0';
			g_tlsActionSounds[i][j][TimeLeftSound_Length] 	= 0.0;
		}
	}
}

bool:Actions_Load()
{
	Actions_ClearAll();
	
	new String:configPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, configPath, sizeof(configPath), "configs/time-left-actions/%s", g_szPlugin_Config_Name);
	
	new line;
	new String:errorMsg[PLATFORM_MAX_PATH];
	new Handle:config = ConfigCreate();
	
	if (!ConfigReadFile(config, configPath, errorMsg, sizeof(errorMsg), line)) {
		
		LogError("Can't read config file %s: %s @ line %d", configPath, errorMsg, line);
		CloseHandle(config);
		return false;
	}
	
	// get parent setting containing the remote host groups
	new Handle:parent 				= ConfigLookup(config, "time-left-actions");
	new Handle:child 				= INVALID_HANDLE;
	new Handle:childType 			= INVALID_HANDLE;
	new Handle:childTime 			= INVALID_HANDLE;
	//new Handle:childCondition 		= INVALID_HANDLE;
	new Handle:childSound 			= INVALID_HANDLE;
	new Handle:sound 				= INVALID_HANDLE;
	new Handle:childCmd 			= INVALID_HANDLE;
	new Handle:childChat 			= INVALID_HANDLE;
	
	new String:buffer[2048];
	new String:buffers[MAX_SOUNDS_PER_ACTION*2][PLATFORM_MAX_PATH];
	
	new offset = 0;
	
	// get amount of children
	new length = ConfigSettingLength(parent);
	if (length > MAX_ACTIONS) { length = MAX_ACTIONS; }
	for (new i=0; i<length; i++) {
		
		//fetch
		child = ConfigSettingGetElement(parent, i);
		
		childType = ConfigSettingGetMember(child, "type");
		if (childType == INVALID_HANDLE) {
			LogError("key 'type' is missing in element %d", i);
			continue;
		}
		
		childTime = ConfigSettingGetMember(child, "time");
		if (childTime == INVALID_HANDLE) {
			LogError("key 'time' is missing in element %d", i);
			continue;
		}
		
		/*childCondition = ConfigSettingGetMember(child, "condition");
		if (childCondition == INVALID_HANDLE) {
			LogError("key 'condition' is missing in element %d", i);
			continue;
		}*/
		
		childSound = ConfigSettingGetMember(child, "sound");
		if (childSound == INVALID_HANDLE) {
			LogError("key 'sound' is missing in element %d", i);
			continue;
		}
		
		childCmd = ConfigSettingGetMember(child, "cmd");
		if (childCmd == INVALID_HANDLE) {
			LogError("key 'cmd' is missing in element %d", i);
			continue;
		}
		
		childChat = ConfigSettingGetMember(child, "chat");
		if (childChat == INVALID_HANDLE) {
			LogError("key 'chat' is missing in element %d", i);
			continue;
		}
		
		//save
		g_tlaActions[g_iActionsPos][TimeLeftAction_Type] = TimeLeftType:ConfigSettingGetInt(childType);
		g_tlaActions[g_iActionsPos][TimeLeftAction_Time] = ConfigSettingGetFloat(childTime);
		//ConfigSettingGetString(childCondition, g_tlaActions[g_iActionsPos][TimeLeftAction_Condition], MAX_CONDITION_LENGTH);
		ConfigSettingGetString(childSound, buffer, sizeof(buffer));
		ConfigSettingGetString(childCmd, g_tlaActions[g_iActionsPos][TimeLeftAction_Cmd], MAX_COMMAND_LENGTH);
		ConfigSettingGetString(childChat, g_tlaActions[g_iActionsPos][TimeLeftAction_Chat], MAX_CHAT_LENGTH);
		
		//PrintToServer("Found time: %f with type: %d", g_tlaActions[g_iActionsPos][TimeLeftAction_Time], g_tlaActions[g_iActionsPos][TimeLeftAction_Type]);
		
		//use
		if (buffer[0] != '\0') {
			
			ExplodeString(buffer, ";", buffers, sizeof(buffers), sizeof(buffers[]));
			offset = 0;
			
			for (new j=0;j<sizeof(buffers);j++) {
				
				if (buffers[j][0] == '\0') {
					continue;
				}
				
				//if this part is nummeric, its a correction of the length for the previous sound
				if (String_IsNumeric(buffers[j])) {
					
					offset--;
					g_tlsActionSounds[g_iActionsPos][j+offset][TimeLeftSound_Length] += StringToFloat(buffers[j]);
					continue;
				}
				
				if (j+offset > MAX_SOUNDS_PER_ACTION) {
					LogError("maximum reached: can't use sound '%s' in type: %d at time ~%.2fs, sound #%d", buffers[j], g_tlaActions[g_iActionsPos][TimeLeftAction_Type], g_tlaActions[g_iActionsPos][TimeLeftAction_Time], j+1);
					continue;
				}
				
				sound = OpenSoundFile(buffers[j]);
				
				if (sound == INVALID_HANDLE) {
					LogError("can't open sound '%s' in type: %d at time ~%.2fs, sound #%d", buffers[j], g_tlaActions[g_iActionsPos][TimeLeftAction_Type], g_tlaActions[g_iActionsPos][TimeLeftAction_Time], j+1);
					continue;
				}
				
				PrecacheSound(buffers[j], true);
				
				strcopy(g_tlsActionSounds[g_iActionsPos][j+offset][TimeLeftSound_Path], PLATFORM_MAX_PATH, buffers[j]);
				g_tlsActionSounds[g_iActionsPos][j+offset][TimeLeftSound_Length] = GetSoundLengthFloat(sound);
				
				//PrintToServer("sound %s length: %f", g_tlsActionSounds[g_iActionsPos][j+offset][TimeLeftSound_Path], g_tlsActionSounds[g_iActionsPos][j+offset][TimeLeftSound_Length]);
				
				//PrintToServer("-- '%s'", buffers[j]);
				
				Format(buffers[j], sizeof(buffers[]), "sound/%s", buffers[j]);
				AddFileToDownloadsTable(buffers[j]);
				
				buffers[j][0] = '\0';
				CloseHandle(sound);
				sound = INVALID_HANDLE;
			}
		}
		
		//inc pos
		g_iActionsPos++;
	}
	
	// close the config handle
	CloseHandle(config);
	return true;
}


//Client
#define TOKEN_STEAM_ID			"{STEAM_ID}"
#define TOKEN_USER_ID			"{USER_ID}"
#define TOKEN_NAME				"{NAME}"
#define TOKEN_IP				"{IP}"
#define TOKEN_RATE				"{RATE}"
#define TOKEN_ALIVE_TEAMMATES	"{ALIVE_TEAMMATES}"
#define TOKEN_DEAD_TEAMMATES	"{DEAD_TEAMMATES}"
#define TOKEN_ALIVE_ENEMIES		"{ALIVE_ENEMIES}"
#define TOKEN_DEAD_ENEMIES		"{DEAD_ENEMIES}"
#define TOKEN_TEAM				"{TEAM}"
#define TOKEN_ENEMY_TEAM		"{ENEMY_TEAM}"
#define TOKEN_TEAM_COLOR		"{TEAM_COLOR}"
#define TOKEN_ENEMY_TEAM_COLOR	"{ENEMY_TEAM_COLOR}"

//Server
#define TOKEN_SERVER_IP			"{SERVER_IP}"
#define TOKEN_SERVER_PORT		"{SERVER_PORT}"
#define TOKEN_SERVER_NAME		"{SERVER_NAME}"
#define TOKEN_L4D_GAMEMODE		"{L4D_GAMEMODE}"
#define TOKEN_CURRENT_MAP		"{CURRENT_MAP}"
#define TOKEN_NEXT_MAP			"{NEXT_MAP}"
#define TOKEN_CURPLAYERS		"{CURPLAYERS}"
#define TOKEN_MAXPLAYERS 		"{MAXPLAYERS}"
#define TOKEN_ALIVE_PLAYERS		"{ALIVE_PLAYERS}"
#define TOKEN_DEAD_PLAYERS		"{DEAD_PLAYERS}"
#define TOKEN_TIME_LEFT			"{TIME_LEFT}"

stock String_ReplaceTokens(const String:text[], String:output[], maxlen, client=0) 
{
	strcopy(output, maxlen, text);
	
	new teamCount = GetTeamCount();
	new players = 0;
	new String:buffer[256];
	
	if (client != 0 && Client_IsValid(client) && IsClientInGame(client)) {
		
		//SteamID
		GetClientAuthId(client, AuthId_Engine, buffer, sizeof(buffer));
		ReplaceString(output, maxlen, TOKEN_STEAM_ID, buffer, true);
		
		//UserId
		IntToString(GetClientUserId(client), buffer, sizeof(buffer));
		ReplaceString(output, maxlen, TOKEN_USER_ID, buffer, true);
		
		//Name
		GetClientName(client, buffer, sizeof(buffer));
		ReplaceString(output, maxlen, TOKEN_NAME, buffer, true);
		
		//IP
		GetClientIP(client, buffer, sizeof(buffer));
		ReplaceString(output, maxlen, TOKEN_IP, buffer, true);
		
		//Rate
		GetClientInfo(client, "rate", buffer, sizeof(buffer));
		ReplaceString(output, maxlen, TOKEN_RATE, buffer, true);
		
		//Alive Teammates
		IntToString(Team_GetClientCount(GetClientTeam(client), CLIENTFILTER_ALIVE), buffer, sizeof(buffer));
		ReplaceString(output, maxlen, TOKEN_ALIVE_TEAMMATES, buffer, true);
		
		//Dead Teammates
		IntToString(Team_GetClientCount(GetClientTeam(client), CLIENTFILTER_DEAD), buffer, sizeof(buffer));
		ReplaceString(output, maxlen, TOKEN_DEAD_TEAMMATES, buffer, true);
		
		//Alive Enemies
		IntToString(Team_GetClientCount(((GetClientTeam(client) == TEAM_ONE) ? TEAM_TWO : TEAM_ONE), CLIENTFILTER_ALIVE), buffer, sizeof(buffer));
		ReplaceString(output, maxlen, TOKEN_ALIVE_ENEMIES, buffer, true);
		
		//Dead Enemies
		IntToString(Team_GetClientCount(((GetClientTeam(client) == TEAM_ONE) ? TEAM_TWO : TEAM_ONE), CLIENTFILTER_DEAD), buffer, sizeof(buffer));
		ReplaceString(output, maxlen, TOKEN_DEAD_ENEMIES, buffer, true);
		
		//Team
		GetTeamName(GetClientTeam(client), buffer, sizeof(buffer));
		ReplaceString(output, maxlen, TOKEN_TEAM, buffer, true);
		
		//Enemy Team
		GetTeamName(((GetClientTeam(client) == TEAM_ONE) ? TEAM_TWO : TEAM_ONE), buffer, sizeof(buffer));
		ReplaceString(output, maxlen, TOKEN_ENEMY_TEAM, buffer, true);
		
		//Team Color
		Format(buffer, sizeof(buffer), "%s", ((GetClientTeam(client) == TEAM_ONE) ? "{R}" : "{B}"));
		ReplaceString(output, maxlen, TOKEN_TEAM_COLOR, buffer, true);
		
		//Enemy Team Color
		Format(buffer, sizeof(buffer), "%s", ((GetClientTeam(client) == TEAM_TWO) ? "{R}" : "{B}"));
		ReplaceString(output, maxlen, TOKEN_ENEMY_TEAM_COLOR, buffer, true);
	}
	
	//ServerIP
	Server_GetIPString(buffer, sizeof(buffer));
	ReplaceString(output, maxlen, TOKEN_SERVER_IP, buffer, true);
	
	//ServerPort
	IntToString(Server_GetPort(), buffer, sizeof(buffer));
	ReplaceString(output, maxlen, TOKEN_SERVER_PORT, buffer, true);
	
	//ServerName
	Server_GetHostName(buffer, sizeof(buffer));
	ReplaceString(output, maxlen, TOKEN_SERVER_NAME, buffer, true);
	
	//L4D GameMode
	new Handle:gameMode = FindConVar("mp_gamemode");
	if (gameMode != INVALID_HANDLE) {
		GetConVarString(gameMode, buffer, sizeof(buffer));
		ReplaceString(output, maxlen, TOKEN_L4D_GAMEMODE, buffer, true);
	}
	
	//Current Map
	GetCurrentMap(buffer, sizeof(buffer));
	ReplaceString(output, maxlen, TOKEN_CURRENT_MAP, buffer, true);
	
	//Next Map
	GetNextMap(buffer, sizeof(buffer));
	ReplaceString(output, maxlen, TOKEN_NEXT_MAP, buffer, true);
	
	//Current players
	IntToString(GetClientCount(true), buffer, sizeof(buffer));
	ReplaceString(output, maxlen, TOKEN_CURPLAYERS, buffer, true);
	
	//Max players
	IntToString(MaxClients, buffer, sizeof(buffer));
	ReplaceString(output, maxlen, TOKEN_MAXPLAYERS, buffer, true);
	
	//Alive players
	players = 0;
	for (new i=2; i < teamCount; i++) {
		players += Team_GetClientCount(i, CLIENTFILTER_ALIVE);
	}
	IntToString(players, buffer, sizeof(buffer));
	ReplaceString(output, maxlen, TOKEN_ALIVE_PLAYERS, buffer, true);
	
	//Dead players
	players = 0;
	for (new i=2; i < teamCount; i++) {
		players += Team_GetClientCount(i, CLIENTFILTER_DEAD);
	}
	IntToString(players, buffer, sizeof(buffer));
	ReplaceString(output, maxlen, TOKEN_DEAD_PLAYERS, buffer, true);
	
	//Timeleft
	Format(buffer, sizeof(buffer), "%d:%02d", g_iMap_TimeLeft/60, g_iMap_TimeLeft%60);
	ReplaceString(output, maxlen, TOKEN_TIME_LEFT, buffer, true);
}

stock Client_InitializeAll() 
{
	for (new client=1;client<=MaxClients;client++) {
		
		if (!IsClientInGame(client)) {
			continue;
		}
		
		Client_Initialize(client);
	}
}

stock Client_Initialize(client) 
{
	//Variables
	Client_InitializeVariables(client);
	
	
	//Functions
	
	
	//Functions where the player needs to be in game
	if (!IsClientInGame(client)) {
		return;
	}
}

stock Client_InitializeVariables(client) 
{
	//Plugin Client Vars
	
}

