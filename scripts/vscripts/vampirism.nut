// Vampirism 1.2 By The Fish
printl("---Starting Vampirism---\n---Made By The Fish---\n---To start the gamemode, leave the safe area---");



DirectorOptions <- {
	ActiveChallenge = 1
	weaponsToConvert = {
		weapon_first_aid_kit = "weapon_pain_pills_spawn"
	}
	
	function ConvertWeaponSpawn( classname ){
		if ( classname in weaponsToConvert )
		{
			return weaponsToConvert[classname];
		}
		return 0;
	}	
	
}

WitchMapFilter <- {
	c4m1_milltown_a = true
	c4m2_sugarmill_a = true
	c4m3_sugarmill_b = true
	c4m4_milltown_b = true
}

MutationState <- {
	vampirismEnabled = false // Is the mod currently enabled? False before player exits safehouse
	maxVampirism = 4 // What is the max health decay rate? (depletes every 3 seconds)
	vampirismConsumeSpeed = 2 // How fast does the health decay build up to max?
	vampirismHeadshotMultiplier = 2.00 // Headshot modifier
	vampirismBlastMultiplier = 1.00 // Gives full health (for now)
	vampirismMeleeMultiplier = 1.25 // Modifier for melee kills
	vampirismBotHealthNewMultiplier = 1.25 //How much health bots receive for kills
	vampirismPlayerHealBotMultiplier = 0.25 //How much health bots receive from player kills
	vampirismHealthStealMultiplier = 1 //Players will recieve 90% of the health that they take off their fellow survivors
	vampirismReviveHealth = 50 // Amount of health players start with when revived
	specialHealthPoints = 25 // Special Infected give 25 health points
	
	MeleeWeaponID = 19 // Holds the weaponID of melee weapons.
	maxPlayerHealth = 100 // Max player health
	
	//Holds the survivor instances
	survivors = null
	
	//Fix for lag spike when applying health changes
	survivorToUpdateNextFrame = null
	
	// Holds the infected stats
	infected = [
		{ zombietype="common", 	HealthPoints=1, 	grantAllSurvivorsHealth=false,	reviveIncapacitatedSurvivors=false }, 	// COMMON INFECTED = index 0
		{ zombietype="smoker", 	HealthPoints=25,	grantAllSurvivorsHealth=false,	reviveIncapacitatedSurvivors=false },	// SMOKER = index 1
		{ zombietype="boomer", 	HealthPoints=25,	grantAllSurvivorsHealth=false,	reviveIncapacitatedSurvivors=false }, 	// BOOMER = index 2
		{ zombietype="hunter", 	HealthPoints=25,	grantAllSurvivorsHealth=false,	reviveIncapacitatedSurvivors=false }, 	// HUNTER = index 3
		{ zombietype="spitter", HealthPoints=25,	grantAllSurvivorsHealth=false,	reviveIncapacitatedSurvivors=false },	// SPITTER = index 4
		{ zombietype="jockey", 	HealthPoints=25,	grantAllSurvivorsHealth=false,	reviveIncapacitatedSurvivors=false }, 	// JOCKEY = index 5
		{ zombietype="charger", HealthPoints=25,	grantAllSurvivorsHealth=false,	reviveIncapacitatedSurvivors=false }, 	// CHARGER = index 6
		{ zombietype="witch", 	HealthPoints=50,	grantAllSurvivorsHealth=true,	reviveIncapacitatedSurvivors=true }, 	// WITCH = index 7
		{ zombietype="tank", 	HealthPoints=100,	grantAllSurvivorsHealth=true,	reviveIncapacitatedSurvivors=true } 		// TANK = index 8
	]
	
}

// Called when the mutation is activated
function OnActivate(){
	// Add a slow pulsing loop to the function vampirism_poll_update located further down this script
	ScriptedMode_AddSlowPoll( vampirism_poll_update );
}

// Called when the mutation stops
function OnShutdown(){
	// Remove the slow pulsing loop
	ScriptedMode_RemoveSlowPoll( vampirism_poll_update );
}

