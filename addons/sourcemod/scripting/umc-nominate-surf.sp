/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *                               Ultimate Mapchooser - Nominations                               *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */
/*************************************************************************
*************************************************************************
This plugin is free software: you can redistribute
it and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation, either version 3 of the License, or
later version.

This plugin is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this plugin.  If not, see <http://www.gnu.org/licenses/>.
*************************************************************************
*************************************************************************/
#pragma semicolon 1

#include <sourcemod>
#include <umc-core>
#include <umc_utils>
#include <umc_workshop_stocks>

#define NOMINATE_ADMINFLAG_KEY "nominate_flags"

//Plugin Information
public Plugin:myinfo =
{
	name        = "[UMC] Nominations",
	author      = "Steell, Powerlord, Mr.Silence, AdRiAnIlloO, Edit By Arcala the Gyiyg",
	description = "Extends Ultimate Mapchooser to allow players to nominate maps",
	version     = PL_VERSION,
	url         = "http://forums.alliedmods.net/showthread.php?t=134190"
};

////----CONVARS-----/////
new Handle:cvar_filename        = INVALID_HANDLE;
new Handle:cvar_nominate        = INVALID_HANDLE;
new Handle:cvar_nominate_tiered = INVALID_HANDLE;
new Handle:cvar_mem_map         = INVALID_HANDLE;
new Handle:cvar_mem_group       = INVALID_HANDLE;
new Handle:cvar_sort            = INVALID_HANDLE;
new Handle:cvar_flags           = INVALID_HANDLE;
new Handle:cvar_nominate_time   = INVALID_HANDLE;
////----/CONVARS-----/////

//Mapcycle
new Handle:map_kv = INVALID_HANDLE;
new Handle:umc_mapcycle = INVALID_HANDLE;

//Memory queues. Used to store the previously played maps.
new Handle:vote_mem_arr    = INVALID_HANDLE;
new Handle:vote_catmem_arr = INVALID_HANDLE;

new Handle:nom_menu_groups[MAXPLAYERS+1]    = { INVALID_HANDLE, ... };
new Handle:nom_menu_nomgroups[MAXPLAYERS+1] = { INVALID_HANDLE, ... };
//EACH INDEX OF THE ABOVE TWO ARRAYS CORRESPONDS TO A NOMINATION MENU FOR A PARTICULAR CLIENT.

//Has a vote neem completed?
new bool:vote_completed;

//Can we nominate?
new bool:can_nominate;

// What's the current map?
char currentMap[MAP_LENGTH];

//TODO: Add cvar for enable/disable exclusion from prev. maps.
//      Possible bug: nomination menu doesn't want to display twice for a client in a map.
//      Alphabetize based off of display, not actual map name.
//
//      New map option called "nomination_group" that sets the "real" map group to be used when
//      the map is nominated for a vote. Useful for tiered nomination menu.

//************************************************************************************************//
//                                        SOURCEMOD EVENTS                                        //
//************************************************************************************************//

//Called when the plugin is finished loading.
public OnPluginStart()
{
	cvar_flags = CreateConVar(
		"sm_umc_nominate_defaultflags",
		"",
		"Flags necessary for a player to nominate a map, if flags are not specified by a map in the mapcycle. If empty, all players can nominate."
	);

	cvar_sort = CreateConVar(
		"sm_umc_nominate_sorted",
		"0",
		"Determines the order of maps in the nomination menu.\n 0 - Same as mapcycle,\n 1 - Alphabetical",
		0, true, 0.0, true, 1.0
	);

	cvar_nominate_tiered = CreateConVar(
		"sm_umc_nominate_tiermenu",
		"0",
		"Organizes the nomination menu so that users select a group first, then a map.",
		0, true, 0.0, true, 1.0
	);

	cvar_nominate = CreateConVar(
		"sm_umc_nominate_enabled",
		"1",
		"Specifies whether players have the ability to nominate maps for votes.",
		0, true, 0.0, true, 1.0
	);

	cvar_filename = CreateConVar(
		"sm_umc_nominate_cyclefile",
		"umc_mapcycle.txt",
		"File to use for Ultimate Mapchooser's map rotation."
	);

	cvar_mem_group = CreateConVar(
		"sm_umc_nominate_groupexclude",
		"0",
		"Specifies how many past map groups to exclude from nominations.",
		0, true, 0.0
	);

	cvar_mem_map = CreateConVar(
		"sm_umc_nominate_mapexclude",
		"4",
		"Specifies how many past maps to exclude from nominations. 1 = Current Map Only",
		0, true, 0.0
	);

	cvar_nominate_time = CreateConVar(
		"sm_umc_nominate_duration",
		"20",
		"Specifies how long the nomination menu should remain open for. Minimum is 10 seconds!",
		0, true, 10.0
	);

	//Create the config if it doesn't exist, and then execute it.
	AutoExecConfig(true, "umc-nominate");

	//Reg the nominate console cmd
	RegConsoleCmd("sm_nominate", Command_Nominate);

	//Reg the nomlist command
	RegConsoleCmd("sm_nomlist", Command_ListNominations);
	RegConsoleCmd("sm_listnoms", Command_ListNominations);
	RegConsoleCmd("sm_nominationlist", Command_ListNominations);
	RegConsoleCmd("sm_listnominations", Command_ListNominations);

	//Reg the recently palyed command.
	RegConsoleCmd("sm_rp", Command_ListRecentlyPlayed);
	RegConsoleCmd("sm_played", Command_ListRecentlyPlayed);

	//Make listeners for player chat. Needed to recognize chat commands ("rtv", etc.)
	AddCommandListener(OnPlayerChat, "say");
	AddCommandListener(OnPlayerChat, "say2"); //Insurgency Only
	AddCommandListener(OnPlayerChat, "say_team");

	//Initialize our memory arrays
	new numCells = ByteCountToCells(MAP_LENGTH);
	vote_mem_arr    = CreateArray(numCells);
	vote_catmem_arr = CreateArray(numCells);

	//Load the translations file
	LoadTranslations("ultimate-mapchooser.phrases");
}

