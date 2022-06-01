SETTINGS_FILE_PATH = "EventShufflerSettings.txt"
GAME_LIST_PATH = ".\\EventsTemp\\GameList.txt"

-- initialise settings to default values
DEBUG_MODE = false
EVENT_FOUND_PREVENTS_TIMER = false
EVENT_OUTCOME_SWITCH_GAME = "EVENT_OUTCOME_SWITCH_GAME"
EVENT_OUTCOME_OUTPUT_CONTROL = "EVENT_OUTCOME_OUTPUT_CONTROL"
EVENT_OUTCOME_WRITE_TO_RAM = "EVENT_OUTCOME_WRITE_TO_RAM"
ON_EVENT = {}
NUMBER_OF_RAM_WRITES_ON_EVENT = 5
RAM_WRITE_MIN = -1
RAM_WRITE_MAX = -1
RAM_WRITE_DOMAIN = "DEFAULT"

gameList = {}

console.clear();

-- ------------------------------ USEFUL TOOL FUNCTIONS
function addToDebugLog(text)
	if DEBUG_MODE then
		console.log(text)
	end
end

function splitString(inputstr, sep)
	if sep == nil then
		sep = "%s"
	end
	local t={}
	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
			table.insert(t, str)
	end
	return t
end

function tablelength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end

function memoryForConsole(whichConsole) 
	if whichConsole == "GEN" then
		return "68K RAM"
	end

	if whichConsole == "GB" then
		return "CartRAM"
	end
	
	if whichConsole == "NES" then
		return "WRAM"
	end

	if whichConsole == "SMS" then
		return "Main RAM"
	end

	if whichConsole == "GG" then
		return "Main RAM"
	end

	if whichConsole == "SAT" then
		return "Work Ram High"
	end
	
	if whichConsole == "GBA" then
		return "IWRAM"
	end

	return memory.getcurrentmemorydomain()
end

function get_ring_file_path_for_current_game()
	return ".\\EventsTemp\\rings_" .. gameinfo.getromname() .. ".txt"
end

function file_exists(filePath)
	local f = io.open(filePath, "rb")
	if f then f:close() end
	return f ~= nil
end
-- ------------------------------ END OF USEFUL TOOL FUNCTIONS

-- Determine whether or not the timer can cause swap to happen
function shouldAllowTimer() 
	if EVENT_FOUND_PREVENTS_TIMER == false then
		return true
	end

	if eventDefinitionsExist == false then
		return true
	end

	return false
end

function outcomeIsEnabled(outcomeId)
	for i, event in pairs(ON_EVENT) do
		if event == outcomeId then
			return true
		end
	end

	return false
end

function readEventShufflerSettings() 
	if (file_exists(SETTINGS_FILE_PATH)) then
		for line in io.lines(SETTINGS_FILE_PATH) do	
			components = splitString(line, ":")
			if tablelength(components) > 1 then
				if components[1] == "DEBUG_MODE" then
					DEBUG_MODE = components[2]:upper() == "TRUE"
				end
				if components[1] == "EVENT_FOUND_PREVENTS_TIMER" then
					EVENT_FOUND_PREVENTS_TIMER = components[2]:upper() == "TRUE"
				end
				if components[1] == "ON_EVENT" then
					ON_EVENT = splitString(components[2], ",")
				end
				if components[1] == "NUMBER_OF_RAM_WRITES_ON_EVENT" then
					NUMBER_OF_RAM_WRITES_ON_EVENT = tonumber(components[2])
				end
				if components[1] == "RAM_WRITE_MIN" and tonumber("0x" .. components[2]) > 0 then
					RAM_WRITE_MIN = tonumber("0x" .. components[2])
				end
				if components[1] == "RAM_WRITE_MAX" and tonumber("0x" .. components[2]) > 0 then
					RAM_WRITE_MAX = tonumber("0x" .. components[2])
				end
				if components[1] == "RAM_WRITE_DOMAIN" then
					RAM_WRITE_DOMAIN = components[2]
				end
			end
		end
	else
		console.log("No settings file at " .. SETTINGS_FILE_PATH)
	end
end

