/**
 *  Builds the vote menu for map voting.
 *  I'm keeping the original function sigature for now,
 *  but I will eventually rework the entire system to
 *  work with modern SourceMod syntax.
 * 
 *  @param voteManagerH					Handle to the vote manager trie.
 *  @param resultH						Handle to the array list that will be filled with the
 *  @param currentRotationH					Handle to the original mapcycle KeyValues.
 *  @param currentMapcycleH				Handle to the current mapcycle KeyValues.
 *  @param scrambleVote					Whether to scramble the vote menu or not.
 *  @param extendOption					Do we add the extend option?
 *  @param dontChangeOption				Do we add the don't change option?
 *  @param ignoreDuplicateNominations	Whether to ignore duplicate nominations in the vote menu or not.
 *  @param nominationsRestricted    		Whether to limit the amount of nominations added to the vote by the maps_invote setting for the category or not.
 *  @param ignoreInVoteSetting			Whether to ignore the maps_invote setting for categories
 *  @param applyExclusionRules			Calls IsValidMap()
 *  @param fromCategory					If specified, only build the vote menu with maps from this category.
 *	
 *  @return 'BuildOptionsError_Success' if we were able to create the vote menu. Otherwise, an appropriate error code is returned and an error message is logged.
*/
UMC_BuildOptionsError BuildMapVoteItemsEx(Handle voteManagerH, 
                                          Handle resultH, Handle currentRotationH,
                                          Handle currentMapcycleH, bool scrambleVote, 
                                          bool extendOption, bool dontChangeOption, 
                                          bool ignoreDuplicateNominations=false, 
                                          bool nominationsRestricted=false,
                                          bool ignoreInVoteSetting=false, 
                                          bool applyExclusionRules=true, 
                                          const char[] fromCategory="") {
	if (voteManagerH == INVALID_HANDLE || 
		resultH == INVALID_HANDLE ||
		currentRotationH == INVALID_HANDLE ||
		currentMapcycleH == INVALID_HANDLE) {
		LogError("VOTING: Cannot build map vote menu, invalid parameters were provided.");
		return BuildOptionsError_InvalidParameters;
	}

	StringMap voteManager = view_as<StringMap>(voteManagerH);
	ArrayList result = view_as<ArrayList>(resultH);
	KeyValues currentRotation = view_as<KeyValues>(currentRotationH);
	KeyValues currentMapcycle = view_as<KeyValues>(currentMapcycleH);

	currentRotation.Rewind(); //rewind original
	KeyValues copyKV = new KeyValues("umc_rotation");
	copyKV.Import(currentRotation);

	if (applyExclusionRules)
		FilterMapcycleEx(copyKV, currentMapcycle, .deleteEmptyGroups=false);

	//Log an error and return nothing if it cannot find a category.
	if (!copyKV.GotoFirstSubKey())
	{
		LogError("VOTING: No map groups found in rotation. Vote menu was not built.");
		copyKV.Close();
		return BuildOptionsError_NoMapGroups;
	}

	ClearVoteArrays(voteManagerH);

	//Determine how we're logging
	bool verboseLogs = view_as<ConVar>(cvar_logging).BoolValue;

	//Buffers
	char mapName[MAP_LENGTH],
		 categoryName[MAP_LENGTH],
		 mapDisplay[MAP_LENGTH],
		 displayTemplate[MAP_LENGTH],
		 nomCategory[MAP_LENGTH];

	int numNominations = 0,
		mapsNeededFromCategory = 0,
		nominationsFetched = 0,
		mapsInVote = 0,
		nextIndex = 0,
		tierAmount = view_as<ConVar>(cvar_vote_tieramount).IntValue;

    Handle mapVoteH;
    GetTrieValue(voteManagerH, "map_vote", mapVoteH);
	ArrayList nominationsFromCategory,
			  tempCategoryNominations,
			  nameArray 				= new ArrayList(ByteCountToCells(MAP_LENGTH)),
			  weightArray 				= new ArrayList(),
              gatheredMapsArray 		= new ArrayList(),
			  mapVote 					= view_as<ArrayList>(mapVoteH),
			  mapVoteDisplay 			= new ArrayList(ByteCountToCells(MAP_LENGTH));
	KeyValues nominationKV;

	do {
		if (fromCategory[0]){
			copyKV.GetSectionName(categoryName, sizeof(categoryName));

			if (!StrEqual(categoryName, fromCategory))
				continue;
		}

		WeightMapGroup(view_as<Handle>(copyKV), view_as<Handle>(currentMapcycle));
		copyKV.GetSectionName(categoryName, sizeof(categoryName));
		copyKV.GetString("display-template", displayTemplate, sizeof(displayTemplate), "{MAP}");

		if (applyExclusionRules)
		{
			tempCategoryNominations = view_as<ArrayList>(GetCatNominations(categoryName));
			nominationsFromCategory = view_as<ArrayList>(FilterNominationsArray(tempCategoryNominations));
			tempCategoryNominations.Close();
		}
		else
			nominationsFromCategory = view_as<ArrayList>(GetCatNominations(categoryName));

		numNominations = nominationsFromCategory.Length;
		mapsInVote = (ignoreInVoteSetting && tierAmount > 0) ? tierAmount : copyKV.GetNum("maps_invote", 1);
	
		if (verboseLogs)
		{
			if (ignoreInVoteSetting)
				LogUMCMessage("VOTE MENU: (Verbose) Second stage tiered vote. See cvar \"sm_umc_vote_tieramount.\"");
			
			LogUMCMessage("VOTE MENU: (Verbose) Fetching %i maps from group '%s'", mapsInVote, categoryName);
		}

		mapsNeededFromCategory = mapsInVote - numNominations;

		// If mapsNeededFromCategory is negative that means
		// that all map slots are taken by nominations.
		//
		// nominationsRestricted lets us know if we should
		// limit the amount of nominations to add by the
		// maps_invote setting for the category.
		nominationKV = new KeyValues("umc_mapcycle");
		if (mapsNeededFromCategory < 0 && nominationsRestricted) {
			//////
			//The piece of code inside this block is for the case where the current category's
			//nominations exceeds it's number of maps allowed in the vote.
			//
			//In order to solve this problem, we first fetch all nominations where the map has
			//appropriate min and max players for the amount of players on the server, and then
			//randomly pick from this pool based on the weights if the maps, until the number
			//of maps in the vote from this category is reached.
			//////
			if (verboseLogs)
				LogUMCMessage(
					"VOTE MENU: (Verbose) Number of nominations (%i) exceeds allowable maps in vote for the map group '%s'. Limiting nominated maps to %i. (See cvar \"sm_umc_nominate_strict\")",
					numNominations, categoryName, mapsInVote
				);

			// Here we'll check to see if there
			// are nominations to parse.
			nominationsFetched = 0;
			if (numNominations > 0) {
				for (int i = 0; i < nominationsFromCategory.Length; i++) {
					StringMap nomination = view_as<StringMap>(nominationsFromCategory.Get(i));
                    nomination.GetString(MAP_TRIE_MAP_KEY, mapName, sizeof(mapName));

                    if (ignoreDuplicateNominations && FindStringInMapArray(mapName, MAP_TRIE_MAP_KEY, mapVote) != -1) {
                        if (verboseLogs)
                            LogUMCMessage(
                                "VOTE MENU: (Verbose) Skipping nominated map '%s' from map group '%s' because it is already in the vote.",
                                mapName, categoryName
                            );

                        continue;
                    }

					nominationKV = null;
					nomination.GetValue("mapcycle", view_as<Handle>(nominationKV));
					if (nominationKV == null ||
						nominationKV == INVALID_HANDLE) {
						if (verboseLogs)
							LogUMCMessage(
								"VOTE MENU: (Verbose) Skipping nominated map '%s' from map group '%s' because it has an invalid mapcycle.",
								mapName, categoryName
							);
					}

					nameArray.Push(mapName);
					weightArray.Push(GetMapWeight(view_as<Handle>(nominationKV), mapName, categoryName));
					
					// Here we'll fill this array with
					// nominations. This is not the result
					// array but a temporary array to store
					// all of our nominations in before
					// processing regular maps. 
					gatheredMapsArray.Push(nomination);
					nominationsFetched++;
				}
				int spotsInVoteLeft = (mapsInVote < nominationsFetched) ? mapsInVote : nominationsFetched;

                // We were able to grab some valid
                // nominations!
                if (gatheredMapsArray.Length != 0) {
					char nomGroupBuffer[MAP_LENGTH];
					nextIndex = 0;

					for (int i = 0; i < spotsInVoteLeft; i++) {
						GetWeightedRandomSubKey(mapName, sizeof(mapName), weightArray, nameArray, nextIndex);
						StringMap nomination = view_as<StringMap>(gatheredMapsArray.Get(nextIndex));
						nomination.GetValue("mapcycle", nominationKV);
						nomination.GetString("nom_group", nomGroupBuffer, sizeof(nomGroupBuffer));

						// Set up what nextIndex of the vote we'll add
						// this nomination to.
						nextIndex = GetNextMenuIndex(mapsInVote, scrambleVote);

						// Handle the map display string.
						KeyValues displayMapCycle = new KeyValues("umc_mapcycle");
						displayMapCycle.Import(nominationKV);
					GetMapDisplayStringEx(displayMapCycle, nomGroupBuffer, mapName, displayTemplate, mapDisplay, sizeof(mapDisplay));
						mapInfoCycle.Import(nominationKV);
						mapInfo.SetValue("mapcycle", view_as<Handle>(mapInfoCycle));
					
						InsertArrayCell(mapVote, nextIndex, view_as<Handle>(mapInfo));
						InsertArrayString(mapVoteDisplay, nextIndex, mapDisplay);
						mapsInVote++;

						copyKV.DeleteKey(mapName);

						nameArray.Erase(nextIndex);
						weightArray.Erase(nextIndex);
						gatheredMapsArray.Erase(nextIndex);

						if (verboseLogs)
							LogUMCMessage(
								"VOTE MENU: (Verbose) Added nominated map '%s' to the vote from group '%s'.",
								mapName, categoryName
							);
					}

					if (nominationsFromCategory != null)
						nominationsFromCategory.Close();
					
					mapsNeededFromCategory = mapsInVote - numNominations;
				} else {
					// Otherwise we handle the nominations we do have,
					// and fill the rest of the open vote positions
					// with maps from the current category in the
					// mapcycle.
					StringMap nomination;
					char nomGroupBuffer[MAP_LENGTH]; 
					for (int i; i < nominationsFromCategory.Length; i++) {
						nomination = view_as<StringMap>(nominationsFromCategory.Get(i));
						nomination.GetString(MAP_TRIE_MAP_KEY, mapName, sizeof(mapName));

						if (ignoreDuplicateNominations && FindStringInMapArray(mapName, MAP_TRIE_MAP_KEY, mapVote) != -1) {
							if (verboseLogs)
								LogUMCMessage(
									"VOTE MENU: (Verbose) Skipping nominated map '%s' from map group '%s' because it is already in the vote.",
									mapName, categoryName
								);

							continue;
						}

						nomination.GetValue("mapcycle", nominationKV);
						nomination.GetString("nom_group", nomGroupBuffer, sizeof(nomGroupBuffer));

						// Handle the map display string.
						KeyValues displayMapCycle = new KeyValues("umc_mapcycle");
						displayMapCycle.Import(nominationKV);
						GetMapDisplayStringEx(displayMapCycle, nomGroupBuffer, mapName, displayTemplate, mapDisplay, sizeof(mapDisplay));
						mapInfo.SetValue(MAP_TRIE_MAP_KEY, mapName);
						mapInfo.SetValue(MAP_TRIE_GROUP_KEY, categoryName);

						KeyValues mapInfoCycle = new KeyValues("umc_mapcycle");
						mapInfoCycle.Import(nominationKV);
						mapInfo.SetValue("mapcycle", view_as<Handle>(mapInfoCycle));
					
						InsertArrayCell(mapVote, nextIndex, view_as<Handle>(mapInfo));
						InsertArrayString(mapVoteDisplay, nextIndex, mapDisplay);
						mapsInVote++;

						copyKV.DeleteKey(mapName);
						if (verboseLogs)
							LogUMCMessage(
								"VOTE MENU: (Verbose) Nominated map '%s' from group '%s' was added to the vote.",
								mapName, categoryName
							);
					} // end of nomination loop

					if (nominationsFromCategory != null)
						nominationsFromCategory.Close();
				}
			} 
		} // Here we've finally handled adding all nominations.

		if (verboseLogs) {
			LogUMCMessage(
				"VOTE MENU: (Verbose) Finished parsing nominations for map group '%s'",
				categoryName
			);

			if (mapsNeededFromCategory > 0)
				LogUMCMessage(
					"VOTE MENU: (Verbose) Fetching %i maps from group '%s' to fill remaining vote slots.",
					mapsNeededFromCategory, categoryName
				);
		}

		int nomIndex = 0;
		nextIndex = 0;
		while (mapsNeededFromCategory > 0) {
			if (!GetRandomMap(copyKV, mapName, sizeof(mapName))) {
				if (verboseLogs)
					LogUMCMessage(
						"VOTE MENU: (Verbose) No more maps to add in group '%s'.",
						categoryName
					);
				
				break;
			}

			if (ignoreDuplicateNominations && FindStringInMapArray(mapName, MAP_TRIE_MAP_KEY, mapVote) != -1) {
				if (verboseLogs)
					LogUMCMessage(
						"VOTE MENU: (Verbose) Skipping map '%s' from group '%s' because it is already in the vote.",
						mapName, categoryName
					);

				continue;
			}

			// Remove nomination if it's in the array because
			// we've already handled it.
			nomIndex = FindNominationIndex(mapName, categoryName);
			if (nomIndex != -1) {
				int owner;
				StringMap nomination = view_as<StringMap>(GetArrayCell(nominations_arr, nomIndex));
			
				nomination.GetValue("client", owner);
				
				Call_StartForward(nomination_reset_forward);
				Call_PushString(mapName);
				Call_PushCell(owner);
				Call_Finish();

				nomination.GetValue("mapcycle", nominationKV);
				nominationKV.Close();
				nomination.Close();
				RemoveFromArray(nominations_arr, nomIndex);

				if(verboseLogs)
					LogUMCMessage(
						"VOTE MENU: (Verbose) Removing selected map '%s' from nominations.",
						mapName
					);
			}

			KeyValues displayCycle = new KeyValues("umc_mapcycle");
			displayCycle.Import(currentRotation);
			GetMapDisplayStringEx(displayCycle, categoryName, mapName, displayTemplate, mapDisplay, sizeof(mapDisplay));
			displayCycle.Close();

			if (cvar_display_cat.BoolValue)
				FormatEx(mapDisplay, sizeof(mapDisplay), "%s (%s)", mapDisplay, categoryName);

			StringMap mapInfo = new StringMap();
			mapInfo.SetValue(MAP_TRIE_MAP_KEY, mapName);
			mapInfo.SetValue(MAP_TRIE_GROUP_KEY, categoryName);

			KeyValues mapInfoCycle = new KeyValues("umc_mapcycle");
			mapInfoCycle.Import(currentMapcycle);
			mapInfo.SetValue("mapcycle", view_as<Handle>(mapInfoCycle));

			// If mapnom_display is 0 nominations are always
			// displayed at the bottom of the vote.
			if (view_as<ConVar>(cvar_mapnom_display).IntValue == 0) {
				InsertArrayCell(mapVote, nextIndex, view_as<Handle>(mapInfo));
				InsertArrayString(mapVoteDisplay, nextIndex, mapDisplay);
			} else {
				// Otherwise we'll just set it to the next position.
				nextIndex = GetNextMenuIndex(mapsInVote, scrambleVote);
				InsertArrayCell(mapVote, nextIndex, view_as<Handle>(mapInfo));
				InsertArrayString(mapVoteDisplay, nextIndex, mapDisplay);
			}

			// We added a map to the vote!
			mapsInVote++;
			copyKV.DeleteKey(mapName);
			mapsNeededFromCategory--;
		} // End adding non-nominated maps

		// Set up arrays for next loop!
		nameArray.Clear();
		weightArray.Clear();
		gatheredMapsArray.Clear();
	} while (copyKV.GotoNextKey()); // Do this for each category.

	nameArray.Close();
	weightArray.Close();
	gatheredMapsArray.Close();
	copyKV.Close();
	// Array list full of numbers corresponding to
	// each available menu slot.
	ArrayList voteInfoOptArray = view_as<ArrayList>(BuildNumArray(mapsInVote));
	StringMap voteItem;
	char menuBuffer[MAP_LENGTH * 2];
	for (int i = 0; i < mapsInVote; i++) {
		voteItem = new StringMap();
		voteInfoOptArray.GetString(i, menuBuffer, sizeof(menuBuffer));
		voteItem.SetString("info", menuBuffer);
		mapVoteDisplay.GetString(i, menuBuffer, sizeof(menuBuffer));
		voteItem.SetString("display", menuBuffer);
		result.Push(view_as<Handle>(voteItem));
	}

	mapVoteDisplay.Close();
	voteInfoOptArray.Close();

	if (extendOption) {
		FormatEx(displayTemplate,
				 sizeof(displayTemplate),
				 "%T",
				 LANG_SERVER,
				 "Extend Map");
		voteItem = new StringMap();
		voteItem.SetString("info", EXTEND_MAP_OPTION);
		voteItem.SetString("display", displayTemplate);

		if (view_as<ConVar>(cvar_extend_display).BoolValue)
			InsertArrayCell(result, 0, view_as<Handle>(voteItem));
		else
			result.Push(view_as<Handle>(voteItem));
	}

	if (dontChangeOption) {
		FormatEx(displayTemplate,
				 sizeof(displayTemplate),
				 "%T",
				 LANG_SERVER,
				 "Don't Change");
		voteItem = new StringMap();
		voteItem.SetString("info", DONT_CHANGE_OPTION);
		voteItem.SetString("display", displayTemplate);

		if (view_as<ConVar>(cvar_dontchange_display).BoolValue)
			InsertArrayCell(resultH, 0, view_as<Handle>(voteItem));
		else
			result.Push(view_as<Handle>(voteItem));
	}

	return BuildOptionsError_Success;
}


