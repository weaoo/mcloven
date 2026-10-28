#Requires AutoHotkey v2.0
#SingleInstance Force

if (!A_IsAdmin) {
    try Run('*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"')
    catch {
        MsgBox("Run as administrator.")
    }
    ExitApp()
)

AppDir          := A_AppData "\MCLoven"
UserFlagsFile   := AppDir "\user_flags.json"
SettingsFile    := AppDir "\settings.json"
TempDir         := A_Temp "\mcloventmp"
OffsetsFile     := TempDir "\offsets.json"
LogFile         := A_ScriptDir "\..\injection_log.txt"
PresetsDir      := A_MyDocuments "\presetflags"
OFFSETS_URL     := "https://imtheo.lol/Offsets/FFlags.hpp"
OFFSETS_URL_ALT := "https://offsets.imtheo.lol/FFlags.hpp"
PREFIX_URL      := "https://raw.githubusercontent.com/soulukr78/Prefixes-FFlags/refs/heads/main/ALL%20PREFIXES%20FFLAGS.json"
OffsetsCache    := AppDir "\FFlags.hpp.cache"
PrefixCache     := AppDir "\prefixes.json.cache"

for d in [AppDir, TempDir, PresetsDir]
    if (!DirExist(d))
        DirCreate(d)

UserFlags    := []
AllOffsets   := Map()
PrefixMap    := Map()
RobloxPID    := 0
CurrentView  := "main"
LastJSONPath := ""

PREFIXES := ["DFInt","DFString","DFFlag","FInt","FString","FFlag",
             "SFFlag","SFInt","SFString","DFLog","FLog"]

Settings := Map(
    "AutoAttach",                 1,
    "AutoLaunchRoblox",           0,
    "TryAttachOnStart",           1,
    "TryAttachAfter10Min",        0,
    "AutoLoadLastJSON",           0,
    "VerifyJSON",                 0,
    "ClearNotInjectedFlags",      1,
    "RetryOnFailure",             0,
    "MinimizeAfterAttach",        0,
    "CloseAfterInject",           0,
    "FetchOffsetsOnUpdate",       1,
    "DiscordRPC",                 1,
    "MinimizeOnSystemTray",       1,
    "AutoApply",                  0,
    "ReApply",                    0
)
LoadSettings()

C_TXT   := "0xE0E0E0"
C_DIM   := "0x7F8C8D"
C_GRN   := "0x27AE60"
C_RED   := "0xE74C3C"
C_SEP   := "0x282828"

RpcScript := TempDir "\rpc.py"
if (!FileExist(RpcScript)) {
    rpcCode := "import time, pypresence`nCLIENT_ID = 1551043578862772264`nRPC = pypresence.Presence(CLIENT_ID, pipe=0)`ntry:`n    RPC.connect()`n    RPC.update(state='made by _weao', details='best open-source injector', large_image='cat', large_text='mcloven', start=int(time.time()))`n    while True:`n        time.sleep(15)`nexcept:`n    pass"
    try FileOpen(RpcScript, "w", "UTF-8").Write(rpcCode)
}

if (Settings["DiscordRPC"]) {
    try Run('pythonw "' RpcScript '"',, "Hide")
}

class MemoryEngine {
    static hProcess   := 0
    static moduleBase := 0
    static moduleSize := 400 * 1024 * 1024

    static Attach(pid) {
        if (this.hProcess) {
            DllCall("CloseHandle", "Ptr", this.hProcess)
            this.hProcess := 0
        }
        this.hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", 0, "UInt", pid, "Ptr")
        if (!this.hProcess)
            return false
        this.moduleBase := this.GetModuleBase(pid, "RobloxPlayerBeta.exe")
        return (this.moduleBase != 0)
    }

    static GetModuleBase(pid, name) {
        snap := DllCall("CreateToolhelp32Snapshot", "UInt", 0x08, "UInt", pid, "Ptr")
        if (snap = -1 || !snap)
            return 0
        structSize := (A_PtrSize = 8) ? 1064 : 548
        mod32 := Buffer(structSize, 0)
        NumPut("UInt", structSize, mod32, 0)
        if DllCall("Module32First", "Ptr", snap, "Ptr", mod32) {
            loop {
                nameOffset := (A_PtrSize = 8) ? 48 : 32
                baseOffset := (A_PtrSize = 8) ? 24 : 20
                if (StrGet(mod32.ptr + nameOffset, "UTF-8") = name) {
                    base := NumGet(mod32.ptr + baseOffset, "Ptr")
                    DllCall("CloseHandle", "Ptr", snap)
                    return base
                }
                if !DllCall("Module32Next", "Ptr", snap, "Ptr", mod32)
                    break
            }
        }
        DllCall("CloseHandle", "Ptr", snap)
        return 0
    }

    static ResolveAddr(name) {
        global AllOffsets, PREFIXES
        cleanName := StripPrefix(name)
        tryNames  := [cleanName, name]
        for idx, pfx in PREFIXES
            tryNames.Push(pfx . cleanName)
        for idx, tryName in tryNames {
            if (AllOffsets.Has(tryName))
                return this.moduleBase + AllOffsets[tryName]
        }
        return 0
    }