//************************************************************************************************//
//                                           GAME EVENTS                                          //
//************************************************************************************************//

//Called after all config files were executed.
public OnConfigsExecuted()
{
	can_nominate = ReloadMapcycle();
	vote_completed = false;

	new Handle:groupArray = INVALID_HANDLE;
	for (new i = 0; i < sizeof(nom_menu_groups); i++)
	{
		groupArray = nom_menu_groups[i];
		if (groupArray != INVALID_HANDLE)
		{
			CloseHandle(groupArray);
			nom_menu_groups[i] = INVALID_HANDLE;
		}
	}
	for (new i = 0; i < sizeof(nom_menu_nomgroups); i++)
	{
		groupArray = nom_menu_groups[i];
		if (groupArray != INVALID_HANDLE)
		{
			CloseHandle(groupArray);
			nom_menu_groups[i] = INVALID_HANDLE;
		}
	}

	//Grab the name of the current map.
	decl String:mapName[MAP_LENGTH];
	GetCurrentMap(mapName, sizeof(mapName));

	decl String:groupName[MAP_LENGTH];
	UMC_GetCurrentMapGroup(groupName, sizeof(groupName));

	if (can_nominate && StrEqual(groupName, INVALID_GROUP, false))
	{
		KvFindGroupOfMap(umc_mapcycle, mapName, groupName, sizeof(groupName));
	}

	//Add the map to all the memory queues.
	new mapmem = GetConVarInt(cvar_mem_map);
	new catmem = GetConVarInt(cvar_mem_group);
	AddToMemoryArray(mapName, vote_mem_arr, mapmem);
	AddToMemoryArray(groupName, vote_catmem_arr, (mapmem > catmem) ? mapmem : catmem);

	map_kv = CreateKeyValues("umc_rotation");
	KvCopySubkeys(umc_mapcycle, map_kv);
	// if (can_nominate)
	// {
	// 	RemovePreviousMapsFromCycle();
	// }
}

public void OnMapStart() {
	GetCurrentMap(currentMap, sizeof(currentMap));
}

//Called when a player types in chat.
//Required to handle user commands.
public Action:OnPlayerChat(client, const String:command[], argc)
{
	//Return immediately if nothing was typed.
	if (argc == 0)
	{
		return Plugin_Continue;
	}

	if (!GetConVarBool(cvar_nominate))
	{
		return Plugin_Continue;
	}

	//Get what was typed.
	decl String:text[80];
	GetCmdArg(1, text, sizeof(text));
	TrimString(text);
	decl String:arg[MAP_LENGTH];
	new next = BreakString(text, arg, sizeof(arg));

	if (StrEqual(arg, "nominate", false))
	{
		if (vote_completed || !can_nominate)
		{
			PrintToChat(client, "[UMC] %t", "No Nominate Nextmap");
		}
		else //Otherwise, let them nominate.
		{
			if (next != -1)
			{
				BreakString(text[next], arg, sizeof(arg));

				// Code based off of https://github.com/engvin/Ultimate-Mapchooser/blob/master/addons/sourcemod/scripting/umc-nominate.sp
				KvRewind(map_kv);

				// Is the attempted nomination the same as the current map?
				if (StrContains(currentMap, arg, false) != -1) {
					PrintToChat(client, "[UMC] Cannot nominate current map!");
					return Plugin_Continue;
				}

				// Create an array list of all valid maps
				ArrayList nomMapArray = view_as<ArrayList>(UMC_CreateValidMapArray(map_kv, umc_mapcycle, INVALID_GROUP, true, false));

				// If there are no results, there are no maps that can be nominated.
				if (nomMapArray.Length == 0) {
					PrintToChat(client, "[UMC] No maps to be nominated.");
					nomMapArray.Close();
					return Plugin_Continue;
				}

				// Create buffer to store map names from ArrayList
				char mapInArray[MAP_LENGTH];
				StringMap nomMapTrie = new StringMap();

				// Loop through the map array list
				for (int i; i < nomMapArray.Length; i++) {
					// Get map name from array list
					nomMapTrie = GetArrayCell(nomMapArray, i);
					GetTrieString(nomMapTrie, MAP_TRIE_MAP_KEY, mapInArray, sizeof(mapInArray));

					// If the retrieved map name has what the user is looking for, set the arg to the full map name.
					if (StrContains(mapInArray, arg, false) != -1) {
						arg = mapInArray;
						break;
					}
				}

				// Clean up!
				nomMapArray.Close();
				nomMapTrie.Close();
				KvRewind(map_kv);

				//Get the selected map.
				decl String:groupName[MAP_LENGTH], String:nomGroup[MAP_LENGTH];
				char argDisplay[MAP_LENGTH]; bool isWorkshop = false;

				if (StrContains(arg, "ws.", false) != -1)
				{
					isWorkshop = true;
					ExtractWorkshopMapNameUMC(arg, argDisplay, sizeof(argDisplay));
				}

				if (!KvFindGroupOfMap(map_kv, arg, groupName, sizeof(groupName)))
				{
					//TODO: Change to translation phrase
					PrintToChat(client, "[UMC] Could not find map \"%s\"", arg);
				}
				else
				{
					ArrayList groupNamesArray = view_as<ArrayList>(UMC_CreateValidMapGroupArray(map_kv, umc_mapcycle, true, false));

					if (groupNamesArray.Length == 0) {
						groupNamesArray.Close();
						PrintToServer("[UMC] There are no maps to be nominated.");
						return Plugin_Handled;
					}
					groupNamesArray.Close();

					KvRewind(map_kv);

					KvJumpToKey(map_kv, groupName);

					decl String:adminFlags[64];
					GetConVarString(cvar_flags, adminFlags, sizeof(adminFlags));

					KvGetString(map_kv, NOMINATE_ADMINFLAG_KEY, adminFlags, sizeof(adminFlags), adminFlags);

					KvJumpToKey(map_kv, arg);

					KvGetSectionName(map_kv, arg, sizeof(arg));

					KvGetString(map_kv, NOMINATE_ADMINFLAG_KEY, adminFlags, sizeof(adminFlags), adminFlags);

					KvGetString(map_kv, "nominate_group", nomGroup, sizeof(nomGroup), groupName);

					KvGoBack(map_kv);
					KvGoBack(map_kv);

					if (UMC_IsMapNominatedEX(arg)) {
						PrintToChatAll("[UMC] %s (%s) is already nominated!", arg, groupName);
						return Plugin_Continue;
					}

					if (view_as<ArrayList>(vote_mem_arr).Length != 0)
					{
						// Buffer to store previous map name from memory
						char prevMapName[MAP_LENGTH];
						// Check to see if map has already been played
						for (int i; i < view_as<ArrayList>(vote_mem_arr).Length; i++) {
							view_as<ArrayList>(vote_mem_arr).GetString(i, prevMapName, sizeof(prevMapName));

							if (isWorkshop)
								if (StrContains(prevMapName, argDisplay, false) != -1) {
									PrintToChat(client, "[UMC] Map has already been played! Cannot nominate map.");
									return Plugin_Handled;
								}
							else
								if (StrContains(prevMapName, arg, false) != -1) {
									PrintToChat(client, "[UMC] Map has already been played! Cannot nominate map.");
									return Plugin_Handled;
								}
						}
					}
					else
						LogUMCMessage("There are no previous maps played.");

					new clientFlags = GetUserFlagBits(client);

					//Check if admin flag set
					if (adminFlags[0] != '\0' && !(clientFlags & ReadFlagString(adminFlags)))
					{
						//TODO: Change to translation phrase
						PrintToChat(client, "[UMC] Could not find map \"%s\"", arg);
					}
					else
					{
						//Nominate it.
						UMC_NominateMap(map_kv, arg, groupName, client, nomGroup);

						char playerName[MAX_NAME_LENGTH];
						GetClientName(client, playerName, sizeof(playerName));

						//Display a message.
						if (StrContains(arg, "@ws.") != -1)
							ExtractWorkshopMapNameUMC(arg, arg, sizeof(arg));

						// Ignore this part, this is just truncating the group names for the surf server.
						char groupAbbrv[16];
						if (GetSurfGroupAbbrv(groupName, groupAbbrv, sizeof(groupAbbrv)))
							PrintToChatAll("[UMC] %s has nominated %s (%s)", playerName, arg, groupAbbrv);
						else
							PrintToChatAll("[UMC] %s has nominated %s (%s)", playerName, arg, groupName);
						LogUMCMessage("%N has nominated '%s' from group '%s'", client, arg, groupName);
					}
				}
			}
			else if (!DisplayNominationMenu(client))
			{
				PrintToChat(client, "[UMC] %t", "No Nominate Nextmap");
			}
		}
	}

	return Plugin_Continue;
}