/**
 *  DEPRECATED?
 *  Fills the vote menu with maps from a category.
 *  I'm keeping the original function sigature for now,
 *  but I will eventually rework the entire system to
 *  work with modern SourceMod syntax.
 */
UMC_BuildOptionsError BuildCatVoteItemsEx(Handle voteManagerH, Handle resultH, 
                                          Handle currentRotationH, Handle currentMapcycleH,
										  bool scrambleVote, bool extendOption,
                                          bool dontChangeOption, bool nominationsRestricted=false, 
                                          bool applyExclusionRules=true) {
    if (voteManagerH == INVALID_HANDLE ||
        resultH == INVALID_HANDLE ||
        currentRotationH == INVALID_HANDLE ||
        currentMapcycle == INVALID_HANDLE) {
        LogError("VOTING: Cannot build category vote menu, invalid parameters were provided.");
        return BuildOptionsError_InvalidParameters;
    }

    StringMap voteManager = view_as<StringMap>(voteManagerH);
    ArrayList result = view_as<ArrayList>(resultH);
    KeyValues currentRotation = view_as<KeyValues>(currentRotationH);
    KeyValues currentMapcycle = view_as<KeyValues>(currentMapcycleH);

    currentRotation.Rewind(); //rewind original
    KeyValues copyKV = new KeyValues("umc_rotation");
    copyKV.Import(currentRotation);

    if (!copyKV.GotoFirstSubKey()) {
        LogError("VOTING: No map groups found in rotation. Vote menu was not built.");
        copyKV.Close();
        return BuildOptionsError_NoMapGroups;
    }

    ClearVoteArrays(voteManagerH);
    bool verboseLogs = view_as<ConVar>(cvar_logging).BoolValue;
    // TODO: Implement custom display templating for categories.
    bool categoryHasNominations = false;
    int  numNominations = 0,
		 numCatsInVote = 0;
    char categoryName[MAP_LENGTH];
         //categoryDisplay[MAP_LENGTH];
         //displayTemplate[MAP_LENGTH];
    ArrayList categoriesInVote = new ArrayList();
    KeyValues displayMapcycle;

    do {
        categoryHasNominations = false;
        copyKV.GetSectionName(categoryName, sizeof(categoryName));
        
        if (!IsValidCat(view_as<Handle>(copyKV), view_as<Handle>(currentMapcycle)) ||
			!copyKV.GotoFirstSubKey()) {
            if (verboseLogs)
                LogUMCMessage(
                    "VOTE MENU: (Verbose) Skipping map group '%s' because it has no valid maps.",
                    categoryName
                );
            continue;
        }

        if (copyKV.GetNum("maps_invote", 1) == 0) {
            if (verboseLogs)
                LogUMCMessage(
                    "VOTE MENU: (Verbose) Skipping map group '%s' because it has no maps allowed in the vote. (See maps_invote setting)",
                    categoryName
                );
            continue;
        }

        if (applyExclusionRules) {
            ArrayList categoryNominations = view_as<ArrayList>(GetCatNominations(categoryName));
            numNominations = categoryNominations.Length;

            char mapName[MAP_LENGTH],
                 nomGroup[MAP_LENGTH];
            KeyValues nominationKV,
                      nominationMapcycle;

            for (int i; i < numNominations; i++) {
                StringMap nomination = view_as<StringMap>(categoryNominations.Get(i));
                nomination.GetValue("mapcycle", nominationMapcycle);
                nomination.GetString(MAP_TRIE_MAP_KEY, mapName, sizeof(mapName));
                nomination.GetString("nom_group", nomGroup, sizeof(nomGroup));

                nominationKV = new KeyValues("umc_nomination");
                nominationKV.Import(nominationMapcycle);
                nominationKV.JumpToKey(nomGroup);

                if (IsValidMapFromCat(view_as<Handle>(nominationKV), 
                                      view_as<Handle>(currentMapcycle), 
                                      mapName, 
                                      .isNom = true)) {
                    categoryHasNominations = true;
                    nominationKV.Close();
                    break;
                }

                nominationKV.Close();
            }
			// Handling empty category here.

            categoryNominations.Close();
        } else {
			categoryHasNominations = true;
			copyKV.GoBack();
		}

		// If we don't have any nominations in
		// the category.
		if (!categoryHasNominations) {

			// Let's check to see if the group is
			// supposed to be excluded from the vote.
			if (!IsValidCat(view_as<Handle>(copyKV), currentMapcycleH)) {
				if (verboseLogs)
                    LogUMCMessage(
                        "VOTE MENU: (Verbose) Skipping excluded map group '%s'.",
                        categoryName
                    );

				// Skip the group if it is
				continue;
			}

			// Now we check to see if the group is
			// allowed to have any maps in the vote.
			if (copyKV.GetNum("maps_invote", 1) < 1 && nominationsRestricted) {
				if (verboseLogs)
                    LogUMCMessage(
                        "VOTE MENU: (Verbose) Skipping map group '%s' due to \"maps_invote\" setting of 0.",
                        categoryName
                    );
				
				continue;
			}
		}

		//We're gonna add the category to the array.
        InsertArrayString(view_as<Handle>(categoriesInVote),
                          GetNextMenuIndex(categoriesInVote.Length, scrambleVote),
                          categoryName);

		// We've aded a category to the vote!
		if (verboseLogs)
            LogUMCMessage(
                "VOTE MENU: (Verbose) Adding map group '%s' to the vote.",
                categoryName
            );
        numCatsInVote++;
    } while (copyKV.GotoNextKey());

	// Now that we've handled getting categories,
	// we can close the copy mapcycle.
	copyKV.Close();

	// We couldn't find any categories in
	// the UMC mapcycle.
	if (categoriesInVote.Length == 0) {
        if (verboseLogs)
            LogUMCMessage("VOTE MENU: (Verbose) No valid map groups found for the vote.");

		categoriesInVote.Close();
        return BuildOptionsError_NoMapGroups;
	
	// If we only have one group
	// we only need to run a map vote.
	} else if (categoriesInVote.Length == 1) {
		if (verboseLogs)
            LogUMCMessage("VOTE MENU: (Verbose) Not enough groups available for group vote, performing map vote with only group available.");
		
		categoriesInVote.Close();
        return BuildOptionsError_NotEnoughOptions;
    }

	StringMap voteItem;
	char categoryNameBuffer[MAP_LENGTH];

	for (int i; i < numCatsInVote; i++) {
		voteItem = new StringMap();
        categoriesInVote.GetString(i, categoryNameBuffer, sizeof(categoryNameBuffer));
        voteItem.SetString("info", categoryNameBuffer);
		voteItem.SetString("display", categoryNameBuffer);
		result.Push(view_as<Handle>(voteItem));
    }

	if (categoriesInVote != null)
		categoriesInVote.Close();

	if (extendOption) {
		voteItem = new StringMap();
		voteItem.SetString("info", EXTEND_MAP_OPTION);

		// TODO: Replace with translation string
		voteItem.SetString("display", "Extend Category");

		if (view_as<ConVar>(cvar_extend_display).BoolValue)
			InsertArrayCell(resultH, 0, view_as<Handle>(voteItem));
		else
			result.Push(view_as<Handle>(voteItem));
	}

	if (dontChangeOption) {
		voteItem = new StringMap();
		voteItem.SetString("info", DONT_CHANGE_OPTION);

		// TODO: Replace with translation string
		voteItem.SetString("display", "Don't Change Category");

		if (view_as<ConVar>(cvar_dontchange_display).BoolValue)
			InsertArrayCell(resultH, 0, view_as<Handle>(voteItem));
		else
			result.Push(view_as<Handle>(voteItem));
	}
	return BuildOptionsError_Success;
}

