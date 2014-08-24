#include <sourcemod>
#include <regex>
#include <socket>
#include <base64>

new const String:g_szRadioUrl[] = "http://hive365.co.uk/plugin/player/";
new const String:PLUGIN_VERSION[] = "3.0.1";
new const DEFAULT_VOLUME = 20;
new const String:szSearch[][] = {"\\x26amp;", "\\"};
new const String:szReplace[][] = {"&", ""};


new bool:bIsTunedIn[MAXPLAYERS+1] = {false, ...};
new Handle:hHelpMenu = INVALID_HANDLE;
new Handle:hVolumeMenu = INVALID_HANDLE;
new Handle:hRadioTunedMenu = INVALID_HANDLE;
new Handle:hEnabled = INVALID_HANDLE;
new String:szCurrentDJ[64] = "";
new String:szCurrentSong[256] = "";
new Handle:hRegexSong;
new Handle:hRegexDJ;
new const Float:fRefresh = 30.0;
new Handle:hReqTrie = INVALID_HANDLE;
new Handle:hShoutTrie = INVALID_HANDLE;
new Handle:hRateTrie = INVALID_HANDLE;
new Handle:hFTWTrie = INVALID_HANDLE;
new Handle:hHostname = INVALID_HANDLE;
new String:szEncodedHost[256];

enum RadioOptions
{
	Radio_Volume,
	Radio_Off,
	Radio_Help,
};
enum SocketInfo
{
	SocketInfo_Info,
	SocketInfo_Request,
	SocketInfo_Shoutout,
	SocketInfo_Choon,
	SocketInfo_Poon,
	SocketInfo_DjFtw,
};

public Plugin:myinfo = 
{
	name = "Hive365 Player",
	author = "Hive365.co.uk",
	description = "Hive365 In-Game Radio Player",
	version = PLUGIN_VERSION,
	url = "http://www.hive365.co.uk"
}