// Called when the game starts or on a map transition
function OnGameplayStart(){
	// Reload the survivors from Entities, function located further down script
	RefreshSurvivors();
	// Do map callbacks
	DoMapCallbackChecks();
	
	printl(SessionState.MapName);
	
	if( SessionState.MapName in WitchMapFilter ){
		if( WitchMapFilter[SessionState.MapName] ){
			printl( "Because there are so many witches in Hard Rain, only the person that kills the witch gains HP" );
			HELP_TEXT_ENG.append("NOTE: Because there are so many witches in Hard Rain, only the person that kills the witch gains HP");
			MutationState.infected[7].grantAllSurvivorsHealth = false;
		}
	}
}

vampirismHUD <- {}

function SetupModeHUD(){
	vampirismHUD = {
		Fields ={
		}
	}
	
	HUDSetLayout( vampirismHUD );
	Ticker_AddToHud( vampirismHUD, "Welcome to Vampirism! For help on how to play, type /vamp_help" );
	Ticker_SetBlink( true );
}

HELP_TEXT_ENG <- [
	" Vampirism twists the game up a bit",
	" That which kills you, keeps you alive",
	" When you leave the safe area your health will start depleting",
	" Shoot zombies to gain health",
	" Common = "+MutationState.infected[0].HealthPoints+" HP",
	" Specials = "+MutationState.infected[1].HealthPoints+" HP",
	" Witch = "+MutationState.infected[7].HealthPoints+" HP to all survivors",
	" Tank = "+MutationState.infected[8].HealthPoints+" HP to all survivors",
	" Headshots = x"+MutationState.vampirismHeadshotMultiplier.tointeger()+" multiplier",
	" Tip: Shoot fellow survivors to steal their health! MUHAHAHAHAHA!"
]

function InterceptChat(str, srcEnt){
	
	if( str.find("/vamp_help") ){
		foreach( idx, str in HELP_TEXT_ENG ){
			Say( null, str, true );
		}
	}
	
}


function GetSurvivor(strName) {
	return {
		playerInstance = Entities.FindByName(null, "!" + strName)
		vampirismEnabled = false
		currentVampirism = 0
	}
}

// Reload the survivors into SessionState.survivors
function RefreshSurvivors(){
	if (!SessionState.survivors) {	
		if( IsL4D1Survivors() ){
			SessionState.survivors = {
				zoey = GetSurvivor("zoey")
				francis = GetSurvivor("francis")
				bill = GetSurvivor("bill")
				louis = GetSurvivor("louis")
			}
			local s = SessionState.survivors
		
			printl("L4D1 SURVIVORS FOUND!");
			s.zoey.playerInstance = Entities.FindByName(null, "!zoey")
			s.zoey.playerInstance.SetReviveCount(0);
			s.francis.playerInstance = Entities.FindByName(null, "!francis")
			s.francis.playerInstance.SetReviveCount(0);
			s.bill.playerInstance = Entities.FindByName(null, "!bill")
			s.bill.playerInstance.SetReviveCount(0);
			s.louis.playerInstance = Entities.FindByName(null, "!louis")
			s.louis.playerInstance.SetReviveCount(0);
		}else{
			SessionState.survivors = {
				nick = GetSurvivor("nick")
				rochelle = GetSurvivor("rochelle")
				coach = GetSurvivor("coach")
				ellis = GetSurvivor("ellis")
			}
			local s = SessionState.survivors
		
			printl("L4D2 SURVIVORS FOUND!");
			s.nick.playerInstance = Entities.FindByName(null, "!nick")
			s.nick.playerInstance.SetReviveCount(0);
			s.rochelle.playerInstance = Entities.FindByName(null, "!rochelle")
			s.rochelle.playerInstance.SetReviveCount(0);
			s.coach.playerInstance = Entities.FindByName(null, "!coach")
			s.coach.playerInstance.SetReviveCount(0);
			s.ellis.playerInstance = Entities.FindByName(null, "!ellis")
			s.ellis.playerInstance.SetReviveCount(0);
		}
	}
}