bool IsCommandHidden(char[] command)
{
	char silentTriggers[32];
	GetSilentChatTriggers(silentTriggers, sizeof(silentTriggers));

	if (FindCharInString(silentTriggers, command[0]))
		return true;

	return false;
}

//************************************************************************************************//
//                                              SETUP                                             //
//************************************************************************************************//

//Parses the mapcycle file and returns a KV handle representing the mapcycle.
Handle:GetMapcycle()
{
	//Grab the file name from the cvar.
	decl String:filename[PLATFORM_MAX_PATH];
	GetConVarString(cvar_filename, filename, sizeof(filename));

	//Get the kv handle from the file.
	new Handle:result = GetKvFromFile(filename, "umc_rotation");

	//Log an error and return empty handle if the mapcycle file failed to parse.
	if (result == INVALID_HANDLE)
	{
		LogError("SETUP: Mapcycle failed to load!");
		return INVALID_HANDLE;
	}

	//Success!
	return result;
}

//Reloads the mapcycle. Returns true on success, false on failure.
bool:ReloadMapcycle()
{
	if (umc_mapcycle != INVALID_HANDLE)
	{
		CloseHandle(umc_mapcycle);
		umc_mapcycle = INVALID_HANDLE;
	}
	if (map_kv != INVALID_HANDLE)
	{
		CloseHandle(map_kv);
		map_kv = INVALID_HANDLE;
	}
	umc_mapcycle = GetMapcycle();

	return umc_mapcycle != INVALID_HANDLE;
}

RemovePreviousMapsFromCycle()
{
	map_kv = CreateKeyValues("umc_rotation");
	KvCopySubkeys(umc_mapcycle, map_kv);
	FilterMapcycleFromArrays(view_as<KeyValues>(map_kv), view_as<ArrayList>(vote_mem_arr), view_as<ArrayList>(vote_catmem_arr), GetConVarInt(cvar_mem_group));
}

//************************************************************************************************//
//                                            COMMANDS                                            //
//************************************************************************************************//