public OnPluginStart()
{
	hReqTrie = CreateTrie();
	hShoutTrie = CreateTrie();
	hRateTrie = CreateTrie();
	hFTWTrie = CreateTrie();
	
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
	
	hEnabled = CreateConVar("sm_hive365radio_enabled", "1", "Enable the radio?", _, true, 0.0, true, 1.0);
	CreateConVar("sm_hive365radio_version", PLUGIN_VERSION, "Hive365 Radio Plugin Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	AutoExecConfig();
	
	hRadioTunedMenu = CreateMenu(RadioTunedMenuHandle);
	SetMenuTitle(hRadioTunedMenu, "Radio Options");
	AddMenuItem(hRadioTunedMenu, "0", "Adjust Volume");
	AddMenuItem(hRadioTunedMenu, "1", "Stop Radio");
	AddMenuItem(hRadioTunedMenu, "2", "Radio Help");
	SetMenuExitButton(hRadioTunedMenu, true);
	
	hVolumeMenu = CreateMenu(RadioVolumeMenuHandle);
	SetMenuTitle(hVolumeMenu, "Volume Options");
	AddMenuItem(hVolumeMenu, "1", "Volume: 1%");
	AddMenuItem(hVolumeMenu, "5", "Volume: 5%");
	AddMenuItem(hVolumeMenu, "10", "Volume: 10%");
	AddMenuItem(hVolumeMenu, "20", "Volume: 20% (default)");
	AddMenuItem(hVolumeMenu, "30", "Volume: 30%");
	AddMenuItem(hVolumeMenu, "40", "Volume: 40%");
	AddMenuItem(hVolumeMenu, "50", "Volume: 50%");
	AddMenuItem(hVolumeMenu, "75", "Volume: 75%");
	AddMenuItem(hVolumeMenu, "100", "Volume: 100%");
	SetMenuExitButton(hVolumeMenu, true);
	
	hHelpMenu = CreateMenu(HelpMenuHandle);
	SetMenuTitle(hHelpMenu, "Radio Help");
	AddMenuItem(hHelpMenu, "0", "Type sm_radio in console (!radio in chat) to tune in");
	AddMenuItem(hHelpMenu, "1", "Type sm_dj in console (!dj in chat) to get dj info");
	AddMenuItem(hHelpMenu, "2", "Type sm_song in console (!song in chat) to get the song info");
	AddMenuItem(hHelpMenu, "3", "Type sm_choon in console (!choon in chat) to like a song");
	AddMenuItem(hHelpMenu, "4", "Type sm_poon in console (!poon in chat) to dislike a song");
	AddMenuItem(hHelpMenu, "-1", "Type sm_request song name in console (!request song name in chat) to request a song");
	AddMenuItem(hHelpMenu, "-1", "Type sm_shoutout shoutout in console (!shoutout shoutout in chat) to request a shoutout");
	AddMenuItem(hHelpMenu, "-1", "NOTE: You must have HTML MOTD enabled!");
	SetMenuExitButton(hHelpMenu, true);
	
	hRegexDJ = CompileRegex("(.*)(\"title\")(.*?)\"(.*?)\",\"");
	hRegexSong = CompileRegex("(.*)(\"artist_song\")(.*?)\"(.*?)\"}");
	MakeSocketRequest(SocketInfo_Info, 0, "");
	CreateTimer(fRefresh, GetStreamInfoTimer, _, TIMER_REPEAT);
	
	CreateTimer(300.0, ShowAdvert, _, TIMER_REPEAT);
	hHostname = FindConVar("hostname");
}
public OnConfigsExecuted()
{
	decl String:encodedhost[256];
	GetConVarString(hHostname, encodedhost, sizeof(encodedhost));
	EncodeBase64(szEncodedHost, sizeof(szEncodedHost), encodedhost);
	ClearTrie(hReqTrie);
	ClearTrie(hShoutTrie);
	ClearTrie(hRateTrie);
}
public Action:GetStreamInfoTimer(Handle:timer)
{
	MakeSocketRequest(SocketInfo_Info, 0, "");
}
public Action:ShowAdvert(Handle:timer)
{
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !bIsTunedIn[i])
		{
			PrintToChat(i, "\x01 \x04[Hive365] This server is running Hive365 Radio type !radiohelp for Help!");
		}
	}
}
public OnClientDisconnect(client)
{
	bIsTunedIn[client] = false;
}
public OnClientPutInServer(client)
{
	new serial = GetClientSerial(client);
	bIsTunedIn[client] = false;
	CreateTimer(15.0, HelpMessage, serial, TIMER_FLAG_NO_MAPCHANGE);
}
public Action:HelpMessage(Handle:timer, any:serial)
{
	new client = GetClientFromSerial(serial);
	if(client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		PrintToChat(client, "\x01 \x04[Hive365] This server is running Hive365 Radio type !radiohelp for Help!");
	}
	
	return Plugin_Continue;
}
public Action:Cmd_DjFtw(client, args)
{
	if(client == 0  || !IsClientInGame(client))
		return Plugin_Handled;
	
	decl String:steamid[32];
	
	if(!GetClientAuthString(client, steamid, sizeof(steamid)))
		return Plugin_Handled;
	
	new value;
	
	if(GetTrieValue(hFTWTrie, steamid, value))
	{
		ReplyToCommand(client, "\x01 \x04[Hive365] You have already rated this DJFTW!");
		return Plugin_Handled;
	}
	
	SetTrieValue(hFTWTrie, steamid, 1, true);
	MakeSocketRequest(SocketInfo_DjFtw, GetClientSerial(client), "");
	
	return Plugin_Handled;
}
public Action:Cmd_Shoutout(client, args)
{
	if(client == 0  || !IsClientInGame(client))
		return Plugin_Handled;
	
	if(args <= 0)
	{
		ReplyToCommand(client, "\x01 \x04[Hive365] sm_shoutout <shoutout> or !shoutout <shoutout>");
		return Plugin_Handled;
	}
	
	decl String:steamid[32];
	
	if(!GetClientAuthString(client, steamid, sizeof(steamid)))
		return Plugin_Handled;
	
	new Float:value;
	
	if(GetTrieValue(hShoutTrie, steamid, value) && value+(3*60) > GetEngineTime())
	{
		ReplyToCommand(client, "\x01 \x04[Hive365] Please wait a few minutes between Shoutouts.");
		return Plugin_Handled;
	}
	
	SetTrieValue(hShoutTrie, steamid, GetEngineTime());
	
	decl String:buffer[128];
	GetCmdArgString(buffer, sizeof(buffer));
	
	if(strlen(buffer) > 3)
		MakeSocketRequest(SocketInfo_Shoutout, GetClientSerial(client), buffer);
	
	return Plugin_Handled;
}
public Action:Cmd_Choon(client, args)
{
	if(client == 0  || !IsClientInGame(client))
		return Plugin_Handled;
	
	decl String:steamid[32];
	
	if(!GetClientAuthString(client, steamid, sizeof(steamid)))
		return Plugin_Handled;
	
	new Float:value;
	
	if(GetTrieValue(hRateTrie, steamid, value) && value+(3*60) > GetEngineTime())
	{
		ReplyToCommand(client, "\x01 \x04[Hive365] Please wait a few minutes between Choons and Poons");
		return Plugin_Handled;
	}
	
	SetTrieValue(hRateTrie, steamid, GetEngineTime());
	
	PrintToChatAll("\x01 \x04[Hive365] %N thinks that %s is a banging Choon!", client, szCurrentSong);
	MakeSocketRequest(SocketInfo_Choon, GetClientSerial(client), "");
	return Plugin_Handled;
}
public Action:Cmd_Poon(client, args)
{
	if(client == 0  || !IsClientInGame(client))
		return Plugin_Handled;
	
	decl String:steamid[32];

	if(!GetClientAuthString(client, steamid, sizeof(steamid)))
		return Plugin_Handled;
	
	new Float:value;
	
	if(GetTrieValue(hRateTrie, steamid, value) && value+(3*60) > GetEngineTime())
	{
		ReplyToCommand(client, "\x01 \x04[Hive365] Please wait a few minutes between Choons and Poons");
		return Plugin_Handled;
	}
	
	SetTrieValue(hRateTrie, steamid, GetEngineTime());
	
	PrintToChatAll("\x01 \x04[Hive365] %N thinks that %s  is a bit of a naff Poon!", client, szCurrentSong);
	MakeSocketRequest(SocketInfo_Poon, GetClientSerial(client), "");
	return Plugin_Handled;
}
public Action:Cmd_Request(client, args)
{
	if(client == 0  || !IsClientInGame(client))
		return Plugin_Handled;
	
	if(args <= 0)
	{
		ReplyToCommand(client, "\x01 \x04[Hive365] sm_request <request> or !request <request>");
		return Plugin_Handled;
	}
	
	decl String:steamid[32];
	
	if(!GetClientAuthString(client, steamid, sizeof(steamid)))
		return Plugin_Handled;
	
	new Float:value;
	
	if(GetTrieValue(hReqTrie, steamid, value) && value+(3*60) > GetEngineTime())
	{
		ReplyToCommand(client, "\x01 \x04[Hive365] Please wait a few minutes between Requests");
		return Plugin_Handled;
	}
	
	SetTrieValue(hReqTrie, steamid, GetEngineTime());
	
	decl String:buffer[128];
	GetCmdArgString(buffer, sizeof(buffer));
	
	if(strlen(buffer) > 3)
		MakeSocketRequest(SocketInfo_Request, GetClientSerial(client), buffer);
	
	return Plugin_Handled;
}
public Action:Cmd_RadioHelp(client, args)
{
	if(client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		DisplayMenu(hHelpMenu, client, 30);
	}
	return Plugin_Handled;
}
public Action:Cmd_RadioMenu(client, args)
{
	if(client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		DisplayRadioMenu(client);
	}
	return Plugin_Handled;
}
public Action:Cmd_SongInfo(client, args)
{
	if(client == 0 || !IsClientInGame(client))
		return Plugin_Handled;
		
	ReplyToCommand(client, "\x01 \x04[Hive365] Current Song is: %s", szCurrentSong);
	
	return Plugin_Handled;
}
public Action:Cmd_DjInfo(client, args)
{
	if(client == 0  || !IsClientInGame(client))
		return Plugin_Handled;
		
	ReplyToCommand(client, "\x01 \x04[Hive365] Your DJ is: %s", szCurrentDJ);
	
	return Plugin_Handled;
}
DisplayRadioMenu(client)
{
	if(GetConVarBool(hEnabled))
	{
		if(!bIsTunedIn[client])
		{
			decl String:szURL[sizeof(g_szRadioUrl) + 15];
			Format(szURL, sizeof(szURL), "%s?volume=%i", g_szRadioUrl, DEFAULT_VOLUME);
			LoadMOTDPanel(client, "Hive365", szURL, false);
			bIsTunedIn[client] = true;
		}
		DisplayMenu(hRadioTunedMenu, client, 30);
	}
	else
	{
		PrintToChat(client, "\x01 \x04[Hive365] Hive365 is currently disabled");
	}
}
public RadioTunedMenuHandle(Handle:menu, MenuAction:action, client, option)
{
	if(action == MenuAction_Select && IsClientInGame(client))
	{
		new String:radiooption[32];
		if(!GetMenuItem(menu, option, radiooption, sizeof(radiooption)))
		{
			PrintToChat(client, "\x01 \x04[Hive365] Unknown option selected");
		}
		switch(RadioOptions:StringToInt(radiooption))
		{
			case Radio_Volume:
			{
				DisplayMenu(hVolumeMenu, client, 30);
			}
			case Radio_Off:
			{
				if(bIsTunedIn[client])
				{
					PrintToChat(client, "\x01 \x04[Hive365] Radio has been turned off. Thanks for listening!");
					LoadMOTDPanel(client, "Thanks for listening", "about:blank", false);
					bIsTunedIn[client] = false;
				}
			}
			case Radio_Help:
			{
				DisplayMenu(hHelpMenu, client, 30);
			}
		}
	}
}
public RadioVolumeMenuHandle(Handle:menu, MenuAction:action, client, option)
{
	if(action == MenuAction_Select && IsClientInGame(client))
	{
		new String:szVolume[10];
		if(!GetMenuItem(menu, option, szVolume, sizeof(szVolume)))
		{
			PrintToChat(client, "\x01 \x04[Hive365] Unknown option selected.");
		}
		new volume = StringToInt(szVolume);
		
		decl String:szURL[sizeof(g_szRadioUrl) + 15];
		Format(szURL, sizeof(szURL), "%s?volume=%i", g_szRadioUrl, volume);
		LoadMOTDPanel(client, "Hive365", szURL, false);
		bIsTunedIn[client] = true;
	}
}
public HelpMenuHandle(Handle:menu, MenuAction:action, client, item)
{
	if(action == MenuAction_Select && IsClientInGame(client))
	{
		new String:option[32];
		if(!GetMenuItem(menu, item, option, sizeof(option)))
		{
			PrintToChat(client, "\x01 \x04[Hive365] Unknown option selected.");
		}
		switch(StringToInt(option))
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
				Cmd_Choon(client, 0)
			}
			case 4:
			{
				Cmd_Poon(client, 0)
			}
		}
	}
}
public LoadMOTDPanel(client, const String:title[], const String:page[], bool:display)
{
	if(client == 0  || !IsClientInGame(client))
		return;
	
	new Handle:kv = CreateKeyValues("data");

	KvSetString(kv, "title", title);
	KvSetNum(kv, "type", MOTDPANEL_TYPE_URL);
	KvSetString(kv, "msg", page);

	ShowVGUIPanel(client, "info", kv, display);
	CloseHandle(kv);
}
MakeSocketRequest(SocketInfo:type, serial, const String:buffer[])
{
	new Handle:socket = SocketCreate(SOCKET_TCP, OnSocketError);
	new Handle:pack = CreateDataPack();
	WritePackCell(pack, _:type);
	if(type != SocketInfo_Info)
	{
		WritePackCell(pack, serial);
		WritePackString(pack, buffer);
	}
	SocketSetArg(socket, pack);
	if(type == SocketInfo_Info)
	{
		SocketConnect(socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, "data.hive365.co.uk", 80);
	}
	else
	{
		SocketConnect(socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, "www.hive365.co.uk", 80);
	}
}
public OnSocketConnected(Handle:socket, any:pack) 
{
	decl String:requestStr[1024];
	ResetPack(pack);
	new SocketInfo:type = SocketInfo:_:ReadPackCell(pack);
	
	if(type == SocketInfo_Info)
	{
		Format(requestStr, sizeof(requestStr), "GET /%s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n", "stream/info.php", "data.hive365.co.uk");
	}
	else if(type == SocketInfo_Request || type == SocketInfo_Shoutout || type == SocketInfo_DjFtw)
	{
		new client = GetClientFromSerial(ReadPackCell(pack));
		
		if(client == 0 || !IsClientInGame(client))
			return;
		
		decl String:buffer[128];
		ReadPackString(pack, buffer, sizeof(buffer));
		decl String:urlRequest[256];
		decl String:encodedbuff[512];
		if(type == SocketInfo_DjFtw)
		{
			EncodeBase64(encodedbuff, sizeof(encodedbuff), szCurrentDJ);
		}
		else
		{
			EncodeBase64(encodedbuff, sizeof(encodedbuff), buffer);
		}
		decl String:name[MAX_NAME_LENGTH];
		
		if(!GetClientName(client, name, sizeof(name)))
			return;
		
		decl String:encodedname[256];
		EncodeBase64(encodedname, sizeof(encodedname), name);
		if(type == SocketInfo_DjFtw)
		{
			Format(urlRequest, sizeof(urlRequest), "plugin/djrate.php?n=%s&s=%s&host=%s", encodedname, encodedbuff, szEncodedHost);
		}
		else if(type == SocketInfo_Shoutout)
		{
			Format(urlRequest, sizeof(urlRequest), "plugin/shoutout.php?n=%s&s=%s&host=%s", encodedname, encodedbuff, szEncodedHost);
		}
		else
		{
			Format(urlRequest, sizeof(urlRequest), "plugin/request.php?n=%s&s=%s&host=%s", encodedname, encodedbuff, szEncodedHost);
		}
		Format(requestStr, sizeof(requestStr), "GET /%s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n", urlRequest, "www.hive365.co.uk");
	}
	else if(type == SocketInfo_Choon || type == SocketInfo_Poon)
	{
		new client = GetClientFromSerial(ReadPackCell(pack));
		
		if(client == 0 || !IsClientInGame(client))
			return;
		
		decl String:name[MAX_NAME_LENGTH];
		
		if(!GetClientName(client, name, sizeof(name)))
			return;
		
		decl String:encodedname[256];
		EncodeBase64(encodedname, sizeof(encodedname), name);
		
		new t = 3;
		if(type == SocketInfo_Poon)
		{
			t = 4;
		}
		Format(requestStr, sizeof(requestStr), "GET /plugin/song_rate.php?n=%s&t=%i&host=%s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n", encodedname, t, szEncodedHost, "www.hive365.co.uk");
	}
	SocketSend(socket, requestStr);
}