function IsL4D1Survivors(){
	local s = SessionState.survivors;

	local l4d1 = 	null != Entities.FindByName(null, "!zoey") ||
				 	null != Entities.FindByName(null, "!francis") ||
					null != Entities.FindByName(null, "!bill") ||
					null != Entities.FindByName(null, "!louis")

	local l4d2 = 	null != Entities.FindByName(null, "!nick") ||
				 	null != Entities.FindByName(null, "!rochelle") ||
					null != Entities.FindByName(null, "!coach") ||
					null != Entities.FindByName(null, "!ellis") 

	if (l4d2) {
		return false;
	}
	else if (l4d1) {
		return true
	}
	else {
		throw "Cannot find any survivors!"
	}
}

// Add health onto a player, called when a zombie is killed.
function AddPlayerHealth(player, healthAdd){
	local healthNew = player.GetHealth();
	healthNew += healthAdd;

	if( healthNew > SessionState.maxPlayerHealth ){
		healthNew = SessionState.maxPlayerHealth;
	}
	// If the new health + temp health is more than the max health
	if( healthNew + player.GetHealthBuffer() > SessionState.maxPlayerHealth ){
			// Set the temp health to fill the gap or = 0
			player.SetHealthBuffer( SessionState.maxPlayerHealth - healthNew );
		}
	// Set the players health to the new health
	player.SetHealth( healthNew );

	// Set the current players health decay to 0
	local name = GetCharacterDisplayName(player).tolower();
	SessionState.survivors[name].currentVampirism = 0;

	//printl(GetCharacterDisplayName(player).tolower()+" : +"+healthAdd+"HP")
}

// Set everyones health decay on or off depending on passed boolean
function SetAllVampirisms(arg){
	RefreshSurvivors();

	// Loop through the survivors
	foreach( name, stats in SessionState.survivors ){
		// Enable health decay
		stats.vampirismEnabled = arg;
		//printl(name+" VAMPIRISM ACTIVATED");
	}
	
	//foreach( name, stats in SessionState.survivors ){
	//	printl(name+"  :  "+stats.vampirismEnabled);
	//}
}

function DoMapCallbackChecks(){
	//A bunch of stuff I don't really understand, but something in there fixed the map transition glitch.
	CheckOrSetMapCallback( "DoMapEventCheck", @() false )
	CheckOrSetMapCallback( "DoMapSetup", @() null)
	CheckOrSetMapCallback( "GetMapEscapeStage", @() null )
	CheckOrSetMapCallback( "IsMapSpecificStage", @() false )
	CheckOrSetMapCallback( "GetMapSpecificStage", @() null )
	CheckOrSetMapCallback( "GetAttackStage", @() null )
	CheckOrSetMapCallback( "GetMapClearoutStage", @() null )
	CheckOrSetMapCallback( "GetMapDelayStage", @() null )
	DoMapSetup();
}

function vampirism_poll_update(){
	// If Vampirism is enabled
	if( SessionState.vampirismEnabled ){
		foreach( name, stats in SessionState.survivors ){
			local survivor = stats.playerInstance
			if( stats.vampirismEnabled ){
				//printl("Vampirism:     "+name+"  :  "+stats.currentVampirism);
				
				// Increase the health decay rate
				// Going to try setting this before the health is decayed rather than after
				stats.currentVampirism += SessionState.vampirismConsumeSpeed;
				if( stats.currentVampirism > SessionState.maxVampirism )
					stats.currentVampirism = SessionState.maxVampirism;
				
				if( !survivor.IsIncapacitated() ){
					// Set the health that is to be set on the player to the current player health
					healthToSet <- survivor.GetHealth() - stats.currentVampirism; 
					if( healthToSet < 1 ) healthToSet = 1; // Lowest health can be 1 HP so if it's below 1 set it to 1
					if( healthToSet == 1 ){
						local healthBuffer = survivor.GetHealthBuffer();
						healthBuffer -= stats.currentVampirism;
						survivor.SetHealthBuffer(healthBuffer);
					}
					survivor.SetHealth( healthToSet );// Set the health to the health decay
				}
				
			}
		}
	}
	else{
		printl("Vampirism disabled. Skipping health decay.")
	}
}