//sm_nominate
public Action:Command_Nominate(client, args)
{
	if (!GetConVarBool(cvar_nominate))
	{
		return Plugin_Handled;
	}

	if (vote_completed || !can_nominate)
	{
		ReplyToCommand(client, "[UMC] %t", "No Nominate Nextmap");
	}
	else //Otherwise, let them nominate.
	{
		if (args > 0)
		{
			//Get what was typed.
			decl String:arg[MAP_LENGTH];
			GetCmdArg(1, arg, sizeof(arg));
			TrimString(arg);

			// Is the attempted nomination the same as the current map?
			if (StrContains(currentMap, arg, false) != -1) {
				PrintToChat(client, "[UMC] Cannot nominate current map!");
				return Plugin_Handled;
			}

			//Get the selected map.
			decl String:groupName[MAP_LENGTH], String:nomGroup[MAP_LENGTH];
			KvRewind(map_kv);

			// Code based off of https://github.com/engvin/Ultimate-Mapchooser/blob/master/addons/sourcemod/scripting/umc-nominate.sp
			KvRewind(map_kv);

			// Create an array list of all valid maps
			ArrayList nomMapArray = view_as<ArrayList>(UMC_CreateValidMapArray(map_kv, umc_mapcycle, INVALID_GROUP, true, false));

			// If there are no results, there are no maps that can be nominated.
			if (nomMapArray.Length == 0) {
				PrintToChat(client, "[UMC] No maps to be nominated.");
				nomMapArray.Close();
				return Plugin_Handled;
			}

			// Create buffer to store map names from ArrayList
			char mapInArray[MAP_LENGTH];
			StringMap nomMapTrie = new StringMap();

			// Loop through the map array list
			for (int i; i < nomMapArray.Length; i++) {
				// Get map name from array list
				nomMapTrie = GetArrayCell(nomMapArray, i);
				GetTrieString(nomMapTrie, MAP_TRIE_MAP_KEY, mapInArray, sizeof(mapInArray));

				// If the retrieved map name has what the user is looking for, set the arg to the full map name.
				if (StrContains(mapInArray, arg, false) != -1) {
					arg = mapInArray;
					break;
				}
			}

			// Clean up!
			nomMapArray.Close();
			nomMapTrie.Close();
			KvRewind(map_kv);

			char argDisplay[MAP_LENGTH]; char argId[64]; bool isWorkshop = false;
			if (StrContains(arg, "ws.", false) != -1)
			{
				isWorkshop = true;
				ExtractWorkshopMapNameUMC(arg, argDisplay, sizeof(argDisplay));
				ExtractWorkshopMapIdUMC(arg, argId, sizeof(argId));
				LogUMCMessage("Map wanted is a workshop map.");
			}

			// Are there maps in memory?
			if (view_as<ArrayList>(vote_mem_arr).Length != 0)
			{
				LogUMCMessage("There are maps in memory!");
				// Buffer to store previous map name from memory
				char storedMapName[MAP_LENGTH];
				for (int i; i < view_as<ArrayList>(vote_mem_arr).Length; i++) {
					view_as<ArrayList>(vote_mem_arr).GetString(i, storedMapName, sizeof(storedMapName));

					LogUMCMessage("storedMapName: %s", storedMapName);

					if (isWorkshop)
					{
						LogUMCMessage("The map wanted is a workshop map.");
						char storedMapId[64];
						if (StrContains(storedMapName, "workshop/", false) != -1)
						{
							ExtractWorkshopMapIdSM(storedMapName, storedMapId, sizeof(storedMapId));
							GetMapDisplayName(storedMapName, storedMapName, sizeof(storedMapName));
							LogUMCMessage("Map stored is also a workshop map.\nstoredMapName: %s storedMapId: %s", storedMapName, storedMapId);
						}

						LogUMCMessage("argId: %s", argId);
						if (StrEqual(storedMapId, argId, false)) {
							PrintToChat(client, "[UMC] %s has already been played!", argDisplay);
							return Plugin_Handled;
						}
					}
					else
					{
						LogUMCMessage("Map wanted is not a workshop map.");
						if (StrContains(storedMapName, arg, false) != -1) {
							PrintToChat(client, "[UMC] %s has already been played!", arg);
							return Plugin_Handled;
						}
					}
				}
			}

			if (!KvFindGroupOfMap(map_kv, arg, groupName, sizeof(groupName)))
			{
				//TODO: Change to translation phrase
				ReplyToCommand(client, "[UMC] Could not find map \"%s\"", arg);
			}
			else
			{
				ArrayList groupNamesArray = view_as<ArrayList>(UMC_CreateValidMapGroupArray(map_kv, umc_mapcycle, true, false));

				if (groupNamesArray.Length == 0) {
					groupNamesArray.Close();
					PrintToServer("[UMC] There are no maps to be nominated.");
					return Plugin_Handled;
				}
				groupNamesArray.Close();

				char nomCMD[24];
				GetCmdArg(0, nomCMD, sizeof(nomCMD));

				if (UMC_IsMapNominatedEX(arg)) {
					char chatTrigger[2];
					GetCmdArgString(chatTrigger, sizeof(chatTrigger));

					if (IsCommandHidden(chatTrigger))
						if (isWorkshop)
							PrintToChat(client, "[UMC] %s (%s) is already nominated!", argDisplay, groupName);
						else
							PrintToChat(client, "[UMC] %s (%s) is already nominated!", arg, groupName);
					else
						if (isWorkshop)
							PrintToChatAll("[UMC] %s (%s) is already nominated!", argDisplay, groupName);
						else
							PrintToChatAll("[UMC] %s (%s) is already nominated!", arg, groupName);

					return Plugin_Handled;
				}

				KvRewind(map_kv);

				KvJumpToKey(map_kv, groupName);

				decl String:adminFlags[64];
				GetConVarString(cvar_flags, adminFlags, sizeof(adminFlags));

				KvGetString(map_kv, NOMINATE_ADMINFLAG_KEY, adminFlags, sizeof(adminFlags), adminFlags);

				KvJumpToKey(map_kv, arg);

				KvGetSectionName(map_kv, arg, sizeof(arg));

				KvGetString(map_kv, NOMINATE_ADMINFLAG_KEY, adminFlags, sizeof(adminFlags), adminFlags);

				KvGetString(map_kv, "nominate_group", nomGroup, sizeof(nomGroup), groupName);

				KvGoBack(map_kv);
				KvGoBack(map_kv);

				new clientFlags = GetUserFlagBits(client);

				//Check if admin flag set
				if (adminFlags[0] != '\0' && !(clientFlags & ReadFlagString(adminFlags)))
				{
					//TODO: Change to translation phrase
					ReplyToCommand(client, "[UMC] Could not find map \"%s\"", arg);
				}
				else
				{
					//Nominate it.
					UMC_NominateMap(map_kv, arg, groupName, client, nomGroup);

					char playerName[MAX_NAME_LENGTH];
					GetClientName(client, playerName, sizeof(playerName));

					// Ignore this part, this is just truncating the group names for the surf server.
					char groupAbbrv[16];
					if (GetSurfGroupAbbrv(groupName, groupAbbrv, sizeof(groupAbbrv)))
						if (isWorkshop)
							PrintToChatAll("[UMC] %s has nominated %s (%s)", playerName, argDisplay, groupAbbrv);
						else
							PrintToChatAll("[UMC] %s has nominated %s (%s)", playerName, arg, groupAbbrv);
					else //Display a message.
						if (isWorkshop)
							PrintToChatAll("[UMC] %s has nominated %s (%s)", playerName, argDisplay, groupName);
						else
							PrintToChatAll("[UMC] %s has nominated %s (%s)", playerName, arg, groupName);

					LogUMCMessage("%N has nominated '%s' from group '%s'", client, arg, groupName);
				}
			}

		}
		else if (!DisplayNominationMenu(client))
		{
			ReplyToCommand(client, "[UMC] %t", "No Nominate Nextmap");
		}
	}

	return Plugin_Handled;
}

