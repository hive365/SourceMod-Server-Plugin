#include <sourcemod>
#include <ripext>
		
#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL    "https://raw.githubusercontent.com/hive365/SourceMod-Server-Plugin/master/updatefile.txt"

#undef REQUIRE_EXTENSIONS

#pragma semicolon 1
#pragma newdecls required

//Defines
#define PLUGIN_VERSION	"5.1.0"
char RADIO_PLAYER_URL[] = "https://player.hive365.radio/minimal";
#define DEFAULT_RADIO_VOLUME 20

//Timer defines
#define INFO_REFRESH_RATE 30.0
#define HIVE_ADVERT_RATE 600.0
#define HELP_TIMER_DELAY 15.0


//Menu Handles
Menu menuHelp;
Menu menuVolume;
Menu menuTuned;

//Tracked Information
char szGameType[256];
char szHostPort[16];
char szHostName[256];
char szHostIP[32];
char szCurrentSong[256];
char szCurrentDJ[64];
bool bIsTunedIn[MAXPLAYERS+1];

//CVars
ConVar convarEnabled;

//Voting Trie's
StringMap stringmapRate;
StringMap stringmapRequest;
StringMap stringmapShoutout;
StringMap stringmapDJFTW;

//enum's
enum RadioOptions
{
	Radio_Volume,
	Radio_Off,
	Radio_Help,
};

enum RequestInfo
{
	RequestInfo_Info,
	RequestInfo_SongRequest,
	RequestInfo_Shoutout,
	RequestInfo_Choon,
	RequestInfo_Poon,
	RequestInfo_DjFtw,
	RequestInfo_HeartBeat,
	RequestInfo_PublicIP,
};

public Plugin myinfo = 
{
	name = "Hive365 Player",
	author = "Hive365.radio",
	description = "Hive365 In-Game Radio Player",
	version = PLUGIN_VERSION,
	url = "https://hive365.radio"
}