///////////////////////////////////////////////////////////\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
///////////////////////////////////////////				EVENTS				\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
///////////////////////////////////////////////////////////\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

function OnGameEvent_player_left_start_area( args ){
	printl("PLAYER "+GetPlayerFromUserID(args.userid).GetPlayerName()+" LEFT START! VAMPIRISM STARTED!");
	SessionState.vampirismEnabled = true;
	SetAllVampirisms(true);
}

function OnGameEvent_round_end( args ){
	SetAllVampirisms(false);
}

function OnGameEvent_revive_success( args ){
	local player = GetPlayerFromUserID( args.subject );
	player.SetHealth( SessionState.vampirismReviveHealth );
	player.SetHealthBuffer(0);
}

function OnGameEvent_door_open( args ){
	player <- GetPlayerFromUserID(args.userid)
	if( args.checkpoint ){
		
		if( player )
			if( !IsPlayerABot(player) ){
				SessionState.vampirismEnabled = true
				SetAllVampirisms(true);
				printl("CHECKPOINT DOOR OPENED BY "+player.GetPlayerName());
			}
	}
}

function OnGameEvent_player_hurt( args ){
	local attacker = GetPlayerFromUserID( args.attacker );
	local victim = GetPlayerFromUserID( args.userid );
	local steal = args.dmg_health * SessionState.vampirismHealthStealMultiplier

	if (attacker && victim) {
		if( attacker.GetZombieType() == 9 && victim.GetZombieType() == 9 ){
			AddPlayerHealth( attacker, steal );
			printl( attacker.GetPlayerName()+" stole "+steal+" health points from "+victim.GetPlayerName() );
		}
	} else {
		if (!attacker) {
			printl(format("Cannot find attacker from ID: %i. Maybe try args.attackerentid (%i)?", args.attacker, args.attackerentid))
		}

		if(!victim) {
			printl(format("Cannot find victim from ID: %i", args.victim))
		}
	}
}

function OnGameEvent_zombie_death( args ){

	local currentMultiplier = 1
	local player = null
	
	if( args.attacker )
		player = PlayerInstanceFromIndex( args.attacker )
		
	if( player ){
		local displayName = GetCharacterDisplayName( player ).tolower();
		
		if( displayName != "" && SessionState.survivors ){

			local s = SessionState.survivors[displayName];
			if( s.vampirismEnabled ){
				if( IsPlayerABot( player ) ) currentMultiplier *= SessionState.vampirismBotHealthNewMultiplier;
				if( args.headshot ) currentMultiplier *= SessionState.vampirismHeadshotMultiplier;
				if( args.blast ) currentMultiplier *= SessionState.vampirismBlastMultiplier;
			
				try{// Tank deaths do not return weapon_id so wrap in try/catch to catch the error
					if( args.weapon_id == SessionState.MeleeWeaponID ) currentMultiplier *= SessionState.vampirismMeleeMultiplier;
				}catch(e){}
				
				local infected = SessionState.infected[args.infected_id]
				//printl( "ZombieAwardAllTeam = "+infected.grantAllSurvivorsHealth );
				if (infected.reviveIncapacitatedSurvivors){
					foreach(name, stats in SessionState.survivors){
						stats.playerInstance.ReviveFromIncap();
						stats.playerInstance.SetReviveCount(0);
					}
				}
				
				if( infected.grantAllSurvivorsHealth ){
					foreach( name, stats in SessionState.survivors ){
						local survivor = stats.playerInstance;
						AddPlayerHealth( survivor, infected.HealthPoints * currentMultiplier );
					}
				}else{
					AddPlayerHealth( player, infected.HealthPoints * currentMultiplier );
					foreach( name, stats in SessionState.survivors ){
						local survivor = stats.playerInstance;
						if( survivor ){
							if( IsPlayerABot(survivor) ){
								AddPlayerHealth( survivor, infected.HealthPoints * currentMultiplier * SessionState.vampirismPlayerHealBotMultiplier )
							}
						}
					}
				}
			}
			
			if (s.currentVampirism > SessionState.maxVampirism)
			s.currentVampirism = SessionState.maxVampirism;
		}
		
		
			
	}
}