    static ReadInt32(addr) {
        try {
            buf := Buffer(4, 0)
            if DllCall("ReadProcessMemory", "Ptr", this.hProcess, "Ptr", addr, "Ptr", buf.ptr, "UPtr", 4, "Ptr", 0)
                return NumGet(buf, 0, "Int")
        }
        return ""
    }

    static SetFlagWithPrefixes(name, value, type) {
        addr := this.ResolveAddr(name)
        if (!addr)
            return false
        return WriteRawMemory(this.hProcess, addr, value, type)
    }

    static UninjectFlag(name) {
        global AllOffsets, PREFIXES
        cleanName := StripPrefix(name)
        tryNames  := [cleanName, name]
        for idx, pfx in PREFIXES
            tryNames.Push(pfx . cleanName)
        
        for idx, tryName in tryNames {
            if (AllOffsets.Has(tryName)) {
                addr := this.moduleBase + AllOffsets[tryName]
                nameLow := StrLower(tryName)
                isStr := (InStr(nameLow, "string") || InStr(nameLow, "log"))
                if (isStr)
                    continue
                
                isInt := (InStr(nameLow, "int"))
                buf := Buffer(4, 0)
                if (isInt) {
                    NumPut("Int", -1, buf)
                }
                DllCall("WriteProcessMemory", "Ptr", this.hProcess, "Ptr", addr, "Ptr", buf.ptr, "UPtr", 4, "Ptr", 0)
            }
        }
    }
}

WriteRawMemory(hProc, addr, value, type) {
    if (!hProc || !addr)
        return false
    try {
        buf := Buffer(8, 0)
        sz  := 0
        if (type = "bool") {
            v := (StrLower(String(value)) = "true" || value = "1") ? 1 : 0
            NumPut("Char", v, buf)
            sz := 1
        } else if (type = "int") {
            NumPut("Int", Integer(value), buf)
            sz := 4
        } else if (type = "float") {
            NumPut("Double", Float(value), buf)
            sz := 8
        } else {
            sv  := String(value)
            sz  := StrPut(sv, "UTF-8")
            buf := Buffer(sz, 0)
            StrPut(sv, buf, "UTF-8")
        }
        return DllCall("WriteProcessMemory",
            "Ptr",hProc,"Ptr",addr,"Ptr",buf.Ptr,"UInt",sz,"Ptr",0)
    } catch {
        return false
    }
}

CleanExit(*) {
    try Run('taskkill /f /im pythonw.exe',, "Hide")
    ExitApp()
}

W := 860
H := 540
M := Gui("-Caption +Border", "MCLoven Interface")
M.BackColor := "0x000000"
M.SetFont("s9 norm", "Segoe UI")

A_TrayMenu.Delete()
A_TrayMenu.Add("Open", (*) => M.Show())
A_TrayMenu.Add("Load and Auto Inject", (*) => (DoLoadJSON(), DoApplyFlags()))
A_TrayMenu.Add("Uninject", (*) => DoUninject())
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", CleanExit)
A_TrayMenu.Default := "Open"

HandleClose(*) {
    if (Settings["MinimizeOnSystemTray"]) {
        M.Hide()
    } else {
        CleanExit()
    }
}
M.OnEvent("Close", HandleClose)

global IsDragging := false, DragX := 0, DragY := 0
WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global IsDragging, DragX, DragY
    if (hwnd = M.Hwnd) {
        MouseGetPos(&mX, &mY, , , 2)
        if (mY <= 40) {
            IsDragging := true
            CoordMode("Mouse", "Screen")
            MouseGetPos(&sX, &sY)
            M.GetPos(&wX, &wY)
            DragX := sX - wX
            DragY := sY - wY
            SetTimer(DragWindow, 10)
        }
    }
}

DragWindow() {
    global IsDragging, DragX, DragY
    if (!GetKeyState("LButton", "P")) {
        IsDragging := false
        SetTimer(DragWindow, 0)
        return
    }
    CoordMode("Mouse", "Screen")
    MouseGetPos(&sX, &sY)
    M.Move(sX - DragX, sY - DragY)
}

OnMessage(0x0201, WM_LBUTTONDOWN)

M.SetFont("s10 Bold c" C_TXT, "Segoe UI")
M.Add("Text", "x0 y4 w" W " h18 Center", "MCLoven")

M.SetFont("s8 norm c" C_DIM, "Segoe UI")
FlagCounterLbl := M.Add("Text", "x0 y22 w" W " h14 Center", "0 flags")

M.SetFont("s10 norm c" C_TXT, "Segoe UI")
MinBtn   := M.Add("Text", "x" (W-60) " y8 w24 h20 Center", "—")
CloseBtn := M.Add("Text", "x" (W-30) " y8 w24 h20 Center", "✕")
MinBtn.OnEvent("Click", (*) => M.Minimize())
CloseBtn.OnEvent("Click", HandleClose)

M.Add("Text", "x0 y40 w" W " h1 Background" C_SEP)

M.SetFont("s8 norm", "Segoe UI")
BtnNavMain    := M.Add("Button", "x16  y52 w90 h28", "Home")
BtnNavConfig  := M.Add("Button", "x16  y85 w90 h28", "Settings")
BtnNavSocials := M.Add("Button", "x16  y118 w90 h28", "Socials")