// sm_nomlist
public Action Command_ListNominations(int client, int args)
{
	DisplayNominationList(client);
	return Plugin_Handled;
}

// sm_rp
public Action Command_ListRecentlyPlayed(int client, int args)
{
	DisplayRPList(client);
	return Plugin_Handled;
}

//************************************************************************************************//
//                                           MENU HANDLER                                         //
//************************************************************************************************//

public int NomList_Handler (Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_End)
		delete menu;

	return 0;
}

public int RPList_Handler (Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_End)
		delete menu;

	return 0;
}

//************************************************************************************************//
//                                           NOMINATIONS                                          //
//************************************************************************************************//

//Display list of nominated maps to client.
void DisplayNominationList(int client) {

	// Rewind the original map KV
	KeyValues maps = view_as<KeyValues>(map_kv);
	maps.Rewind();

	// Get a list of categories
	ArrayList catArray = view_as<ArrayList>(UMC_CreateValidMapGroupArray(maps, umc_mapcycle, false, false));

	if (catArray.Length == 0) {
		PrintToChat(client, "[UMC] There are no maps available.");
		catArray.Close();
		return;
	}

	Menu nomList = new Menu(NomList_Handler);

	if (client != 0)
		nomList.SetTitle("Nominated Maps");
	else
		nomList.Close();

	char catName[MAP_LENGTH];
	char mapName[MAP_LENGTH];
	int numNoms;
	for (int i; i < catArray.Length; i++) {
		catArray.GetString(i, catName, sizeof(catName));
		maps.JumpToKey(catName);
		maps.GotoFirstSubKey();
		do {
			maps.GetSectionName(mapName, sizeof(mapName));

			if (UMC_IsMapNominatedEX(mapName)) {
				numNoms++;
				if (client != 0) {

					char disp[MAP_LENGTH * 2];
					if (StrContains(mapName, "ws.") != -1)
					{
						FormatWorkshopUMCtoSM(mapName, mapName, sizeof(mapName));
						GetMapDisplayName(mapName, mapName, sizeof(mapName));
					}

					FormatEx(disp, sizeof(disp), "%s (%s)", mapName, catName);
					nomList.AddItem("X", disp, ITEMDRAW_DISABLED);
				}
			}
		} while (maps.GotoNextKey());
		maps.Rewind();
	}

	if (client != 0) {
		if (numNoms == 0)
			nomList.AddItem("X", "No maps nominated.", ITEMDRAW_DISABLED);
		nomList.Display(client, 20);
	}
	else
		PrintToServer("No maps nominated.");

	catArray.Close();
}

void DisplayRPList(int client)
{
	ArrayList voteMemory = view_as<ArrayList>(CloneHandle(vote_mem_arr));
	Menu recentlyPlayed = new Menu(RPList_Handler);
	recentlyPlayed.SetTitle("Recently Played Maps");

	if (voteMemory.Length == 0)
		recentlyPlayed.AddItem("X", "There are no recently played maps!", ITEMDRAW_DISABLED);
	else
	{
		char mapInfo[MAP_LENGTH]; char mapGroup[MAP_LENGTH];
		for (int i; i < voteMemory.Length; i++)
		{
			voteMemory.GetString(i, mapInfo, sizeof(mapInfo));
			UMC_GetMapGroup(umc_mapcycle, mapInfo, mapGroup, sizeof(mapGroup));

			if (StrContains(mapInfo, "workshop/") != -1)
				GetMapDisplayName(mapInfo, mapInfo, sizeof(mapInfo));

			if (mapGroup[0] != '\0')
				FormatEx(mapInfo, sizeof(mapInfo), "%s (%s)", mapInfo, mapGroup);

			recentlyPlayed.AddItem("X", mapInfo, ITEMDRAW_DISABLED);
		}
	}

	recentlyPlayed.Display(client, 0);
}

// Checks every group to see if a map is already nominated.
bool UMC_IsMapNominatedEX (char mapName[MAP_LENGTH])
{
	char workshopLink[MAP_LENGTH]; char mapDisplay[MAP_LENGTH];
	if (StrContains(mapName, "ws") != -1)
	{
		FormatWorkshopUMCtoSM(mapName, workshopLink, sizeof(workshopLink));
		GetMapDisplayName(workshopLink, mapDisplay, sizeof(mapDisplay));
	}
	else
		GetMapDisplayName(mapName, mapDisplay, sizeof(mapDisplay));

	map_kv = CreateKeyValues("umc_rotation");
	KvCopySubkeys(umc_mapcycle, map_kv);

	ArrayList groupNamesArray = view_as<ArrayList>(UMC_CreateValidMapGroupArray(map_kv, umc_mapcycle, true, false));

	if (!groupNamesArray) {
		PrintToServer("UMC_IsMapNominatedEX: Unable to create group name array.");
		return false;
	}

	char groupArrayName[MAP_LENGTH];
	for (int j; j < groupNamesArray.Length; j++) {
		groupNamesArray.GetString(j, groupArrayName, sizeof(groupArrayName));

		if (UMC_IsMapNominated(mapDisplay, groupArrayName))
		{
			groupNamesArray.Close();
			return true;
		}
	}
	groupNamesArray.Close();
	return false;
}