public OnSocketReceive(Handle:socket, String:receiveData[], const dataSize, any:pack) 
{
	ResetPack(pack);
	new SocketInfo:type = SocketInfo:_:ReadPackCell(pack);
	
	if(SocketInfo:type == SocketInfo_Info)
	{
		ParseSocketInfo(receiveData);
	}
}

public OnSocketDisconnected(Handle:socket, any:pack) 
{
	ResetPack(pack);
	new SocketInfo:type = SocketInfo:_:ReadPackCell(pack);
	if(type == SocketInfo_Request || type == SocketInfo_Shoutout || type == SocketInfo_DjFtw)
	{
		new client = GetClientFromSerial(ReadPackCell(pack));
		
		if(client != 0 && IsClientInGame(client))
		{
			if(type == SocketInfo_DjFtw)
			{
				PrintToChatAll("\x01 \x04[Hive365] %N thinks %s is a banging DJ!", client, szCurrentDJ);
			}
			else if(type == SocketInfo_Shoutout)
			{
				PrintToChat(client, "\x01 \x04[Hive365] Your Shoutout has been sent!");
			}
			else
			{
				PrintToChat(client, "\x01 \x04[Hive365] Your Request has been sent!");
			}
		}
	}
	
	CloseHandle(pack);
	CloseHandle(socket);
}