BtnNavMain.OnEvent("Click", (*) => SwitchView("main"))
BtnNavConfig.OnEvent("Click", (*) => SwitchView("config"))
BtnNavSocials.OnEvent("Click", (*) => SwitchView("socials"))

M.SetFont("s9 norm c" C_TXT, "Segoe UI")
BtnAdd      := M.Add("Button", "x120 y52 w55  h28", "Add")
BtnRemove   := M.Add("Button", "x179 y52 w65  h28", "Remove")
BtnClearAll := M.Add("Button", "x248 y52 w75  h28", "Remove All")
BtnExport   := M.Add("Button", "x327 y52 w65  h28", "Export")
BtnPresets  := M.Add("Button", "x396 y52 w65  h28", "Presets")
BtnUninject := M.Add("Button", "x465 y52 w65  h28", "Uninject")

BtnApply    := M.Add("Button", "x" (W-265) " y52 w110 h28", "Apply to Roblox")
BtnKill     := M.Add("Button", "x" (W-145) " y52 w130 h28", "Kill Switch")

BtnAdd.OnEvent("Click", DoOpenAddFlagDialog)
BtnRemove.OnEvent("Click", DoRemoveSelectedFlag)
BtnClearAll.OnEvent("Click", DoClearAllFlags)
BtnExport.OnEvent("Click", DoExportFlags)
BtnPresets.OnEvent("Click", DoOpenPresetsDialog)
BtnUninject.OnEvent("Click", (*) => DoUninject())
BtnApply.OnEvent("Click", DoApplyFlags)
BtnKill.OnEvent("Click", DoKillRoblox)

SearchBox := M.Add("Edit", "x120 y90 w496 h26 c" C_TXT " Background0x0F0F0F", "Search flags...")
SearchBox.OnEvent("Change", FilterFlagList)

MainListView := M.Add("ListView", "x120 y126 w" (W-136) " h395 c" C_TXT " Background0x0F0F0F +Grid -Multi", ["#", "NAME", "TYPE", "VALUE"])
MainListView.ModifyCol(1, 40)
MainListView.ModifyCol(2, 350)
MainListView.ModifyCol(3, 90)
MainListView.ModifyCol(4, 200)