//Calls the templating system to format a map's display string.
//  kv: Mapcycle containing the template info to use
//  group:  Group of the map we're getting display info for.
//  map:    Name of the map we're getting display info for.
//  buffer: Buffer to store the display string.
//  maxlen: Maximum length of the buffer.
void GetMapDisplayStringEx(Handle currentMapcycle, 
						   const char[] mapGroup,
						   const char[] mapName,
						   const char[] displayTemplate,
						   char[] resultBuffer,
						   int maxLen) {
	KeyValues mapcycle = view_as<KeyValues>(currentMapcycle);
	strcopy(resultBuffer, maxLen, "");

	if (mapcycle.JumpToKey(mapGroup) &&
		mapcycle.JumpToKey(mapName)) {
		
		// TODO: Implement once I've finished
		// workshop name caching.
		// if (IsWorkshopMap(mapName)) {
			
		// }
		
		mapcycle.GetString("display", resultBuffer, maxLen, displayTemplate);
		mapcycle.GoBack();
		mapcycle.GoBack();
	}

	Call_StartForward(template_forward);
	Call_PushStringEx(resultBuffer, maxLen, SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(maxLen);
	Call_PushCell(currentMapcycle);
	Call_PushString(mapName);
	Call_PushString(mapGroup);
	Call_Finish();
}

//Filters a mapcycle with all invalid entries filtered out.
void FilterMapcycleEx(Handle kvToFilter,
					  Handle currentMapcycle,
					  bool isNomination=false, 
					  bool isForMapChange=true, 
					  bool deleteEmptyGroups=true)
{	
	KeyValues copyKV = view_as<KeyValues>(kvToFilter);

	//Do nothing if there are no map groups.
	if (!copyKV.GotoFirstSubKey())
		return;

	char group[MAP_LENGTH];
	do {
		FilterMapGroupEx(copyKV, currentMapcycle, isNomination, isForMapChange);

		if (deleteEmptyGroups) {
			if (!copyKV.GotoFirstSubKey()) {
				copyKV.GetSectionName(group, sizeof(group));

				// If we're unable to delete a key
				// there's probably something horribly wrong.
				if (copyKV.DeleteThis() == -1)
					return;
				
			}

			copyKV.GoBack();
		}
	} while (copyKV.GotoNextKey());
	copyKV.GoBack();
}

/**
 *  Filters all of the maps in a given category.
 *  The cursor of the KeyValue object has to be
 *  at the category that you want to filter.
 */
void FilterMapGroupEx(Handle kvToFilter, 
					  Handle currentMapcycle,
					  bool isNomination=false, 
					  bool isForMapChange=true)
{
	KeyValues copyKV = view_as<KeyValues>(kvToFilter);

	char group[MAP_LENGTH];
	copyKV.GetSectionName(group, sizeof(group));
	if (!copyKV.GotoFirstSubKey())
		return;

	char mapName[MAP_LENGTH];
	do {
		if (!IsValidMapEx(copyKV, currentMapcycle, group, isNomination, isForMapChange)) {
			copyKV.GetSectionName(mapName, sizeof(mapName));

			// If we're unable to delete a key
			// there's probably something horribly wrong.
			if (copyKV.DeleteThis() == -1)
				return;
		}
	} while (copyKV.GotoNextKey());
	copyKV.GoBack();
}

/**
 *  Given the map at the current position of kvToCheck, 
 *  this checks to see if the map is valid (or a workshop map).
 *  
 *  Then it calls the UMC_OnDeterminMapExclude forward to see
 *  if the map matches filters such as playercount and time of day.
 * 
 * 	@param kvToCheck        The KeyValues object who's cursor is at the map to check.
 * 	@param currentMapcycle  The current mapcycle KeyValues object.
 * 	@param category         The category to check the map against.
 * 	@param isNomination     Whether the map is being checked for a nomination.
 * 	@param isForMapChange   Whether the map is being checked for a map change.
 * 
 *  @return                 True if the map is valid, false otherwise.
 */
bool IsValidMapEx(Handle kvToCheck,
				  Handle currentMapcycle,
				  const char[] category,
				  bool isNomination = false,
				  bool isForMapChange = true) {
	KeyValues currentRotation = view_as<KeyValues>(kvToCheck);
	KeyValues mapcycle = view_as<KeyValues>(currentMapcycle);
	
	char mapName[MAP_LENGTH];
	currentRotation.GetSectionName(mapName, sizeof(mapName));

	// If sourcemod doesn't see this as a valid map
	// and the map isn't a workshop map then it isn't valid.
	if (!IsMapValid(mapName) && !IsWorkshopMap(mapName)) {
		LogUMCMessage("WARNING: Map \"%s\" does not exist on the server. (Group: \"%s\")", mapName, category);
		return false;
	}

	// Now we'll check the mapcycle for the map. If it exists
	// we can start the exclusion forward to let other plugins
	// modify the map's validity.
	if (currentRotation.JumpToKey(category) &&
	    currentRotation.JumpToKey(mapName)) {
		mapcycle.Rewind();

		KeyValues mapcycleCopy = new KeyValues("umc_rotation");
		Action result = Plugin_Continue;
		mapcycleCopy.Import(mapcycle);

		// Todo, replace with GlobalForward object.
		Call_StartForward(exclude_forward);
		Call_PushCell(view_as<Handle>(mapcycleCopy));
		Call_PushString(mapName);
		Call_PushString(category);
		Call_PushCell(isNomination);
		Call_PushCell(isForMapChange);
		Call_Finish(result);

		mapcycleCopy.Close();
		return (result == Plugin_Continue);
	}

	return false;
}

/** 
 *  Checks if a category is valid by checking
 *  if it contains at least one valid map.
 * 
 *  @param kvToCheck        The KeyValues object who's cursor is at the category to check.
 *  @param currentMapcycle  The current mapcycle KeyValues object.
 *  @param isNomination     Whether the map is being checked for a nomination.
 *  @param isForMapChange   Whether the map is being checked for a map change.
 * 
*/
bool IsValidCatEx(Handle kvToCheck,
				  Handle currentMapcycle,
				  bool isNomination = false,
				  bool isForMapChange = true) {
	KeyValues currentRotation = view_as<KeyValues>(kvToCheck);

	char categoryName[MAP_LENGTH];
	currentRotation.GetSectionName(categoryName, sizeof(categoryName));

	// Check if the category has any maps
	if (!currentRotation.GotoFirstSubKey()) {
		LogUMCMessage("WARNING: Category \"%s\" does not contain any maps.", categoryName);
		return false;
	}

	// Let's check each map in the category now
	do {
		if (IsValidMapEx(kvToCheck, currentMapcycle, categoryName, isNomination, isForMapChange)) {
			// Go back up one level from maps to categories
			currentRotation.GoBack();

			// Category meets requirements!
			return true;
		}
	} while (currentRotation.GotoNextKey());
	
	// Go back up one level, from maps
	// to categories.
	currentRotation.GoBack();
	
	// Category does not meet requirements.
	return false;
}

/**
 *  Checks if a map is valid within a category.
 * 
 *  @param kvToCheck        The KeyValues object who's cursor is at the category to check.
 *  @param currentMapcycle  The current mapcycle KeyValues object.
 *  @param mapName          The name of the map to check.
 *  @param isNomination     Whether the map is being checked for a nomination.
 *  @param isForMapChange   Whether the map is being checked for a map change.
 */
bool IsValidMapFromCatEx(Handle kvToCheck,
						 Handle currentMapcycle,
						 const char[] mapName,
						 bool isNomination = false,
						 bool isForMapChange = true) {
	KeyValues currentRotation = view_as<KeyValues>(kvToCheck);
	KeyValues mapcycle = view_as<KeyValues>(currentMapcycle);

	char categoryName[MAP_LENGTH];
	currentRotation.GetSectionName(categoryName, sizeof(categoryName));

	if (!currentRotation.JumpToKey(mapName))
		return false;

	bool result = IsValidMapEx(kvToCheck, currentMapcycle, categoryName, isNomination, isForMapChange);

	currentRotation.GoBack();
	return result;
}



int FindStringInMapArray(const char[] string, const char[] key, const ArrayList mapArray) {
    char nameBuffer[MAP_LENGTH];
    StringMap mapInfo;
    
    for (int i; i < mapArray.Length; i++) {
        mapInfo = mapArray.Get(i);
        mapInfo.GetString(key, nameBuffer, sizeof(nameBuffer));
        if (StrEqual(string, nameBuffer)) {
            return i;
        }
    }

    return -1;
}