public void OnPluginStart()
{
	stringmapRate = new StringMap();
	stringmapRequest = new StringMap();
	stringmapShoutout = new StringMap();
	stringmapDJFTW = new StringMap();
	
	RegConsoleCmd("sm_radio", Cmd_RadioMenu);
	RegConsoleCmd("sm_radiohelp", Cmd_RadioHelp);
	RegConsoleCmd("sm_dj", Cmd_DjInfo);
	RegConsoleCmd("sm_song", Cmd_SongInfo);
	RegConsoleCmd("sm_shoutout", Cmd_Shoutout);
	RegConsoleCmd("sm_request", Cmd_Request);
	RegConsoleCmd("sm_choon", Cmd_Choon);
	RegConsoleCmd("sm_poon", Cmd_Poon);
	RegConsoleCmd("sm_req", Cmd_Request);
	RegConsoleCmd("sm_ch", Cmd_Choon);
	RegConsoleCmd("sm_p", Cmd_Poon);
	RegConsoleCmd("sm_sh", Cmd_Shoutout);
	RegConsoleCmd("sm_djftw", Cmd_DjFtw);
	
	convarEnabled = CreateConVar("sm_hive365radio_enabled", "1", "Enable the radio?", _, true, 0.0, true, 1.0);
	CreateConVar("sm_hive365radio_version", PLUGIN_VERSION, "Hive365 Radio Plugin Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	AutoExecConfig();
	
	menuTuned = new Menu(RadioTunedMenuHandle);
	menuTuned.SetTitle("Radio Options");
	//menuTuned.AddItem("0", "Adjust Volume");
	menuTuned.AddItem("0", "Start Radio (Will open motd window to play and adjust volume)");
	menuTuned.AddItem("1", "Stop Radio");
	menuTuned.AddItem("2", "Radio Help");
	menuTuned.ExitButton = true;
	
	menuVolume = new Menu(RadioVolumeMenuHandle);
	menuVolume.SetTitle("Radio Options");
	menuVolume.AddItem("1", "Volume: 1%");
	menuVolume.AddItem("5", "Volume: 5%");
	menuVolume.AddItem("10", "Volume: 10%");
	menuVolume.AddItem("20", "Volume: 20% (default)");
	menuVolume.AddItem("30", "Volume: 30%");
	menuVolume.AddItem("40", "Volume: 40%");
	menuVolume.AddItem("50", "Volume: 50%");
	menuVolume.AddItem("75", "Volume: 75%");
	menuVolume.AddItem("100", "Volume: 100%");
	if(GetEngineVersion() != Engine_CSGO)// We could remove one for csgo maybe
	{
		menuVolume.Pagination = MENU_NO_PAGINATION;
	}
	menuVolume.ExitButton = true;
	
	menuHelp = new Menu(HelpMenuHandle);
	menuHelp.SetTitle("Radio Help");
	menuHelp.AddItem("0", "Type !radio in chat to tune in");
	menuHelp.AddItem("1", "Type !dj in chat to get dj info");
	menuHelp.AddItem("2", "Type !song in chat to get the song info");
	menuHelp.AddItem("3", "Type !choon in chat if you like a song");
	menuHelp.AddItem("4", "Type !poon in chat if you dislike a song");
	menuHelp.AddItem("-1", "Type !request song name in chat to request a song");
	menuHelp.AddItem("-1", "Type !shoutout shoutout in chat to request a shoutout");
	menuHelp.AddItem("-1", "NOTE: Currently broken for CS:GO");
	menuHelp.AddItem("-1", "NOTE: You must have HTML MOTD enabled!");
	menuHelp.Pagination = MENU_NO_PAGINATION;
	menuHelp.ExitButton = true;
	
	ConVar gametype = FindConVar("hostname");

	if(gametype)
	{
		gametype.GetString(szGameType, sizeof(szGameType));
	}
	
	ConVar showInfo = FindConVar("host_info_show"); //CS:GO Only... for now
	if(showInfo)
	{
		if(showInfo.IntValue < 1)
		{
			showInfo.IntValue = 1;
		}
		showInfo.AddChangeHook(HookShowInfo);
	}
		   
	MakeHTTPRequest(RequestInfo_Info, 0, "");
		   
	CreateTimer(HIVE_ADVERT_RATE, ShowAdvert, _, TIMER_REPEAT);
	CreateTimer(INFO_REFRESH_RATE, GetStreamInfoTimer, _, TIMER_REPEAT);
	
	for(int i = 0; i <= MaxClients; i++)
	{
		bIsTunedIn[i] = false;
	}
	
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public void OnMapStart()
{
	stringmapRate.Clear();
	stringmapRequest.Clear();
	stringmapShoutout.Clear();
	stringmapDJFTW.Clear();
	MakeHTTPRequest(RequestInfo_HeartBeat, 0, "");
}

public void OnClientDisconnect(int client)
{
	bIsTunedIn[client] = false;
}

public void OnClientPutInServer(int client)
{
	int serial = GetClientSerial(client);
	bIsTunedIn[client] = false;
	CreateTimer(HELP_TIMER_DELAY, HelpMessage, serial, TIMER_FLAG_NO_MAPCHANGE);
}

public void HookShowInfo(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(convar.IntValue < 1)
	{
		convar.IntValue = 1;
	}
}

//Timer Handlers
public Action GetStreamInfoTimer(Handle timer)
{
	MakeHTTPRequest(RequestInfo_Info, 0, "");
	MakeHTTPRequest(RequestInfo_HeartBeat, 0, "");
	return Plugin_Continue;
}

public Action ShowAdvert(Handle timer)
{	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !bIsTunedIn[i])
		{
			PrintToChat(i, "\x01[\x04Hive365\x01] \x04This server is running Hive365 Radio type !radiohelp for Help!");
		}
	}
	return Plugin_Continue;
}

public Action HelpMessage(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);
	if(client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		PrintToChat(client, "\x01[\x04Hive365\x01] \x04This server is running Hive365 Radio type !radiohelp for Help!");
	}
	return Plugin_Continue;
}