public OnSocketError(Handle:socket, const errorType, const errorNum, any:pack) 
{
	ResetPack(pack);
	new SocketInfo:type = SocketInfo:_:ReadPackCell(pack);
	
	if(type == SocketInfo_Info)
	{
		strcopy(szCurrentSong, sizeof(szCurrentSong), "Unknown");
		strcopy(szCurrentDJ, sizeof(szCurrentDJ), "AutoDj");
	}
	LogError("[Hive365] socket error %d (errno %d)", errorType, errorNum);
	CloseHandle(socket);
	CloseHandle(pack);
}
ParseSocketInfo(String:receiveData[])
{
	new String:song[256] = "Unknown";
	new String:dj[64] = "AutoDj";

	if(MatchRegex(hRegexSong, receiveData) >= 1)
	{
		GetRegexSubString(hRegexSong, 4, song, sizeof(song));
		
		CleanInfo(song, sizeof(song));
		
		if(!StrEqual(song, szCurrentSong, false))
		{
			strcopy(szCurrentSong, sizeof(szCurrentSong), song);
			PrintToChatAll("\x01 \x04[Hive365] Now Playing: %s", szCurrentSong);
		}
	}
		
	if(MatchRegex(hRegexDJ, receiveData) >= 1)
	{
		GetRegexSubString(hRegexDJ, 4, dj, sizeof(dj));
		
		CleanInfo(dj, sizeof(dj));
		
		if(!StrEqual(dj, szCurrentDJ, false))
		{
			strcopy(szCurrentDJ, sizeof(szCurrentDJ), dj);
			ClearTrie(hFTWTrie);
			PrintToChatAll("\x01 \x04[Hive365] Your DJ is: %s", szCurrentDJ);
		}
	}
}
CleanInfo(String:str[], size)
{
	for(new i = 0; i < sizeof(szSearch); i++)
	{
		ReplaceString(str, size, szSearch[i], szReplace[i], false);
	}
}