function loadGameList() 
	gameList = {}
	if (file_exists(GAME_LIST_PATH)) then
		for line in io.lines(GAME_LIST_PATH) do	
			table.insert(gameList, line)
		end
	else
		console.log("No game list file at " .. GAME_LIST_PATH)
	end
end

-- Begin by getting the settings
readEventShufflerSettings()

loadGameList()

diff = 0
lowTime = 5
highTime = 30
newGame = 0
i = 0
x = 0
romSet = {}
gamePath = ".\\CurrentROMs\\"
settingsPath = "settings.xml"
if userdata.get("countdown") ~= nil then
	countdown = userdata.get("countdown")
else
	countdown = false
end
currentChangeCount = 0
c = {}
readOldTime = ""
saveOldTime = 0
savePlayCount = 0

lastTriggerValue = {}
swapForTriggerCounters = {}
flagToSwap = false
hasLoadedFirstGame = false
hasLoadedEventTriggers = false

eventDefinitionsExist = false

inspect = require('inspect')
gameDefs = {}

controlEventsSent = 0
queuedControlEvents = {}

if userdata.get("currentChangeCount") ~= nil then -- Syncs up the last time settings changed so it doesn't needlessly read the CurrentROMs folder again.
	currentChangeCount = userdata.get("currentChangeCount")
end
databaseSize = userdata.get("databaseSize")

function openCurrentTime(rom)
	if currentGame == nil then
		addToDebugLog("openCurrentTime failed - no currentGame set")
		return
	end
	oldTime = io.open(".\\TimeLogs\\" .. currentGame .. ".txt","a+")
	readOldTimeString = oldTime:read("*line")
	if readOldTimeString ~= nil then
		readOldTime = readOldTimeString
	else
		readOldTime = 0
	end
	oldTime:close()
	saveOldTime = readOldTime
	oldCount = io.open(".\\PlayCount\\" .. currentGame .. ".txt","a+")
	readOldCountString = oldCount:read("*line")
	if readOldCountString ~= nil then
		readOldCount = tonumber(readOldCountString)
	else
		readOldCount = 0
	end
	oldCount:close()
	savePlayCount = readOldCount + 1
	romDatabase = io.open("CurrentGameTime.txt","w")
	romDatabase:write(gameinfo.getromname() .. " play time: " .. saveOldTime)
	romDatabase:close()
	timeDatabase = io.open("CurrentGameSwitchCount.txt","w")
	timeDatabase:write(savePlayCount)
	timeDatabase:close()
	
end
	
	