//Displays a nomination menu to the given client.
bool:DisplayNominationMenu(client)
{
	if (!can_nominate)
	{
		return false;
	}

	LogUMCMessage("%N wants to nominate a map.", client);

	//Build the menu
	new Handle:menu = GetConVarBool(cvar_nominate_tiered) ? BuildTieredNominationMenu(client) : BuildNominationMenu(client);

	//Display the menu if the menu was built successfully.
	if (menu != INVALID_HANDLE)
	{
		return DisplayMenu(menu, client, GetConVarInt(cvar_nominate_time));
	}

	return false;
}

//Creates and returns the Nomination menu for the given client.
Handle:BuildNominationMenu(client, const String:cat[]=INVALID_GROUP)
{
	//Initialize the menu
	new Handle:menu = CreateMenu(Handle_NominationMenu, MenuAction_Display);

	//Set the title.
	SetMenuTitle(menu, "%T", "Nomination Menu Title", LANG_SERVER);

	if (!StrEqual(cat, INVALID_GROUP))
	{
		//Make it so we can return to the previous menu.
		SetMenuExitBackButton(menu, true);
	}

	KvRewind(map_kv);

	//Copy over for template processing
	new Handle:dispKV = CreateKeyValues("umc_mapcycle");
	KvCopySubkeys(map_kv, dispKV);

	//Get map array.
	new Handle:mapArray = UMC_CreateValidMapArray(map_kv, umc_mapcycle, cat, true, false);

	if (GetConVarBool(cvar_sort))
	{
		SortMapTrieArray(mapArray);
	}

	new size = GetArraySize(mapArray);
	if (size == 0)
	{
		LogError("No maps available to be nominated.");
		CloseHandle(menu);
		CloseHandle(mapArray);
		CloseHandle(dispKV);
		return INVALID_HANDLE;
	}

	//Variables
	new numCells = ByteCountToCells(MAP_LENGTH);
	nom_menu_groups[client] = CreateArray(numCells);
	nom_menu_nomgroups[client] = CreateArray(numCells);
	new Handle:menuItems = CreateArray(numCells);
	new Handle:menuItemDisplay = CreateArray(numCells);
	decl String:display[MAP_LENGTH];
	new Handle:mapTrie = INVALID_HANDLE;
	decl String:mapBuff[MAP_LENGTH], String:groupBuff[MAP_LENGTH];
	decl String:group[MAP_LENGTH];

	decl String:dAdminFlags[64], String:gAdminFlags[64], String:mAdminFlags[64];
	GetConVarString(cvar_flags, dAdminFlags, sizeof(dAdminFlags));
	new clientFlags = GetUserFlagBits(client);

	// Item Draw Array
	ArrayList menuItemDraw = CreateArray();

	for (new i = 0; i < size; i++)
	{
		mapTrie = GetArrayCell(mapArray, i);
		GetTrieString(mapTrie, MAP_TRIE_MAP_KEY, mapBuff, sizeof(mapBuff));
		GetTrieString(mapTrie, MAP_TRIE_GROUP_KEY, groupBuff, sizeof(groupBuff));

		KvJumpToKey(map_kv, groupBuff);

		KvGetString(map_kv, "nominate_group", group, sizeof(group), INVALID_GROUP);

		if (StrEqual(group, INVALID_GROUP))
		{
			strcopy(group, sizeof(group), groupBuff);
		}

		KvGetString(map_kv, NOMINATE_ADMINFLAG_KEY, gAdminFlags, sizeof(gAdminFlags), dAdminFlags);

		KvJumpToKey(map_kv, mapBuff);

		KvGetString(map_kv, NOMINATE_ADMINFLAG_KEY, mAdminFlags, sizeof(mAdminFlags), gAdminFlags);

		//Check if admin flag set
		if (mAdminFlags[0] != '\0')
		{
			//Check if player has admin flag
			if (!(clientFlags & ReadFlagString(mAdminFlags)))
			{
				continue;
			}
		}

		//Get the name of the current map.
		KvGetSectionName(map_kv, mapBuff, sizeof(mapBuff));

		//Get the display string.
		UMC_FormatDisplayString(display, sizeof(display), dispKV, mapBuff, groupBuff);

		KvRewind(map_kv);

		ArrayList groupNamesArray = view_as<ArrayList>(UMC_CreateValidMapGroupArray(map_kv, umc_mapcycle, true, false));

		if (groupNamesArray.Length == 0) {
			LogError("No maps available to nominate.");
			groupNamesArray.Close();
			menuItems.Close();
			menuItemDisplay.Close();
			menuItemDraw.Close();
			mapArray.Close();
			menu.Close();
			dispKV.Close();
			KvRewind(map_kv);
			return INVALID_HANDLE;
		}

		if (StrContains(display, "ws.", false) != -1)
		{
			char splitLink[2][32];
			ExplodeString(display, "@ws.ugc", splitLink, 2, 32);
			FormatEx(display, sizeof(display), "%s", splitLink[0]);
		}

		// Buffer to store previous map name from memory
		char prevMapName[MAP_LENGTH];
		bool recentlyPlayed = false;

		// Check to see if the current map is a workshop map.
		bool isCurWorkshop;
		char currentMapId[MAP_LENGTH];
		if (StrContains(currentMap, "workshop/") != -1)
		{
			// It's a workshop map, let's grab it's id.
			isCurWorkshop = true;
			ExtractWorkshopMapIdSM(currentMap, currentMapId, sizeof(currentMapId));
		}

		char prevMapId[MAP_LENGTH];
		// Check the previously played maps to see what's there
		for (int j; j < view_as<ArrayList>(vote_mem_arr).Length; j++) {
			// Grab the previous map name.
			view_as<ArrayList>(vote_mem_arr).GetString(j, prevMapName, sizeof(prevMapName));

			// If the previous map name was a workshop map, we need to grab it's ID.
			bool isPrevWorkshop = false;
			if (StrContains(prevMapName, "workshop/") != -1)
			{
				ExtractWorkshopMapIdSM(prevMapName, prevMapId, sizeof(prevMapId));
				isPrevWorkshop = true;
			}

			// Now we need to check to see if the map we're adding was recently played.
			if (isPrevWorkshop) // Check if past map was a workshop map.
			{
				if (StrContains(mapBuff, prevMapId) != -1)
				{
					//Check to see if whatever map we're adding has the workshop id in it.
					recentlyPlayed = true;
					break;
				}
			}
			else
			{
				// It's not a workshop map, just compare the two names.
				if (StrEqual(mapBuff, prevMapName, false)) {
					recentlyPlayed = true;
					break;
				}
			}

		}

		// ugh long if trees, probably a better way to do this?
		// Is the map currently nominated?
		if (UMC_IsMapNominatedEX(mapBuff)) {
			menuItemDraw.Push(ITEMDRAW_DISABLED);
			FormatEx(display, sizeof(display), "%s (Nominated)", display);
		}
		// Is the map the current map? (Current map is not workshop.)
		else if (StrEqual(mapBuff, currentMap, false) && !isCurWorkshop) {
			menuItemDraw.Push(ITEMDRAW_DISABLED);
			FormatEx(display, sizeof(display), "%s (Current Map)", display);
		}
		// Is the map the current map? (Current map IS workshop.)
		else if (StrContains(mapBuff, currentMapId) != -1 && isCurWorkshop)
		{
			menuItemDraw.Push(ITEMDRAW_DISABLED);
			FormatEx(display, sizeof(display), "%s (Current Map)", display);
		}
		// Was the map recently played?
		else if (recentlyPlayed) {
			menuItemDraw.Push(ITEMDRAW_DISABLED);
			FormatEx(display, sizeof(display), "%s (Recently Played)", display);
		}
		// Valid map to choose for nomination.
		else
			menuItemDraw.Push(ITEMDRAW_DEFAULT);

		//Add map data to the arrays.
		PushArrayString(menuItems, mapBuff);
		PushArrayString(menuItemDisplay, display);
		PushArrayString(nom_menu_groups[client], groupBuff);
		PushArrayString(nom_menu_nomgroups[client], group);

		KvRewind(map_kv);
	}

	//Add all maps from the nominations array to the menu.
	AddArrayToMenu(menu, menuItems, menuItemDisplay, view_as<Handle>(menuItemDraw));

	//No longer need the arrays.
	CloseHandle(menuItems);
	CloseHandle(menuItemDisplay);
	ClearHandleArray(mapArray);
	CloseHandle(mapArray);

	menuItemDraw.Close();

	//Or the display KV
	CloseHandle(dispKV);

	//Success!
	return menu;
}