//Command Handlers
public Action Cmd_DjFtw(int client, int args)
{
	if(client == 0 || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	if(!HandleSteamIDTracking(stringmapDJFTW, client))
	{
		ReplyToCommand(client, "\x01[\x04Hive365\x01] \x04You have already rated this DJFTW!");
		return Plugin_Handled;
	}
	
	MakeHTTPRequest(RequestInfo_DjFtw, client, "");
	
	return Plugin_Handled;
}

public Action Cmd_Shoutout(int client, int args)
{
	if(client == 0 || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	if(args <= 0)
	{
		ReplyToCommand(client, "\x01[\x04Hive365\x01] \x04sm_shoutout <shoutout> or !shoutout <shoutout>");
		return Plugin_Handled;
	}
	
	if(!HandleSteamIDTracking(stringmapShoutout, client, true, 10))
	{
		ReplyToCommand(client, "\x01[\x04Hive365\x01] \x04Please wait a few minutes between Shoutouts.");
		return Plugin_Handled;
	}
	
	char buffer[128];
	GetCmdArgString(buffer, sizeof(buffer));
	
	if(strlen(buffer) > 3)
	{
		MakeHTTPRequest(RequestInfo_Shoutout, client, buffer);
	}
	
	return Plugin_Handled;
}

public Action Cmd_Choon(int client, int args)
{
	if(client == 0 || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	if(!HandleSteamIDTracking(stringmapRate, client, true, 5))
	{
		ReplyToCommand(client, "\x01[\x04Hive365\x01] \x04Please wait a few minutes between Choons and Poons");
		return Plugin_Handled;
	}
	
	PrintToChatAll("\x01[\x04Hive365\x01] \x04%N thinks that %s is a banging Choon!", client, szCurrentSong);
	
	MakeHTTPRequest(RequestInfo_Choon, client, "");
	
	return Plugin_Handled;
}

public Action Cmd_Poon(int client, int args)
{
	if(client == 0 || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	if(!HandleSteamIDTracking(stringmapRate, client, true, 5))
	{
		ReplyToCommand(client, "\x01[\x04Hive365\x01] \x04Please wait a few minutes between Choons and Poons");
		return Plugin_Handled;
	}
	
	PrintToChatAll("\x01[\x04Hive365\x01] \x04%N thinks that %s  is a bit of a naff Poon!", client, szCurrentSong);
	
	MakeHTTPRequest(RequestInfo_Poon, client, "");
	
	return Plugin_Handled;
}

public Action Cmd_Request(int client, int args)
{
	if(client == 0 || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}
	
	if(args <= 0)
	{
		ReplyToCommand(client, "\x01[\x04Hive365\x01] \x04sm_request <request> or !request <request>");
		return Plugin_Handled;
	}
	
	if(!HandleSteamIDTracking(stringmapRequest, client, true, 10))
	{
		ReplyToCommand(client, "\x01[\x04Hive365\x01] \x04Please wait a few minutes between Requests");
		return Plugin_Handled;
	}
	
	char buffer[128];
	GetCmdArgString(buffer, sizeof(buffer));
	
	if(strlen(buffer) > 3)
	{
		MakeHTTPRequest(RequestInfo_SongRequest, client, buffer);
	}
	
	return Plugin_Handled;
}

public Action Cmd_RadioHelp(int client, int args)
{
	if(client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		menuHelp.Display(client, 30);
	}
	
	return Plugin_Handled;
}

public Action Cmd_RadioMenu(int client, int args)
{
	if(client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		menuTuned.Display(client, 30);
		//DisplayRadioMenu(client);
	}
	
	return Plugin_Handled;
}

public Action Cmd_SongInfo(int client, int args)
{
	if(client == 0 || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}
		
	ReplyToCommand(client, "\x01[\x04Hive365\x01] \x04Current Song is: %s", szCurrentSong);
	
	return Plugin_Handled;
}

public Action Cmd_DjInfo(int client, int args)
{
	if(client == 0 || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}
		
	ReplyToCommand(client, "\x01[\x04Hive365\x01] \x04Your DJ is: %s", szCurrentDJ);
	
	return Plugin_Handled;
}

//Menu Handlers
public int RadioTunedMenuHandle(Menu menu, MenuAction action, int client, int option)
{
	if(action == MenuAction_Select && IsClientInGame(client))
	{
		char radiooption[3];
		if(!menu.GetItem(option, radiooption, sizeof(radiooption)))
		{
			PrintToChat(client, "\x01[\x04Hive365\x01] \x04Unknown option selected");
		}
		switch(view_as<RadioOptions>(StringToInt(radiooption)))
		{
			case Radio_Volume:
			{
				if(client > 0 && client <= MaxClients && IsClientInGame(client))
				{
					DisplayRadioMenu(client);
				}
				//menuVolume.Display(client, 30);
			}
			case Radio_Off:
			{
				if(bIsTunedIn[client])
				{
					PrintToChat(client, "\x01[\x04Hive365\x01] \x04Radio has been turned off. Thanks for listening!");
					
					LoadMOTDPanel(client, "Thanks for listening", "about:blank", false);
					
					bIsTunedIn[client] = false;
				}
			}
			case Radio_Help:
			{
				menuHelp.Display(client, 30);
			}
		}
	}
	return 0;
}

public int RadioVolumeMenuHandle(Menu menu, MenuAction action, int client, int option)
{
	if(action == MenuAction_Select && IsClientInGame(client))
	{
		char szVolume[10];
		
		if(!menu.GetItem(option, szVolume, sizeof(szVolume)))
		{
			PrintToChat(client, "\x01[\x04Hive365\x01] \x04Unknown option selected.");
		}
		
		char szURL[sizeof(RADIO_PLAYER_URL) + 15];
		
		Format(szURL, sizeof(szURL), RADIO_PLAYER_URL);
	
		LoadMOTDPanel(client, "Hive365", szURL, false);
		
		bIsTunedIn[client] = true;
	}
	return 0;
}

public int HelpMenuHandle(Menu menu, MenuAction action, int client, int option)
{
	if(action == MenuAction_Select && IsClientInGame(client))
	{
		char radiooption[3];
		if(!menu.GetItem(option, radiooption, sizeof(radiooption)))
		{
			PrintToChat(client, "\x01[\x04Hive365\x01] \x04Unknown option selected.");
		}
		
		switch(StringToInt(radiooption))
		{
			case 0:
			{
				Cmd_RadioMenu(client, 0);
			}
			case 1:
			{
				Cmd_DjInfo(client, 0);
			}
			case 2:
			{
				Cmd_SongInfo(client, 0);
			}
			case 3:
			{
				Cmd_Choon(client, 0);
			}
			case 4:
			{
				Cmd_Poon(client, 0);
			}
		}
	}
	return 0;
}

//Functions
bool HandleSteamIDTracking(StringMap map, int client, bool checkTime = false, int timeCheck = 0)
{
	char steamid[32];
	
	if(!GetClientAuthId(client, AuthId_Engine, steamid, sizeof(steamid), true))
	{
		return false;
	}
	
	if(!checkTime)
	{
		int value;
		
		if(map.GetValue(steamid, value))
		{
			return false;
		}
		else
		{
			map.SetValue(steamid, 1, true);
			return true;
		}
	}
	else
	{
		float value;
		
		if(map.GetValue(steamid, value) && value+(timeCheck*60) > GetEngineTime())
		{
			return false;
		}
		else
		{
			map.SetValue(steamid, GetEngineTime(), true);
			return true;
		}
	}
}

void DisplayRadioMenu(int client)
{
	if(convarEnabled.BoolValue)
	{
		if(!bIsTunedIn[client])
		{
			char szURL[sizeof(RADIO_PLAYER_URL) + 15];
			
			Format(szURL, sizeof(szURL), RADIO_PLAYER_URL);
			
			LoadMOTDPanel(client, "Hive365", szURL, true);
			
			bIsTunedIn[client] = true;
		}
	}
	else
	{
		PrintToChat(client, "\x01 \x04[Hive365] Hive365 is currently disabled");
	}
}

void LoadMOTDPanel(int client, const char [] title, const char [] page, bool display)
{
	if(client == 0  || !IsClientInGame(client))
		return;
	
	KeyValues kv = new KeyValues("data");

	kv.SetString("title", title);
	kv.SetNum("type", MOTDPANEL_TYPE_URL);
	kv.SetString("msg", page);

	ShowVGUIPanel(client, "info", kv, display);
	
	delete kv;
}

// In the event that some nasty characters are attemting to be passed into a string, this decodes them.
void DecodeHTMLEntities(char [] str, int size)
{
	static char htmlEnts[][][] = 
	{
		{"&amp;", "&"},
		{"\\", ""},
		{"&lt;", "<"},
		{"&gt;", ">"}
	};
	
	for(int i = 0; i < 4; i++)
	{
		ReplaceString(str, size, htmlEnts[i][0], htmlEnts[i][1], false);
	}
}

/*
This sends out the full HTTP Request using GET, PUT, or POST.
@param requestMethod Either "GET", "PUT", or "POST" to tell the function which request to send.
@param requestInfoType The RequestInfo type that will be used in order to determine names of JSON keys, like RequestInfo_Choon.
@param urlRequest The URL that will be requested.
@param name This will be the "name" that goes into the json.
@param source This will be the "source" that goes into the json.
@param message Most requests differ when it comes to this, so this will be that third miscellaneous key that will be translated based on the requestMethod.
*/
void SendHTTPRequest(char [] requestMethod, RequestInfo requestInfoType, char [] urlRequest, char [] name, char [] source, char [] message)
{
	HTTPRequest request = new HTTPRequest(urlRequest);
		   
	if (StrEqual(requestMethod, "GET")) 
	{
		request.Get(OnHTTPResponseReceived, requestInfoType);
		return;
	}
	else
	{   
		// Only create the JSON to be inputted if requestMethod is not "GET"
		JSONObject inputtedJSON = new JSONObject();
		
		if (StrEqual(requestMethod, "PUT"))
		{
			bool ipGrabSuccess;
			if (requestInfoType == RequestInfo_HeartBeat)
			{
				char directConnect[64];

				IntToString(GetConVarInt(FindConVar("hostport")), szHostPort, sizeof(szHostPort));

				SendHTTPRequest("GET", RequestInfo_PublicIP, "http://api64.ipify.org/?format=json", "", "", "");
				// Ensure that the IP is grabbed successfully.
				if (!StrEqual(szHostIP, "") && !StrEqual(szHostIP, " ")) 
				{
					ipGrabSuccess = true;
				} 
				else 
				{
					ipGrabSuccess = false;
				}
				Format(directConnect, sizeof(directConnect), "%s:%s", szHostIP, szHostPort);

				inputtedJSON.SetString("serverName", "Test part 2 to differentiate this one from the other one");
				inputtedJSON.SetString("gameType", szGameType);
				inputtedJSON.SetString("pluginVersion", PLUGIN_VERSION);
				inputtedJSON.SetString("directConnect", directConnect);
				inputtedJSON.SetInt("currentPlayers", GetClientCount());
				inputtedJSON.SetInt("maxPlayers", MaxClients);
			}
			else if (requestInfoType == RequestInfo_SongRequest)
			{
				inputtedJSON.SetString("name", name);
				inputtedJSON.SetString("source", source);
				inputtedJSON.SetString("songName", message);
			}
			else if (requestInfoType == RequestInfo_Shoutout)
			{
				inputtedJSON.SetString("name", name);
				inputtedJSON.SetString("source", source);
				inputtedJSON.SetString("message", message);
			}

			if (requestInfoType != RequestInfo_HeartBeat) 
			{
				request.Put(view_as<JSON>(inputtedJSON), OnHTTPResponseReceived, requestInfoType); // Request normally
			}
			else
			{
				if (ipGrabSuccess)
				{
					request.Put(view_as<JSON>(inputtedJSON), OnHTTPResponseReceived, requestInfoType); // Heartbeat request only if the IP was grabbed successfully
				}
			}
		}
		else if (StrEqual(requestMethod, "POST"))
		{
			if (requestInfoType == RequestInfo_DjFtw)
			{
				inputtedJSON.SetString("name", name);
				inputtedJSON.SetString("source", source);
			}
			else if (requestInfoType == RequestInfo_Choon || requestInfoType == RequestInfo_Poon)
			{
				inputtedJSON.SetString("type", message);
				inputtedJSON.SetString("name", name);
				inputtedJSON.SetString("source", source);
			}

			request.Post(inputtedJSON, OnHTTPResponseReceived, requestInfoType);
		}
		delete inputtedJSON;
		return;
	}
}

// This parses the data received and places it into the corresponding globals, updating them and telling all users if necessary.
void ParseSongDetails(JSONObject responseData)
{
	JSONObject info = new JSONObject();
	info = view_as<JSONObject>(responseData.Get("info"));

	char artist[128];
	char songName[128];
	char artist_song[256];
	char streamer[64];

	// Pull song and its artist from the JSON.
	info.GetString("artist", artist, sizeof(artist));
	DecodeHTMLEntities(artist, sizeof(artist));
	info.GetString("title", songName, sizeof(songName));
	DecodeHTMLEntities(songName, sizeof(songName));
	Format(artist_song, sizeof(artist_song), "%s - %s", songName, artist);

	// If szCurrentSong doesn't match the one that was just grabbed, update it and tell everyone that a new song is playing. 
	if(!StrEqual(artist_song, szCurrentSong, false))
	{
		strcopy(szCurrentSong, sizeof(szCurrentSong), artist_song);
		PrintToChatAll("\x01[\x04Hive365\x01] \x04Now Playing: %s", szCurrentSong);
	}

	// Pull DJ from the JSON.
	info.GetString("streamer", streamer, sizeof(streamer));
	DecodeHTMLEntities(streamer, sizeof(streamer));
	
	// If szCurrentDJ doesn't match the one that was just grabbed, update it and tell everyone who the recently grabbed DJ is.
	if(!StrEqual(streamer, szCurrentDJ, false))
	{
		strcopy(szCurrentDJ, sizeof(szCurrentDJ), streamer);
		stringmapDJFTW.Clear();
		PrintToChatAll("\x01[\x04Hive365\x01] \x04Your DJ is: %s", szCurrentDJ);
	}

	//delete infoData;
}

/* 
This is called by many Actions such as Cmd_Request() in order to send the right requests to the server according to what needs to be sent.
@param requestType Tell the program which kind of request needs to be made.
@param client The client index, to be used when necessary. Only matters when not dealing with Heartbeat or Info.
@param buffer Many commands will have a "buffer" that will hold info passed into the command. !request <song> would have <song> stored as the buffer, and it should be passed here. 
*/
void MakeHTTPRequest(RequestInfo requestType, int client, char [] buffer)
{
	if(requestType == RequestInfo_HeartBeat)
	{
		SendHTTPRequest("PUT", requestType, "http-backend.hive365radio.com/gameserver", "", "", "");
		return;
	}
	else if(requestType == RequestInfo_Info)
	{
		SendHTTPRequest("GET", requestType, "http-backend.hive365radio.com/streamInfo/simple", "", "", "");
		return;
	}
	else if (requestType == RequestInfo_PublicIP)
	{
		SendHTTPRequest("GET", requestType, "http://api64.ipify.org/?format=json", "", "", "");
		return;
	}
	else
	{
		char szUsername[MAX_NAME_LENGTH];

		if(client == 0 || !IsClientInGame(client) || !GetClientName(client, szUsername, sizeof(szUsername)))
		{
			return;
		}
		
		switch (requestType) 
		{
			case RequestInfo_DjFtw:
			{
				SendHTTPRequest("POST", requestType, "http-backend.hive365radio.com/rating/streamer", szUsername, szGameType, "");
			}
			case RequestInfo_SongRequest:
			{
				SendHTTPRequest("PUT", requestType, "http-backend.hive365radio.com/songrequest", szUsername, szGameType, buffer);
			}
			case RequestInfo_Shoutout:
			{
				SendHTTPRequest("PUT", requestType, "http-backend.hive365radio.com/shoutout", szUsername, szGameType, buffer);
			}
			case RequestInfo_Choon:
			{
				SendHTTPRequest("POST", requestType, "http-backend.hive365radio.com/rating/song", szUsername, szGameType, "CHOON");
			}
			case RequestInfo_Poon:
			{
				SendHTTPRequest("POST", requestType, "http-backend.hive365radio.com/rating/song", szUsername, szGameType, "POON");
			}
		}
		return;
	}
}

// This is the function run when SendHTTPRequest() is called and the request is made.
void OnHTTPResponseReceived(HTTPResponse response, RequestInfo requestType)
{
	if (response.Status != HTTPStatus_OK && response.Status != HTTPStatus_Created) {
		// Failed to send or retrieve data.
		return;
	}

	if (requestType == RequestInfo_Info)
	{
		// Only create a JSON object to parse if GET was used to grab current stream info
		JSONObject responseData = view_as<JSONObject>(response.Data);
		ParseSongDetails(responseData);
		delete responseData;
		return;
	}
	else if (requestType == RequestInfo_PublicIP)
	{
		JSONObject responseData = view_as<JSONObject>(response.Data);
		responseData.GetString("ip", szHostIP, sizeof(szHostIP));
		delete responseData;
		return;
	}
}
