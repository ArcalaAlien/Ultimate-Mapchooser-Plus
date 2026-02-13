#if defined __umc_workshop_stocks_included
	#endinput
#endif

#define __umc_workshop_stocks_included

#include <umc-core>
#include <umc_utils>

/**
 * Change ID format from UMC to Sourcemod
 * 
 * @param input			UMC Format mapname@ws.ugc<mapid>
 * @param output		Buffer to store Sourcemod format workshop/mapname.ugc<mapid>
 * @param len			Length of output buffer
 * 
 * @noreturn
 */
stock void FormatWorkshopUMCtoSM(const char[] input, char[] output, int len)
{
	char splitOld[2][MAP_LENGTH];
	ExplodeString(input, "@ws.", splitOld, 2, MAP_LENGTH);
	FormatEx(output, len, "workshop/%s.%s", splitOld[0], splitOld[1]);
}

/**
 * Change ID format from Sourcemod to UMC
 * 
 * @param input			Sourcemod format workshop/mapname.ugc<mapid>
 * @param output		Buffer to store UMC Format mapname@ws.ugc<mapid>
 * @param len			Length of output buffer
 * 
 * @noreturn
 */
stock void FormatWorkshopSMtoUMC(const char[] input, char[] output, int len)
{
	char slashExplode[2][MAP_LENGTH]; char ugcExplode[2][MAP_LENGTH];
	ExplodeString(input, "/", slashExplode, 2, MAP_LENGTH);
	ExplodeString(slashExplode[1], ".ugc", ugcExplode, 2, MAP_LENGTH);
	FormatEx(output, len, "%s@ws.ugc%s", ugcExplode[0], ugcExplode[1]);
}

/**
 *  Get the map name from UMC format
 * 
 *  @param input 	Workshop link (UMC Format) mapname@ws.ugc00000000
 *  @param output 	map name
 *  @param len 		length of buffer.
 * 
 *  @noreturn
 */
stock void ExtractWorkshopMapNameUMC(const char[] input, char[] output, int len)
{
	char inputSplit[2][MAP_LENGTH];
	ExplodeString(input, "@ws.ugc", inputSplit, 2, MAP_LENGTH);
	strcopy(output, len, inputSplit[0]);
}

/**
 * Get map name from SM format
 * 
 * @param input			Sourcemod format workshop/mapname.ugc<mapid>
 * @param output		Buffer to store map name
 * @param len			Length of output buffer
 * 
 * @noreturn
 */
stock void ExtractWorkshopMapNameSM(const char[] input, char[] output, int len)
{
	char slashExplode[2][MAP_LENGTH]; char ugcExplode[2][MAP_LENGTH];
	ExplodeString(input, "/", slashExplode, 2, MAP_LENGTH);
	ExplodeString(slashExplode[1], ".ugc", ugcExplode, 2, MAP_LENGTH);
	strcopy(output, len, ugcExplode[0]);
}

/**
 *  Get the map id from the UMC workshop link.
 * 
 *  @param input 	Workshop link (UMC Format) mapname@ws.ugc00000000
 *  @param output 	map id
 *  @param len 		length of buffer.
 * 
 *  @noreturn
 */
stock void ExtractWorkshopMapIdUMC(const char[] input, char[] output, int len)
{
	char inputSplit[2][64];
	ExplodeString(input, "@ws.ugc", inputSplit, 2, 64);
	strcopy(output, len, inputSplit[1]);
}

/**
 *  Get the map id from the workshop link.
 * 
 *  @param input 	Workshop link (Steam Format) workshop/00000000
 *  @param output 	map id
 *  @param len 		length of buffer.
 * 
 *  @noreturn
 */
stock void ExtractWorkshopMapIdSM(const char[] input, char[] output, int len)
{
	char inputSplit[2][64];
	ExplodeString(input, ".ugc", inputSplit, 2, 64);
	strcopy(output, len, inputSplit[1]);
}

/**
 *  Check if the input string is a workshop map.
 * 
 *  @param input 	String to check
 *  @return 		True if it's a workshop map, false otherwise.
 */
stock bool IsWorkshopMap(const char[] input)
{
	return (StrContains(input, "@ws.ugc") != -1 ||
			StrContains(input, "workshop/") != -1);
}