//Creates the first part of a tiered Nomination menu.
Handle:BuildTieredNominationMenu(client)
{
	//Initialize the menu
	new Handle:menu = CreateMenu(Handle_TieredNominationMenu, MenuAction_Display);

	KvRewind(map_kv);

	//Get group array.
	new Handle:groupArray = UMC_CreateValidMapGroupArray(map_kv, umc_mapcycle, true, false);

	new size = GetArraySize(groupArray);

	//Log an error and return nothing if the number of maps available to be nominated
	if (size == 0)
	{
		LogError("No maps available to be nominated.");
		CloseHandle(menu);
		CloseHandle(groupArray);
		return INVALID_HANDLE;
	}

	//Variables
	decl String:dAdminFlags[64], String:gAdminFlags[64], String:mAdminFlags[64];
	GetConVarString(cvar_flags, dAdminFlags, sizeof(dAdminFlags));
	new clientFlags = GetUserFlagBits(client);

	new Handle:menuItems = CreateArray(ByteCountToCells(MAP_LENGTH));
	decl String:groupName[MAP_LENGTH];
	new bool:excluded = true;
	for (new i = 0; i < size; i++)
	{
		GetArrayString(groupArray, i, groupName, sizeof(groupName));

		KvJumpToKey(map_kv, groupName);

		KvGetString(map_kv, NOMINATE_ADMINFLAG_KEY, gAdminFlags, sizeof(gAdminFlags), dAdminFlags);

		KvGotoFirstSubKey(map_kv);
		do
		{
			KvGetString(map_kv, NOMINATE_ADMINFLAG_KEY, mAdminFlags, sizeof(mAdminFlags), gAdminFlags);

			//Check if admin flag set
			if (mAdminFlags[0] != '\0')
			{
				//Check if player has admin flag
				if (!(clientFlags & ReadFlagString(mAdminFlags)))
				{
					continue;
				}
			}

			excluded = false;
			break;
		}
		while (KvGotoNextKey(map_kv));

		if (!excluded)
		{
			PushArrayString(menuItems, groupName);
		}

		KvGoBack(map_kv);
		KvGoBack(map_kv);
	}

	//Add all maps from the nominations array to the menu.
	AddArrayToMenu(menu, menuItems);

	//No longer need the arrays.
	CloseHandle(menuItems);
	CloseHandle(groupArray);

	//Success!
	return menu;
}