function ends_with(str, ending)
   return ending == "" or str:sub(-#ending) == ending
end

function dirLookup(directory) -- Reads all ROM names in the CurrentROMs folder.
	gameList = {}

	if directory ~= null then
		addToDebugLog("calling dirLookup: ".. directory)
	else	
		addToDebugLog("calling dirLookup: NULL")
	end

	romIndex = 0
	for directory in io.popen([[dir ".\CurrentROMs" /b]]):lines() do
		addToDebugLog("got directory ".. directory)
		-- do not allow BIN, IMG or SUB files. Sega CD games can only be run fron CUE files or ISO files
		if ends_with(directory, ".bin") or ends_with(directory, ".img") or ends_with(directory, ".sub") or ends_with(directory, ".ccd") then
			addToDebugLog("SKIP: " .. directory)
		else
			addToDebugLog("ROM: " .. directory)
			romIndex = romIndex + 1
			userdata.set("rom" .. romIndex,directory)
			romSet[romIndex] = directory

			table.insert(gameList, directory)
		end
	end
	databaseSize = romIndex
	userdata.set("databaseSize", databaseSize)
	addToDebugLog("databaseSize is " .. databaseSize .. " roms!")

	fileToWrite = io.open(GAME_LIST_PATH,"w")
	runningString = ""
	for index, textValue in pairs(gameList) do
		if runningString:len() > 0 then
			runningString = runningString .. "\n"
		end
		runningString = runningString .. textValue
	end
	fileToWrite:write(runningString)
	fileToWrite:close()
end

function getSettings(filename) -- Gets the settings saved by the RaceShufflerSetup.exe
	local fp = io.open(filename, "r" ) -- Opens settings.xml
	if fp == nil then 
		return nil
	end
	settingsName = {}
	settingsValue = {}
	newLine = "a"
	newSetting = "a"
	k = 1
	for line in fp:lines() do -- Gets lines from the settings xml.
		newLine = string.match(line,'%l+%u*%l+')
		newSetting = string.match(line,'%p%a+%p(%w+)')
		if newLine ~= "settings" then
			settingsValue["value" .. k] = newSetting
			k = k + 1
		end
			
	end
	fp:close() -- Closes settings.xml
	lowTime = settingsValue["value2"] -- Stores minimum value
	highTime = settingsValue["value3"] -- Stores maximum value
	changedRomCount = tonumber(settingsValue["value6"]) -- Stores value indicating if ROMs have been changed
	if settingsValue["value5"] == "true" then
		countdown = true
	else
		countdown = false
		addToDebugLog("value5 " .. tostring(settingsValue["value5"]))
	end	
end

if databaseSize ~= nil then
	currentGame = userdata.get("currentGame")
	if currentGame == nil then
		currentGame = 0
	end
	openCurrentTime(rom)
	addToDebugLog("Current Game: " .. currentGame)
	lowTime = userdata.get("lowTime")
	if lowTime == nil then
		lowTime = 5
	end
	highTime = userdata.get("highTime")
	if highTime == nil then
		highTime = 5
	end
	seed = (userdata.get("seed"))
	if seed == nil then
		seed = 1234567
	end
	math.randomseed(seed)
	math.random()
	if lowTime ~= highTime then
		timeLimit = math.random(lowTime * 60,highTime * 60)
	else
		timeLimit = tonumber(highTime * 60)
	end
else 
	getSettings(settingsPath)
	timeLimit = 5
	dirLookup(directory)
	seed = settingsValue["value4"]
	math.randomseed(seed)
	math.random()
	addToDebugLog("Initial seed " .. seed)
end


databaseIndex = 0
databaseSize = userdata.get("databaseSize")

while databaseIndex < databaseSize do
	databaseIndex = databaseIndex + 1
	romSet[databaseIndex] = userdata.get("rom" .. databaseIndex)
	addToDebugLog("    Got rom rom ID userdata:" .. databaseIndex .. " = " .. romSet[databaseIndex])
end

addToDebugLog("Time Limit " .. timeLimit)

--Commenting delay out until we implement it in the setup bot. Feel free to use it yourself.
--[[


-- Pause after a swap
sound = client.GetSoundOn()
client.SetSoundOn(false)
client.sleep(500)  -- TODO: This should be configurable
client.SetSoundOn(sound)
]]

function cleanup()
	userdata.clear()
	do return end
end

function nextGame(game) -- Changes to the next game and saves the current settings into userdata
	totalGames = tablelength(gameList)
	addToDebugLog("Picking next game from set of " .. totalGames .. ": " .. inspect(gameList))
	if totalGames > 0 then
		client.SetSoundOn(false)
		getSettings(settingsPath)
		diff = 0
		if currentChangeCount < changedRomCount then -- Only do dirLookup() if settings have changed
			dirLookup(directory)
			currentChangeCount = changedRomCount
		end
		if totalGames == 1 then
			dirLookup(directory)
			newGame = gameList[1]
		else
			ranNumber = math.random(1, totalGames)
			addToDebugLog("Wants to load rom at index " .. ranNumber)
			if gameList[ranNumber] ~= nil then
				newGame = gameList[ranNumber]
				addToDebugLog("    This rom is " .. newGame)
			else
				addToDebugLog("    No ROM. Getting a new one from dirLookup ")
				dirLookup(directory)
				newGame = userdata.get("rom" .. ranNumber)
				addToDebugLog("    Got " .. newGame)
				--addToDebugLog("Ran dirLookup()")
			end
			while currentGame == newGame or newGame == nil do
				if newGame == nil then
					addToDebugLog("   Fetched game is nil - rerolling...")
				else
					addToDebugLog("   Fetched game " .. currentGame .." is the same as the last one - rerolling...")
				end
				ranNumber = math.random(1,totalGames)
				newGame = gameList[ranNumber]
				addToDebugLog("    Reroll! " .. ranNumber)
			end
		end
		currentGame = newGame
		userdata.set("first",1)
		savestate.saveslot(1)

		-- saving the database size must come before switching ROMs to prevent a race
		-- condition where an old game list hangs around in data
		databaseIndex = 0
		userdata.set("databaseSize",databaseSize)
		while databaseIndex < databaseSize do
			databaseIndex = databaseIndex + 1
			userdata.set("rom" .. databaseIndex, romSet[databaseIndex])
			addToDebugLog("    Setting in userdata, rom" .. databaseIndex .. " = " .. romSet[databaseIndex])
		end

		-- moving the actual game switch to the end prevents race conditions
		addToDebugLog("about to open rom: " .. gamePath .. currentGame)
		client.openrom(gamePath .. currentGame)
		addToDebugLog("did open rom: " .. gamePath .. currentGame)
		savestate.loadslot(1)
		addToDebugLog("currentGame " .. currentGame .. " loaded!")

		-- choosing next seed must come after the game loads
		-- I'm not sure why. Does it get immediately read by the next game? Feels like something
		-- that'd cause a race condition...
		randIncrease = math.random(1,20)
		userdata.set("seed",seed + randIncrease) -- Changes the seed so the next game/time don't follow a pattern.
		userdata.set("consoleID",emu.getsystemid())

		userdata.set("currentGame",currentGame)
		userdata.set("timeLimit",timeLimit)
		romDatabase = io.open("CurrentROM.txt","w")
		romDatabase:write(gameinfo.getromname())
		romDatabase:close()
		userdata.set("currentChangeCount",currentChangeCount)
		userdata.set("lowTime",lowTime)
		userdata.set("highTime",highTime)
		userdata.set("countdown",countdown)
	end	
end

buffer = 0 -- Sets countdown location. Adding 8 makes it appear correct for the NES.
if emu.getsystemid() == "NES" then
	buffer = 8
end

function startCountdown(count) -- Draws the countdown box and text
	if countdown == true then
		gui.drawBox(client.bufferwidth()/2-60,buffer,client.bufferwidth()-(client.bufferwidth()/2+1-60),15+buffer,"white","black")
		if (diff >= timeLimit - 60) then 
			gui.drawText(client.bufferwidth()/2,buffer,"!.!.!.ONE.!.!.!","red",null,null,null,"center")
		elseif (diff >= timeLimit - 120) then 
			gui.drawText(client.bufferwidth()/2,buffer,"!.!...TWO...!.!","yellow",null,null,null,"center")
		else
			gui.drawText(client.bufferwidth()/2,buffer,"!....THREE....!","lime",null,null,null,"center")
		end
	end
end

if userdata.get("currentChangeCount") ~= null then
	currentChangeCount = userdata.get("currentChangeCount")
else
	currentChangeCount = 0
end

function saveTime(currentRom)
	if currentGame == nil then
		addToDebugLog("Cannot save time without currentGame")
		return
	end
	currentGameTime = io.open(".\\TimeLogs\\" .. currentGame .. ".txt","w")
	if saveOldTime ~= nil then
		newTime = saveOldTime + timeLimit
	else
		newTime = timeLimit
	end
	currentGameTime:write(newTime)
	currentGameTime:close()
	currentGamePlayCount = io.open(".\\PlayCount\\" .. currentGame .. ".txt","w")
	if savePlayCount ~= nil then
		newPlayCount = savePlayCount
	else
		newPlayCount = 1
	end
	currentGamePlayCount:write(newPlayCount)
	currentGamePlayCount:close()
end

function checkForSwapEvent()
	-- memory inaccessible for the NULL system, so only check for swap events
	-- if we're in an active emulator (e.g. Genesis, SNES, GB...), and we're
	-- in a game where we have defined triggers in the "Events" folder
	if emu.getsystemid() ~= "NULL" and hasLoadedEventTriggers then
		if loadedGameDefs["scoreCounters"] == nil then
			return
		end

		-- for each defined trigger (e.g. score, ring count, coin count) for this game, 
		-- calculate if it has changed since last frame
		for key, value in pairs(loadedGameDefs["scoreCounters"]) do	
			bytesToInspect = value["bytes"]
			currentTriggerValue = 0
			multiplicand = 1

			-- Calculate the total based on the defined bytes and base for this trigger
			-- EXAMPLES
			-- if we track bytes {0xFE20, 0xFE21}, and read 0x12 from 0xFE20 and 0x34 from FE21
			--	in base 256, total = (1 * 0x12) + (256 * 0x34)
			--  in base 100, total = (1 * 0x2) + (10 * 0x1) + (100 * 0x4) + (1000 * 0x3)
			--  in base 10, total = (1 * 0x12) + (10 * 0x34)
			for i = 1,8 do
				byteValue = bytesToInspect[i]
				if byteValue ~= nil then
					domainToCheck = value["domain"]
					if domainToCheck == "DEFAULT" then
						domainToCheck = memoryForConsole(emu.getsystemid())
					end
					foundValue = memory.readbyte(byteValue, domainToCheck)
					if value["base"] == 100 then
						lowerVal = foundValue % 16
						upperVal = (foundValue - lowerVal) / 16
						foundValue = lowerVal + (upperVal * 10)
					end
					currentTriggerValue = currentTriggerValue + (foundValue * multiplicand)
					multiplicand = multiplicand * value["base"]
				end
			end

			-- initialise the trigger if we haven't done so yet
			if lastTriggerValue[key] == nil then
				lastTriggerValue[key] = 0
			end

			if value["trackerDivisor"] > 0 then
				currentTriggerValue = math.floor(currentTriggerValue / value["trackerDivisor"])
			end
			

			-- If the calculated score for this trigger is different enough from the
			-- previous one, fire the "ready to switch!" trigger
			if currentTriggerValue ~= lastTriggerValue[key] then
				addToDebugLog("lastTriggerValue["..key.."] = " .. lastTriggerValue[key])
				ringDifference = currentTriggerValue - lastTriggerValue[key]
				lastTriggerValue[key] = currentTriggerValue

				-- flag to begin counting down the swap timer for this trigger
				-- (immediate if "delay" is set to 0, after a few frames otherwise)
				if currentTriggerValue ~= 0 and ringDifference > value["minChange"] and ringDifference < value["maxChange"] and value["enabled"] and value["isTracker"] == false then
					
					
					swapForTriggerCounters[key] = 1

					addToDebugLog("queuedControlEvents: " .. inspect(queuedControlEvents) .. ", " .. value["controlOutput"])
					table.insert(queuedControlEvents, value["controlOutput"])

					addToDebugLog("flagToSwap set at checkForSwapEvent, ".. key .. " " .. lastTriggerValue[key] .. " -> " .. currentTriggerValue)
				end

				if value["isTracker"] and value["enabled"] and outcomeIsEnabled(EVENT_OUTCOME_OUTPUT_CONTROL) then
					writeTrackerToController(key, currentTriggerValue)
				end
			end
		end
	end
end

function clearTrackersForController()
	eventIndex = math.random(1, 100)
	eventCountString = string.format("%05d", eventIndex)

	filePath = ".\\ControlsOutput\\tracker_" .. eventCountString .. ".txt"
	fileToWrite = io.open(filePath,"w")
	fileToWrite:write("RESET")
	fileToWrite:close()

	addToDebugLog(EVENT_OUTCOME_OUTPUT_CONTROL .. " RESET at path " .. filePath)
end

function writeTrackerToController(key, value)
	eventIndex = math.random(1, 100)
	eventCountString = string.format("%05d", eventIndex)

	stringToSend = key .. ":" .. value

	filePath = ".\\ControlsOutput\\tracker_" .. eventCountString .. ".txt"
	fileToWrite = io.open(filePath,"w")
	fileToWrite:write(stringToSend)
	fileToWrite:close()

	addToDebugLog(EVENT_OUTCOME_OUTPUT_CONTROL .. " tracked: " .. stringToSend .. " to " .. filePath)
end

-- Save the current states of the triggers, so that when we swap
-- back into this game, it does not immediately fire a swap.
-- Call this just before you switch games.
function saveCurrentTriggerStates()
	if emu.getsystemid() ~= "NULL" then
		addToDebugLog("saveCurrentTriggerStates " .. emu.getsystemid())
		addToDebugLog("saveCurrentTriggerStates writing")

		runningString = ""
		for key, value in pairs(lastTriggerValue) do
			if runningString:len() > 0 then
				runningString = runningString .. "/"
			end
			runningString = runningString .. key .. ":" .. tostring(lastTriggerValue[key])
		end

		userdata.set(get_ring_file_path_for_current_game(), runningString)

		addToDebugLog("saveCurrentTriggerStates wrote")
	end
end

if databaseSize == 1 then
	timeLimit = 6000
end

loadedGameDefs = {}
loadedGameDefs["scoreCounters"] = {}

function decodeGameDefs(sourceString)
	allLines = splitString(sourceString, "\n")
	trackerFound = false

	for lineIndex, line in pairs(allLines) do
		addToDebugLog("Decoding shuffler line: " .. line)
		lineSplit = splitString(line, ">")
		-- you can comment out values to track using the "/" character
		if tablelength(lineSplit) > 1 and line:sub(1, 1) ~= "/" then
			-- begin by applying defaults for this trigger
			lastTriggerValue[lineSplit[1]] = 0
			loadedGameDefs["scoreCounters"][lineSplit[1]] = {}
			loadedGameDefs["scoreCounters"][lineSplit[1]]["bytes"] = {}
			loadedGameDefs["scoreCounters"][lineSplit[1]]["base"] = 0x100
			loadedGameDefs["scoreCounters"][lineSplit[1]]["minChange"] = 0
			loadedGameDefs["scoreCounters"][lineSplit[1]]["maxChange"] = 100000000
			loadedGameDefs["scoreCounters"][lineSplit[1]]["delay"] = 0
			loadedGameDefs["scoreCounters"][lineSplit[1]]["domain"] = "DEFAULT" --memoryForConsole(emu.getsystemid())
			loadedGameDefs["scoreCounters"][lineSplit[1]]["controlOutput"] = "PRESS"
			loadedGameDefs["scoreCounters"][lineSplit[1]]["enabled"] = true
			loadedGameDefs["scoreCounters"][lineSplit[1]]["isTracker"] = false
			loadedGameDefs["scoreCounters"][lineSplit[1]]["trackerDivisor"] = 1

			-- now decode each phrase
			data = splitString(lineSplit[2], "/")
			for i, dataEntry in pairs(data) do
				entry = splitString(dataEntry, ":")
				if entry[2] ~= nil then
					if entry[1] == "bytes" then
						bytesSplit = splitString(entry[2], ",")
						for j, byteName in pairs(bytesSplit) do
							loadedGameDefs["scoreCounters"][lineSplit[1]]["bytes"][j] = tonumber("0x" .. byteName)
						end
					end
					if entry[1] == "base" then
						loadedGameDefs["scoreCounters"][lineSplit[1]]["base"] = tonumber(entry[2])
					end
					if entry[1] == "minChange" then
						loadedGameDefs["scoreCounters"][lineSplit[1]]["minChange"] = tonumber(entry[2])
					end
					if entry[1] == "maxChange" then
						loadedGameDefs["scoreCounters"][lineSplit[1]]["maxChange"] = tonumber(entry[2])
					end
					if entry[1] == "delay" then
						loadedGameDefs["scoreCounters"][lineSplit[1]]["delay"] = tonumber(entry[2])
					end
					if entry[1] == "domain" then
						loadedGameDefs["scoreCounters"][lineSplit[1]]["domain"] = entry[2]
					end
					if entry[1] == "controlOutput" then
						loadedGameDefs["scoreCounters"][lineSplit[1]]["controlOutput"] = entry[2]
					end
					if entry[1] == "enabled" then
						loadedGameDefs["scoreCounters"][lineSplit[1]]["enabled"] = entry[2]:upper() == "TRUE"
					end
					if entry[1] == "isTracker" then
						loadedGameDefs["scoreCounters"][lineSplit[1]]["isTracker"] = entry[2]:upper() == "TRUE"
						trackerFound = true
					end
					if entry[1] == "trackerDivisor" then
						loadedGameDefs["scoreCounters"][lineSplit[1]]["trackerDivisor"] = tonumber(entry[2])
					end
				end
			end
		end
	end

	-- tell the controller to stop using tracker inputs for this game to decide the conrols
	-- and instead use the timer
	if trackerFound == false then
		clearTrackersForController()
	end

	eventDefinitionsExist = true
end

function initialiseEventTriggers()
	addToDebugLog("!!!!!!!!!!!!!!! initialiseEventTriggers begins !!!!!!!!!!!!!!!!!!")

	-- determine the file name for this game. For example, the game "Sonic: Forces (JUE) [!]"
	-- running on the Sega Genesis will have its trigger stored at "Events/Sonic, Forces GEN.txt"
	romName = gameinfo.getromname()
	romNameWithoutDetails = splitString(romName, "[(")[1]
	romNameWithoutDetails = romNameWithoutDetails:upper():gsub(":",",")
	lastLetter = romNameWithoutDetails:sub(romNameWithoutDetails:len(), romNameWithoutDetails:len())
	if lastLetter ~= " " then
		romNameWithoutDetails = romNameWithoutDetails .. " "
	end
	romNameWithoutDetails = romNameWithoutDetails .. emu.getsystemid()
	addToDebugLog("romNameWithoutDetails: " .. romNameWithoutDetails)

	-- expose the ID of the current game for the EventShufflerSetup tool
	romDatabase = io.open(".\\EventsTemp\\EventShufflerGameID.txt","w")
	romDatabase:write(romNameWithoutDetails)
	romDatabase:close()

	fileNameForShuffleDetails = ".\\Events\\" .. romNameWithoutDetails .. ".txt"

	-- userstateData = userdata.get(fileNameForShuffleDetails)

	-- If we've already cached trigger definitions for this game, use the cached definitions
	-- Otherwise, decode the data saved in the text file if it exists, use it and cache it
	-- Otherwise, default to using the timer
	if userstateData ~= NULL then
		decodeGameDefs(userstateData)
		addToDebugLog("DECODED CACHED SPEC: " .. inspect(loadedGameDefs))
	elseif (file_exists(fileNameForShuffleDetails)) then
		runningDef = ""
		for line in io.lines(fileNameForShuffleDetails) do
			-- prepare a version of this for the cache
			if runningDef:len() > 0 then
				runningDef = runningDef .. "\n"
			end
			runningDef = runningDef .. line
		end
		userdata.set(fileNameForShuffleDetails, runningDef)
		decodeGameDefs(runningDef)

		addToDebugLog("LOADED NEW SPEC: " .. inspect(loadedGameDefs))
	else 
		addToDebugLog("NO FILE AT: " .. fileNameForShuffleDetails)
		eventDefinitionsExist = false
	end

	addToDebugLog("!!!!!!!!!!!!!!! do we have cached trigger states? !!!!!!!!!!!!!!!!!!") 
	-- determine if we already have states cached for these triggers (i.e. from
	-- when we last switched out of this game)
	ringsFilePath = get_ring_file_path_for_current_game()
	if userdata.containskey(ringsFilePath) then
		addToDebugLog("trigger state user data exists at " .. ringsFilePath)
		rawData = userdata.get(ringsFilePath)
		dataSplit = splitString(rawData, "/")
		for i, dataLine in pairs(dataSplit) do
			addToDebugLog("Has loaded trigger state line: " .. dataLine)
			lineSplit = splitString(dataLine, ":")
			if tablelength(lineSplit) > 1 then
				lastTriggerValue[lineSplit[1]] = tonumber(lineSplit[2])
				swapForTriggerCounters[lineSplit[1]] = 0
			end
		end
		hasLoadedEventTriggers = true
	else
		addToDebugLog("No trigger states in user data at " .. ringsFilePath)
		hasLoadedEventTriggers = true
		lastTriggerValue = {}
		swapForTriggerCounters = {}
	end

	addToDebugLog("!!!!!!!!!!!!!!! end of initialiseEventTriggers !!!!!!!!!!!!!!!!!!") 
end

-- does the thing that gets done, for example, when Mario grabs a coin
function activateEventOutcome() 
	-- switch to a new game
	if outcomeIsEnabled(EVENT_OUTCOME_SWITCH_GAME) then
		swapForTriggerCounters = {}
		hasLoadedEventTriggers = false
		saveCurrentTriggerStates()

		saveTime(currentRom)
		nextGame(game)

		hasLoadedFirstGame = true
		shouldLoop = false
	end

	-- write to a random RAM location
	if outcomeIsEnabled(EVENT_OUTCOME_WRITE_TO_RAM) then
		math.randomseed(os.time())
		math.random()

		-- determine the settings from EventShufflerSettings.txt
		domain = memoryForConsole(emu.getsystemid())
		if RAM_WRITE_DOMAIN ~= "DEFAULT" then
			domain = RAM_WRITE_DOMAIN
		end
		min = 0
		max = memory.getmemorydomainsize(domain)
		if RAM_WRITE_MIN > -1 then
			min = RAM_WRITE_MIN
			if min > RAM_WRITE_MAX then
				min = RAM_WRITE_MAX
			end
		end
		if RAM_WRITE_MAX > -1 and RAM_WRITE_MAX < max then
			max = RAM_WRITE_MAX
			if max < min then
				max = min
			end
		end

		-- write to RAM as many times as we have defined in EventShufflerSettings.txt
		for i = 1, NUMBER_OF_RAM_WRITES_ON_EVENT do
			index = math.random(min, max)
			value = math.random(0, 255)
			addToDebugLog(i ..": Writing " .. value .. " to " .. index .. " in " .. domain)
			memory.writebyte(index, value, domain)
		end
	end

	-- write a "controls event outcome"
	if outcomeIsEnabled(EVENT_OUTCOME_OUTPUT_CONTROL) then
		eventIndex = math.random(1, 100)
		eventCountString = string.format("%05d", eventIndex)

		stringToSend = ""
		for index, value in pairs(queuedControlEvents) do
			if stringToSend:len() > 0 then
				stringToSend = stringToSend .. ","
			end
			stringToSend = stringToSend .. value
		end

		filePath = ".\\ControlsOutput\\event_" .. eventCountString .. ".txt"
		fileToWrite = io.open(filePath,"w")
		fileToWrite:write(stringToSend)
		fileToWrite:close()

		addToDebugLog(EVENT_OUTCOME_OUTPUT_CONTROL .. " wrote: " .. stringToSend .. " to " .. filePath)

		queuedControlEvents = {}
		controlEventsSent = controlEventsSent + 1
	end
end

-- SET UP THE EVENT TRACKERS HERE!
initialiseEventTriggers()

while true do -- The main cycle that causes the emulator to advance and trigger a game switch.
	if (diff >= timeLimit - 180 and shouldAllowTimer()) then
		startCountdown(count)
	end

	-- The sound gets switched off during a game switch, so switch it on again
	-- if we're satisfied we're back in the game
	if diff == 1 then
		client.SetSoundOn(true)
	end
	-- After the first frame, start checking for swap events being fired
	-- e.g. collecting a ring
	if diff > 0 then 
		checkForSwapEvent()
	end

	-- If no emulator is loaded, swap immediately
	if emu.getsystemid() == "NULL" and diff == 5 and outcomeIsEnabled(EVENT_OUTCOME_SWITCH_GAME) then
		flagToSwap = true
		addToDebugLog("flagToSwap set at getsystemid")
	end

	-- If there are no defined events for this game use the timer
	-- to decide when to switch
	if diff > timeLimit and shouldAllowTimer() and outcomeIsEnabled(EVENT_OUTCOME_SWITCH_GAME) then
		flagToSwap = true
	end	

	-- Check for triggers that have been fired. If they have,
	-- count down until it is swap-time for them
	-- (the "delay" features allows us to tell the difference between
	-- score going up because you stomped an enemy, and score going up
	-- during an end-of-level totaliser)
	nextTriggerCounters = {}
	for key, value in pairs(swapForTriggerCounters) do
		nextTriggerCounters[key] = value
		if value > 0 then
			nextTriggerCounters[key] = value + 1
		end
		if loadedGameDefs["scoreCounters"][key] ~= nil then
			if value > loadedGameDefs["scoreCounters"][key]["delay"] then
				flagToSwap = true
				nextTriggerCounters[key] = 0
			end
		end
	end
	swapForTriggerCounters = nextTriggerCounters

	-- So the user can tell the script is running, log the frame count
	-- every 5 seconds
	diff = diff + 1
	if (diff % 300) == 0 then
		console.log("On frame " .. diff)
	end

	-- Swap to the next game if a swap has been fired!
	if flagToSwap then
		flagToSwap = false
		activateEventOutcome()
	end 
		
	emu.frameadvance()
end