DllCall("uxtheme\SetWindowTheme", "Ptr", MainListView.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
DllCall("uxtheme\SetWindowTheme", "Ptr", SearchBox.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)

ChkDiscordRPC  := M.Add("CheckBox", "x120 y52 w350 h23 c" C_TXT " +Hidden", "Discord Rich Presence")
ChkAutoAttach  := M.Add("CheckBox", "x120 y86 w350 h23 c" C_TXT " +Hidden", "Auto Attach")
ChkClearNotInj := M.Add("CheckBox", "x120 y121 w350 h23 c" C_TXT " +Hidden", "Remove not injected flags")
ChkTrayMin     := M.Add("CheckBox", "x120 y156 w350 h23 c" C_TXT " +Hidden", "Minimize on SystemTray")

ChkAutoApply   := M.Add("CheckBox", "x120 y191 w450 h23 c" C_TXT " +Hidden", "Auto-apply flags when Roblox launches")
ChkReApply     := M.Add("CheckBox", "x120 y226 w450 h23 c" C_TXT " +Hidden", "Re-apply flags continuously (every 2s)")
ChkAutoApply.Value := Settings["AutoApply"]
ChkReApply.Value   := Settings["ReApply"]
ChkAutoApply.OnEvent("Click", UpdateSettingsValue)
ChkReApply.OnEvent("Click", UpdateSettingsValue)

ChkDiscordRPC.Value  := Settings["DiscordRPC"]
ChkAutoAttach.Value  := Settings["AutoAttach"]
ChkClearNotInj.Value := Settings["ClearNotInjectedFlags"]
ChkTrayMin.Value     := Settings["MinimizeOnSystemTray"]

ChkDiscordRPC.OnEvent("Click", UpdateSettingsValue)
ChkAutoAttach.OnEvent("Click", UpdateSettingsValue)
ChkClearNotInj.OnEvent("Click", UpdateSettingsValue)
ChkTrayMin.OnEvent("Click", UpdateSettingsValue)

SocDiscordLbl  := M.Add("Text", "x130 y56 w120 h23 c" C_TXT " +Hidden", "Discord Server")
BtnOpenDiscord := M.Add("Button", "x220 y51 w130 h26 +Hidden", "Open Discord")

SocRobloxLbl   := M.Add("Text", "x130 y96 w120 h23 c" C_TXT " +Hidden", "Roblox User")
BtnOpenRoblox  := M.Add("Button", "x220 y91 w130 h26 +Hidden", "Open Profile")

BtnOpenDiscord.OnEvent("Click", (*) => OpenDiscordApp())
BtnOpenRoblox.OnEvent("Click", (*) => OpenRobloxProfile())

M.Show("w" W " h" H)
LoadUserFlags()
RefreshMainList()

SetTimer(MonitorRoblox, 2000)
SetTimer(FetchOffsets, -300)
ManageReApplyTimer()

if (Settings["TryAttachOnStart"]) {
    pid := ProcessExist("RobloxPlayerBeta.exe")
    if (pid) {
        AttachRoblox(pid)
        if (Settings["AutoApply"])
            SetTimer(AutoApplyFlags, -3000)
    }
}

SwitchView(viewName) {
    global CurrentView, BtnAdd, BtnRemove, BtnClearAll, BtnExport, BtnPresets, BtnUninject, SearchBox, MainListView
    global BtnApply, BtnKill
    global ChkDiscordRPC, ChkAutoAttach, ChkClearNotInj, ChkTrayMin, ChkAutoApply, ChkReApply
    global SocDiscordLbl, BtnOpenDiscord, SocRobloxLbl, BtnOpenRoblox
    
    CurrentView := viewName
    
    BtnAdd.Visible        := false
    BtnRemove.Visible     := false
    BtnClearAll.Visible   := false
    BtnExport.Visible     := false
    BtnPresets.Visible    := false
    BtnUninject.Visible   := false
    BtnApply.Visible      := false
    BtnKill.Visible       := false
    SearchBox.Visible     := false
    MainListView.Visible  := false
    ChkDiscordRPC.Visible := false
    ChkAutoAttach.Visible := false
    ChkClearNotInj.Visible:= false
    ChkTrayMin.Visible    := false
    ChkAutoApply.Visible  := false
    ChkReApply.Visible    := false
    SocDiscordLbl.Visible := false
    BtnOpenDiscord.Visible:= false
    SocRobloxLbl.Visible  := false
    BtnOpenRoblox.Visible := false

    if (viewName = "main") {
        BtnAdd.Visible      := true
        BtnRemove.Visible   := true
        BtnClearAll.Visible := true
        BtnExport.Visible   := true
        BtnPresets.Visible  := true
        BtnUninject.Visible := true
        BtnApply.Visible    := true
        BtnKill.Visible     := true
        SearchBox.Visible   := true
        MainListView.Visible:= true
    } else if (viewName = "config") {
        ChkDiscordRPC.Visible  := true
        ChkAutoAttach.Visible  := true
        ChkClearNotInj.Visible := true
        ChkTrayMin.Visible     := true
        ChkAutoApply.Visible   := true
        ChkReApply.Visible     := true
    } else if (viewName = "socials") {
        SocDiscordLbl.Visible := true
        BtnOpenDiscord.Visible:= true
        SocRobloxLbl.Visible  := true
        BtnOpenRoblox.Visible := true
    }
}

OpenDiscordApp() {
    try {
        Run("discord://discord.gg/ArZHEy77Ff")
    } catch {
        try Run("https://discord.gg/ArZHEy77Ff")
    }
}

OpenRobloxProfile() {
    try {
        Run("https://www.roblox.com/pt/users/4104430697/profile?friendshipSourceType=PlayerSearch")
    }
}

UpdateSettingsValue(ctrl, *) {
    global Settings
    if (ctrl = ChkDiscordRPC)
        Settings["DiscordRPC"] := ctrl.Value
    else if (ctrl = ChkAutoAttach)
        Settings["AutoAttach"] := ctrl.Value
    else if (ctrl = ChkClearNotInj)
        Settings["ClearNotInjectedFlags"] := ctrl.Value
    else if (ctrl = ChkTrayMin)
        Settings["MinimizeOnSystemTray"] := ctrl.Value
    else if (ctrl = ChkAutoApply)
        Settings["AutoApply"] := ctrl.Value
    else if (ctrl = ChkReApply) {
        Settings["ReApply"] := ctrl.Value
        ManageReApplyTimer()
    }
    SaveSettings()
}

RefreshMainList() {
    global UserFlags, MainListView, FlagCounterLbl
    MainListView.Delete()
    for i, f in UserFlags {
        MainListView.Add(, i, f["name"], StrUpper(f["type"]), f["value"])
    }
    UpdateCounter()
}

UpdateCounter() {
    global UserFlags, AllOffsets, FlagCounterLbl
    FlagCounterLbl.Text := UserFlags.Length " flags  |  "
        . (AllOffsets.Count ? AllOffsets.Count " offsets loaded" : "offsets loading...")
}

FilterFlagList(ctrl, *) {
    global UserFlags, MainListView
    query := StrLower(Trim(ctrl.Value))
    if (query = "search flags..." || query = "") {
        RefreshMainList()
        return
    }
    MainListView.Delete()
    idx := 1
    for i, f in UserFlags {
        if (InStr(StrLower(f["name"]), query) || InStr(StrLower(f["value"]), query)) {
            MainListView.Add(, idx, f["name"], StrUpper(f["type"]), f["value"])
            idx++
        }
    }
}

DoLoadJSON() {
    global UserFlags
    path := FileSelect(1,, "Load FFlags", "JSON or TXT (*.json; *.txt)")
    if (path = "")
        return
    ext  := StrLower(SubStr(path, InStr(path, ".", , -1) + 1))
    text := ""
    try {
        text := FileRead(path, "UTF-8")
    } catch {
        text := FileRead(path)
    }
    if (text = "")
        return
    NewFlags := []
    count := (ext = "json") ? ParseJson(text, &NewFlags) : ParseTxt(text, &NewFlags)
    if (count > 0) {
        for i, nf in NewFlags {
            exists := false
            for j, f in UserFlags {
                if (f["name"] = nf["name"]) {
                    f["value"] := nf["value"]
                    f["type"]  := nf["type"]
                    exists := true
                    break
                }
            }
            if (!exists)
                UserFlags.Push(nf)
        }
        SaveUserFlags()
        RefreshMainList()
    }
}

DoRemoveSelectedFlag(*) {
    global UserFlags, MainListView
    row := MainListView.GetNext(0)
    if (!row)
        return
    flagName := MainListView.GetText(row, 2)
    for i, f in UserFlags {
        if (f["name"] = flagName) {
            UserFlags.RemoveAt(i)
            break
        }
    }
    SaveUserFlags()
    RefreshMainList()
}

DoClearAllFlags(*) {
    global UserFlags
    if (MsgBox("Clear all loaded flags?", "Confirm", 0x34) == "Yes") {
        UserFlags := []
        SaveUserFlags()
        RefreshMainList()
    }
}

DoExportFlags(*) {
    global UserFlags
    if (UserFlags.Length = 0)
        return
    path := FileSelect("S16",, "Export Flags", "JSON (*.json)")
    if (path = "")
        return
    s := "{"
    for i, f in UserFlags
        s .= '`n    "' GetPrefixedName(f["name"]) '": "' f["value"] '",'
    s := RTrim(s, ",") "`n}"
    try FileOpen(path, "w", "UTF-8").Write(s)
}

DoOpenAddFlagDialog(*) {
    global UserFlags

    aGui := Gui("-Caption +Border +Owner" M.Hwnd, "Add Flag")
    aGui.BackColor := "0x0F0F0F"
    aGui.SetFont("s9 norm c0xE0E0E0", "Segoe UI")

    aGui.Add("Text",  "x16 y14 w60  h20", "Name:")
    eName  := aGui.Add("Edit", "x80  y10 w340 h24 Background0x0F0F0F c0xE0E0E0")

    aGui.Add("Text",  "x16 y46 w60  h20", "Value:")
    eValue := aGui.Add("Edit", "x80  y42 w340 h24 Background0x0F0F0F c0xE0E0E0")

    aGui.Add("Text",  "x16 y78 w60  h20", "Type:")
    eType  := aGui.Add("DropDownList", "x80 y74 w120 Choose1", ["auto", "bool", "int", "float", "string"])

    msgLbl := aGui.Add("Text", "x16 y108 w404 h20 c0x7F8C8D", "")

    btnAddOne   := aGui.Add("Button", "x16  y136 w195 h30", "Add Flag")
    btnDone     := aGui.Add("Button", "x219 y136 w200 h30", "Done")
    btnFromFile := aGui.Add("Button", "x16 y174 w403 h30", "Add from File")
    btnCancel   := aGui.Add("Text",   "x422 y12  w18  h18 Center", "✕")

    btnCancel.OnEvent("Click",  (*) => aGui.Destroy())
    btnDone.OnEvent(  "Click",  (*) => aGui.Destroy())
    btnAddOne.OnEvent("Click",  AddOneFlag)
    btnFromFile.OnEvent("Click", AddFromFile)
    eName.OnEvent("Change", (*) => msgLbl.Text := "")

    AddOneFlag(*) {
        rawName  := Trim(eName.Value)
        rawValue := Trim(eValue.Value)
        rawType  := eType.Text

        if (rawName = "") {
            msgLbl.Text := "Name cannot be empty."
            return
        }

        cleanName := StripPrefix(rawName)
        resolvedType := (rawType = "auto") ? InferType(rawValue) : rawType

        for i, f in UserFlags {
            if (f["name"] = cleanName) {
                f["value"] := rawValue
                f["type"]  := resolvedType
                SaveUserFlags()
                RefreshMainList()
                msgLbl.Text := "Updated existing flag: " cleanName
                eValue.Value := ""
                eName.Value  := ""
                eName.Focus()
                return
            }
        }

        UserFlags.Push(Map("name", cleanName, "value", rawValue, "type", resolvedType))
        SaveUserFlags()
        RefreshMainList()
        msgLbl.Text := "Added: " cleanName " = " rawValue " (" resolvedType ")"
        eValue.Value := ""
        eName.Value  := ""
        eName.Focus()
    }

    AddFromFile(*) {
        path := FileSelect(1,, "Load FFlags", "JSON or TXT (*.json; *.txt)")
        if (path = "")
            return
        ext  := StrLower(SubStr(path, InStr(path, ".", , -1) + 1))
        text := ""
        try {
            text := FileRead(path, "UTF-8")
        } catch {
            text := FileRead(path)
        }
        if (text = "") {
            msgLbl.Text := "File is empty or unreadable."
            return
        }
        NewFlags := []
        count := (ext = "json") ? ParseJson(text, &NewFlags) : ParseTxt(text, &NewFlags)
        added := 0, updated := 0
        for i, nf in NewFlags {
            exists := false
            for j, f in UserFlags {
                if (f["name"] = nf["name"]) {
                    f["value"] := nf["value"]
                    f["type"]  := nf["type"]
                    exists := true
                    updated++
                    break
                }
            }
            if (!exists) {
                UserFlags.Push(nf)
                added++
            }
        }
        if (count > 0) {
            SaveUserFlags()
            RefreshMainList()
            msgLbl.Text := "File: " added " added, " updated " updated."
        } else {
            msgLbl.Text := "No flags found in file."
        }
    }

    aGui.Show("w436 h218")
    eName.Focus()
}

DoOpenPresetsDialog(*) {
    global PresetsDir, UserFlags
    
    pGui := Gui("-Caption +Border", "MCLoven Presets")
    pGui.BackColor := "0x0F0F0F"
    pGui.SetFont("s9 norm c" "0xE0E0E0", "Segoe UI")
    
    pGui.Add("Text", "x16 y12 w300 h20", "[ SAVED PRESETS ]")
    
    presetList := pGui.Add("ListView", "x16 y40 w468 h260 Background0x0F0F0F c0xE0E0E0 +Grid -Multi", ["Preset Name"])
    presetList.ModifyCol(1, 450)
    DllCall("uxtheme\SetWindowTheme", "Ptr", presetList.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    RefreshPresets() {
        presetList.Delete()
        loop files PresetsDir "\*.json" {
            name := SubStr(A_LoopFileName, 1, StrLen(A_LoopFileName) - 5)
            presetList.Add(, name)
        }
    }
    RefreshPresets()
    
    btnSave   := pGui.Add("Button", "x16  y310 w230 h30", "Save Current Flags")
    btnLoad   := pGui.Add("Button", "x254 y310 w230 h30", "Load Selected")
    btnImport := pGui.Add("Button", "x16  y350 w230 h30", "Import")
    btnOpen   := pGui.Add("Button", "x254 y350 w230 h30", "Open Folder")
    btnDel    := pGui.Add("Button", "x16  y390 w468 h30", "Delete Selected")
    
    btnClose := pGui.Add("Text", "x470 y10 w20 h20 Center", "✕")
    btnClose.OnEvent("Click", (*) => pGui.Destroy())
    
    btnSave.OnEvent("Click", BtnSaveClick)
    btnLoad.OnEvent("Click", BtnLoadClick)
    btnImport.OnEvent("Click", BtnImportClick)
    btnOpen.OnEvent("Click", BtnOpenClick)
    btnDel.OnEvent("Click", BtnDelClick)

    BtnSaveClick(*) {
        ib := InputBox("Enter a name for the new preset:", "Save Preset")
        if (ib.Result = "OK" && Trim(ib.Value) != "") {
            fileName := PresetsDir "\" Trim(ib.Value) ".json"
            s := "["
            for i, f in UserFlags {
                s .= '{"name":"' f["name"] '","value":"' f["value"] '","type":"' f["type"] '"},'
            }
            s := RTrim(s, ",") "]"
            try FileOpen(fileName, "w", "UTF-8").Write(s)
            RefreshPresets()
        }
    }

    BtnLoadClick(*) {
        row := presetList.GetNext(0)
        if (!row)
            return
        pName := presetList.GetText(row, 1)
        filePath := PresetsDir "\" pName ".json"
        if (FileExist(filePath)) {
            try {
                c := FileRead(filePath, "UTF-8"), pos := 1
                UserFlags := []
                while (pos := RegExMatch(c, '\{"name":"([^"]+)","value":"([^"]*)","type":"([^"]+)"\}', &m, pos)) {
                    UserFlags.Push(Map("name", m[1], "value", m[2], "type", m[3]))
                    pos += m.Len
                }
                SaveUserFlags()
                RefreshMainList()
                pGui.Destroy()
            }
        }
    }

    BtnImportClick(*) {
        pGui.Destroy()
        DoLoadJSON()
    }

    BtnOpenClick(*) {
        Run(PresetsDir)
    }

    BtnDelClick(*) {
        row := presetList.GetNext(0)
        if (!row)
            return
        pName := presetList.GetText(row, 1)
        filePath := PresetsDir "\" pName ".json"
        if (FileExist(filePath) && MsgBox("Delete preset '" pName "'?", "Confirm", 0x34) == "Yes") {
            FileDelete(filePath)
            RefreshPresets()
        }
    }
    
    pGui.Show("w500 h435")
}

DoUninject() {
    global RobloxPID, UserFlags
    if (!RobloxPID)
        return
    if (!MemoryEngine.hProcess) {
        if (!MemoryEngine.Attach(RobloxPID))
            return
    }
    for i, f in UserFlags {
        MemoryEngine.UninjectFlag(f["name"])
    }
}

DoApplyFlags(*) {
    global RobloxPID, UserFlags, AllOffsets
    if (!RobloxPID) {
        pid := ProcessExist("RobloxPlayerBeta.exe")
        if (pid)
            AttachRoblox(pid)
        else {
            MsgBox("Roblox is not running.", "MCLoven", 0x10)
            return
        }
    }
    if (!AllOffsets.Count)
        FetchOffsets()
    if (!AllOffsets.Count) {
        MsgBox("Could not download the offsets from imtheo.lol (and no cached copy exists)." "`n" "Check your connection and try again.", "MCLoven", 0x10)
        return
    }
    InjectNow(RobloxPID, UserFlags, UserFlags.Length)
}

AutoApplyFlags() {
    global RobloxPID, UserFlags, AllOffsets
    static tries := 0
    if (!RobloxPID || UserFlags.Length = 0) {
        tries := 0
        return
    }
    if (!AllOffsets.Count) {
        if (++tries <= 10)
            SetTimer(AutoApplyFlags, -2000)
        else
            tries := 0
        return
    }
    tries := 0
    InjectNow(RobloxPID, UserFlags, UserFlags.Length, true)
}

DoKillRoblox(*) {
    ProcessClose("RobloxPlayerBeta.exe")
}

AttachRoblox(pid) {
    global RobloxPID
    MemoryEngine.Attach(pid)
    RobloxPID := pid
}

InjectNow(pid, flags, total, silent := false) {
    global AllOffsets, PREFIXES, LogFile, Settings, UserFlags

    if (!MemoryEngine.hProcess || !MemoryEngine.moduleBase) {
        if (!MemoryEngine.Attach(pid)) {
            if (!silent)
                MsgBox("Failed to attach to Roblox process.", "MCLoven", 0x10)
            return
        }
    }

    succ := 0, fail := 0
    logLines := []
    SuccessfullyInjected := []

    for i, f in flags {
        name  := f["name"]
        value := f["value"]
        type  := f["type"]
        ok    := false

        try {
            ok := MemoryEngine.SetFlagWithPrefixes(name, value, type)
        } catch {
            ok := false
        }

        t := FormatTime(, "HH:mm:ss")
        if (ok) {
            succ++
            logLines.Push("[" t "] [+] " name " = " value)
            SuccessfullyInjected.Push(f)
        } else {
            fail++
            logLines.Push("[" t "] [ERROR] x " name ": not found")
        }
        
        if (Mod(i, 15) = 0)
            Sleep(1)
    }

    logText := ""
    for i, line in logLines
        logText .= line "`n"
    try FileOpen(LogFile, "w", "UTF-8").Write(logText)

    if (Settings["ClearNotInjectedFlags"] && !silent) {
        UserFlags := SuccessfullyInjected
    } else {
        for i, nf in flags {
            exists := false
            for j, f in UserFlags {
                if (f["name"] == nf["name"]) {
                    f["value"] := nf["value"]
                    f["type"]  := nf["type"]
                    exists := true
                    break
                }
            }
            if (!exists)
                UserFlags.Push(nf)
        }
    }
    SaveUserFlags()
    RefreshMainList()

    if (!silent) {
        MsgBox("Total flags applied: " succ " flags, failed: " fail, "Injection Results", 0x40)

        if (Settings["MinimizeOnSystemTray"]) {
            M.Hide()
        }
    
        hwndRoblox := WinExist("ahk_exe RobloxPlayerBeta.exe")
        if (hwndRoblox) {
            WinActivate(hwndRoblox)
        }
    }

    if (Settings["CloseAfterInject"] && !silent)
        ExitApp()
}

MonitorRoblox() {
    global RobloxPID, Settings
    pid := ProcessExist("RobloxPlayerBeta.exe")
    if (pid && pid != RobloxPID) {
        RobloxPID := pid
        MemoryEngine.Attach(pid)
        if (Settings["AutoApply"])
            SetTimer(AutoApplyFlags, -4000)
    } else if (!pid && RobloxPID) {
        RobloxPID := 0
        if (MemoryEngine.hProcess) {
            DllCall("CloseHandle", "Ptr", MemoryEngine.hProcess)
            MemoryEngine.hProcess := 0
        }
    }
}

HttpGet(url) {
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.SetTimeouts(5000, 5000, 10000, 20000)
        whr.Open("GET", url, true)
        whr.SetRequestHeader("User-Agent", "MCLoven/1.0")
        whr.Send()
        whr.WaitForResponse()
        if (whr.Status = 200)
            return whr.ResponseText
    }
    return ""
}

FetchOffsets() {
    global AllOffsets, PrefixMap, OFFSETS_URL, OFFSETS_URL_ALT, PREFIX_URL, OffsetsCache, PrefixCache

    text := HttpGet(OFFSETS_URL)
    if (!InStr(text, "uintptr_t"))
        text := HttpGet(OFFSETS_URL_ALT)

    fromCache := false
    if (!InStr(text, "uintptr_t")) {
        if (!FileExist(OffsetsCache))
            return false
        text := FileRead(OffsetsCache, "UTF-8")
        fromCache := true
    }

    count := ParseOffsetsHpp(text)
    if (count > 0 && !fromCache)
        try FileOpen(OffsetsCache, "w", "UTF-8").Write(text)

    ptext := HttpGet(PREFIX_URL)
    if (!InStr(ptext, "{")) {
        if (FileExist(PrefixCache))
            ptext := FileRead(PrefixCache, "UTF-8")
        else
            ptext := ""
    } else {
        try FileOpen(PrefixCache, "w", "UTF-8").Write(ptext)
    }
    if (ptext != "")
        ParsePrefixes(ptext)

    UpdateCounter()
    return (count > 0)
}

ParseOffsetsHpp(text) {
    global AllOffsets
    body := RegExMatch(text, "s)namespace\s+FFlags\s*\{([^}]+)\}", &ns) ? ns[1] : text
    newMap := Map()
    pos := 1
    while (pos := RegExMatch(body, "uintptr_t\s+(\w+)\s*=\s*(0x[0-9A-Fa-f]+)\s*;", &m, pos)) {
        newMap[m[1]] := Integer(m[2])
        pos += m.Len
    }
    if (newMap.Count > 0)
        AllOffsets := newMap
    return newMap.Count
}

ParsePrefixes(text) {
    global PrefixMap
    pos := 1
    while (pos := RegExMatch(text, '"(?P<Full>[^"]+)"\s*:', &m, pos)) {
        full := m["Full"]
        PrefixMap[StripPrefix(full)] := full
        pos += m.Len
    }
}

GetPrefixedName(name) {
    global PrefixMap
    return PrefixMap.Has(name) ? PrefixMap[name] : name
}

ManageReApplyTimer() {
    global Settings
    SetTimer(ExecuteReApply, Settings["ReApply"] ? 2000 : 0)
}

ExecuteReApply() {
    global RobloxPID, UserFlags, AllOffsets
    if (!RobloxPID || UserFlags.Length = 0 || !AllOffsets.Count || !MemoryEngine.hProcess || !MemoryEngine.moduleBase)
        return
    for f in UserFlags {
        addr := MemoryEngine.ResolveAddr(f["name"])
        if (!addr)
            continue
        ftype := f["type"]
        if (ftype != "bool" && ftype != "int")
            continue
        cur := MemoryEngine.ReadInt32(addr)
        if (cur = "")
            continue
        if (ftype = "bool") {
            v := StrLower(Trim(String(f["value"])))
            want := (v = "true" || v = "1") ? 1 : 0
            if ((cur & 0xFF) = want)
                continue
        } else {
            if (!IsInteger(Trim(f["value"])) || cur = Integer(Trim(f["value"])))
                continue
        }
        WriteRawMemory(MemoryEngine.hProcess, addr, f["value"], ftype)
    }
}

ParseJson(text, &out) {
    count := 0, pos := 1
    while (pos := RegExMatch(text,
        '"(?P<Key>[^"]+)":\s*(?:"(?P<Val>[^"]*)"|(?P<ValNum>[^,\}\s]+))',
        &m, pos))
    {
        key := m["Key"], val := (m["Val"] != "") ? m["Val"] : m["ValNum"]
        out.Push(Map("name", StripPrefix(key), "value", val, "type", InferType(val)))
        count++, pos += m.Len
    }
    return count
}

ParseTxt(text, &out) {
    count := 0
    loop parse, text, "`n", "`r" {
        line := Trim(A_LoopField)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        key := "", val := ""
        if      RegExMatch(line, '"(?P<K>[^"]+)":\s*"?(?P<V>[^",}]+)"?', &m)
            key := m["K"], val := Trim(m["V"])
        else if RegExMatch(line, "^(?P<K>[^=]+)=(?P<V>.+)$", &m)
            key := Trim(m["K"]), val := Trim(m["V"])
        else if RegExMatch(line, "^(?P<K>[^:]+):(?P<V>.+)$", &m)
            key := Trim(m["K"]), val := Trim(m["V"])
        if (key = "" || val = "")
            continue
        out.Push(Map("name", StripPrefix(key), "value", val, "type", InferType(val)))
        count++
    }
    return count
}

StripPrefix(name) {
    global PREFIXES
    for idx, pfx in PREFIXES {
        if (SubStr(name, 1, StrLen(pfx)) = pfx)
            return SubStr(name, StrLen(pfx) + 1)
    }
    return name
}

InferType(v) {
    v := StrLower(Trim(String(v)))
    if (v = "true" || v = "false")
        return "bool"
    return IsNumber(v) ? (InStr(v, ".") ? "float" : "int") : "string"
}

SaveUserFlags() {
    global UserFlagsFile, UserFlags
    s := "["
    for i, f in UserFlags {
        s .= '{"name":"' f["name"] '","value":"' f["value"] '","type":"' f["type"] '"},'
    }
    s := RTrim(s, ",") "]"
    try FileOpen(UserFlagsFile, "w", "UTF-8").Write(s)
}

LoadUserFlags() {
    global UserFlagsFile, UserFlags
    if (!FileExist(UserFlagsFile))
        return
    try {
        c := FileRead(UserFlagsFile), pos := 1
        while (pos := RegExMatch(c, '\{"name":"([^"]+)","value":"([^"]*)","type":"([^"]+)"\}', &m, pos)) {
            UserFlags.Push(Map("name", m[1], "value", m[2], "type", m[3]))
            pos += m.Len
        }
    }
}

SaveSettings() {
    global SettingsFile, Settings
    s := "{"
    for k, v in Settings
        s .= '"' k '":' v ','
    s := RTrim(s, ",") "}"
    try FileOpen(SettingsFile, "w", "UTF-8").Write(s)
}

LoadSettings() {
    global SettingsFile, Settings
    if (!FileExist(SettingsFile))
        return
    try {
        c := FileRead(SettingsFile)
        for k in Settings {
            if RegExMatch(c, '"' k '":\s*(\d)', &m)
                Settings[k] := Integer(m[1])
        }
    }
}