// Called when the client has picked an item in the nomination menu.
public Handle_NominationMenu(Handle:menu, MenuAction:action, client, param2)
{
	switch (action)
	{
		case MenuAction_Select: //The client has picked something.
		{
			//Get the selected map.
			decl String:map[MAP_LENGTH], String:group[MAP_LENGTH], String:nomGroup[MAP_LENGTH];
			GetMenuItem(menu, param2, map, sizeof(map));
			GetArrayString(nom_menu_groups[client], param2, group, sizeof(group));
			GetArrayString(nom_menu_nomgroups[client], param2, nomGroup, sizeof(nomGroup));
			KvRewind(map_kv);

			// Check if map is already nominated
			ArrayList groupNamesArray = view_as<ArrayList>(UMC_CreateValidMapGroupArray(map_kv, umc_mapcycle, true, false));

			if (groupNamesArray.Length == 0) {
				LogError("No maps available to nominate.");
				groupNamesArray.Close();
				menu.Close();
				KvRewind(map_kv);
				return 0;
			}
			groupNamesArray.Close();

			if (UMC_IsMapNominatedEX(map)) {
				PrintToChat(client, "[UMC] %s (%s) is already nominated!", map, group);
				return 0;
			}

			//Nominate it.
			UMC_NominateMap(map_kv, map, group, client, nomGroup);

			char playerName[MAX_NAME_LENGTH];
			GetClientName(client, playerName, sizeof(playerName));

			//Display a message.
			// Ignore this part, this is just truncating the group names for the surf server.

			if (StrContains(map, "ws.") != -1)
				ExtractWorkshopMapNameUMC(map, map, sizeof(map));

			char groupAbbrv[16];
			if (StrContains(nomGroup, "Com") != -1) {
				FormatEx(groupAbbrv, sizeof(groupAbbrv), "Combat");
				PrintToChatAll("[UMC] %s has nominated %s (%s)", playerName, map, groupAbbrv);
			}
			else if (StrContains(nomGroup, "Skil") != -1) {
				FormatEx(groupAbbrv, sizeof(groupAbbrv), "Skill");
				PrintToChatAll("[UMC] %s has nominated %s (%s)", playerName, map, groupAbbrv);
			}
			else if (StrContains(nomGroup, "Are") != -1) {
				FormatEx(groupAbbrv, sizeof(groupAbbrv), "Arena");
				PrintToChatAll("[UMC] %s has nominated %s (%s)", playerName, map, groupAbbrv);
			}
			else
				PrintToChatAll("[UMC] %s has nominated %s (%s)", playerName, map, group);

			LogUMCMessage("%N has nominated '%s' from group '%s'", client, map, group);

			//Close handles for stored data for the client's menu.
			CloseHandleEx(nom_menu_groups[client]);
			CloseHandleEx(nom_menu_nomgroups[client]);
		}
		case MenuAction_End: //The client has closed the menu.
		{
			//We're done here.
			CloseHandle(menu);
		}
		case MenuAction_Display: //the menu is being displayed
		{
			new Handle:panel = Handle:param2;
			decl String:buffer[255];
			FormatEx(buffer, sizeof(buffer), "%T", "Nomination Menu Title", client);
			SetPanelTitle(panel, buffer);
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				//Build the menu
				new Handle:newmenu = BuildTieredNominationMenu(client);

				//Display the menu if the menu was built successfully.
				if (newmenu != INVALID_HANDLE)
				{
					DisplayMenu(newmenu, client, GetConVarInt(cvar_nominate_time));
				}
			}

			//Close handles for stored data for the client's menu.
			CloseHandleEx(nom_menu_groups[client]);
			CloseHandleEx(nom_menu_nomgroups[client]);
		}
	}
}

//Handles the first-stage tiered nomination menu.
public Handle_TieredNominationMenu(Handle:menu, MenuAction:action, client, param2)
{
	if (action == MenuAction_Select)
	{
		decl String:cat[MAP_LENGTH];
		GetMenuItem(menu, param2, cat, sizeof(cat));

		//Build the menu
		new Handle:newmenu = BuildNominationMenu(client, cat);

		//Display the menu if the menu was built successfully.
		if (newmenu != INVALID_HANDLE)
		{
			DisplayMenu(newmenu, client, GetConVarInt(cvar_nominate_time));
		}
	}
	else
	{
		Handle_NominationMenu(menu, action, client, param2);
	}
}

//************************************************************************************************//
//                                   ULTIMATE MAPCHOOSER EVENTS                                   //
//************************************************************************************************//

//Called when UMC requests that the mapcycle should be reloaded.
public UMC_RequestReloadMapcycle()
{
	can_nominate = ReloadMapcycle();

	if (can_nominate)
	{
		RemovePreviousMapsFromCycle();
	}
}


//Called when UMC has set a next map.
public UMC_OnNextmapSet(Handle:kv, const String:map[], const String:group[], const String:display[])
{
	vote_completed = true;
}

//Called when UMC has extended a map.
public UMC_OnMapExtended()
{
	vote_completed = false;
}

//Called when UMC requests that the mapcycle is printed to the console.
public UMC_DisplayMapCycle(client, bool:filtered)
{
	PrintToConsole(client, "Module: Nominations");

	if (filtered)
	{
		PrintToConsole(client, "Maps available to nominate:");
		new Handle:filteredMapcycle = UMC_FilterMapcycle(map_kv, umc_mapcycle, true, false);

		PrintKvToConsole(filteredMapcycle, client);
		CloseHandle(filteredMapcycle);
		PrintToConsole(client, "Maps available for map change (if nominated):");

		filteredMapcycle = UMC_FilterMapcycle(map_kv, umc_mapcycle, true, true);
		PrintKvToConsole(filteredMapcycle, client);
		CloseHandle(filteredMapcycle);
	}
	else
	{
		PrintKvToConsole(umc_mapcycle, client);
	}
}

//************************************************************************************************//
//                                   	  MISC FUNCTIONS    			                          //
//************************************************************************************************//

/**
 * 	Strips the surf map groups of "surf"
 *
 *  @param groupName		Group name
 *  @param output			Output buffer.
 *  @param len				Buffer length.
 *
 *  @return					True if stripped, false if not.
 */
bool GetSurfGroupAbbrv(char[] groupName, char[] output, int len)
{
	if (StrContains(groupName, "Combat") != -1)
	{
		FormatEx(output, len, "Combat");
		return true;
	}
	else if (StrContains(groupName, "Skill") != -1)
	{
		FormatEx(output, len, "Skill");
		return true;
	}
	else if (StrContains(groupName, "Arena") != -1)
	{
		FormatEx(output, len, "Arena");
		return true;
	}

	return false;
}
