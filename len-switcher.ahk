#Requires AutoHotkey v2.0
#SingleInstance Force

DEFAULT_HOTKEY := "^+l"
DEFAULT_LAYOUT_A := "00000409"
DEFAULT_LAYOUT_B := "0000040D"

APP_DIR := EnvGet("LOCALAPPDATA") "\LenSwitcher"
SETTINGS_PATH := APP_DIR "\settings.ini"

ConvertHotkey := DEFAULT_HOTKEY
LayoutA := DEFAULT_LAYOUT_A
LayoutB := DEFAULT_LAYOUT_B
A_TO_B := Map()
B_TO_A := Map()
savedClip := unset
settingsGui := 0
captureIh := 0
pendingHotkey := ""
layoutList := []
selectedKlidA := ""
selectedKlidB := ""
captureCtrl := false
captureShift := false
captureAlt := false
captureWin := false

DirCreate(APP_DIR)
LoadSettings()
if !ApplyLayoutPair(LayoutA, LayoutB, false) {
    LayoutA := DEFAULT_LAYOUT_A
    LayoutB := DEFAULT_LAYOUT_B
    ApplyLayoutPair(LayoutA, LayoutB, false)
}
BindConvertHotkey(ConvertHotkey)

A_IconTip := "len-switcher"
A_TrayMenu.Delete()
A_TrayMenu.Add("Settings", OpenSettings)
A_TrayMenu.Add()
A_TrayMenu.Add("Reload", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Settings"
return

; --- Settings persistence ---------------------------------------------------

LoadSettings() {
    global ConvertHotkey, LayoutA, LayoutB, SETTINGS_PATH, DEFAULT_HOTKEY, DEFAULT_LAYOUT_A, DEFAULT_LAYOUT_B
    if !FileExist(SETTINGS_PATH) {
        SaveSettings()
        return
    }
    ConvertHotkey := IniRead(SETTINGS_PATH, "Settings", "Hotkey", DEFAULT_HOTKEY)
    LayoutA := StrUpper(IniRead(SETTINGS_PATH, "Settings", "LayoutA", DEFAULT_LAYOUT_A))
    LayoutB := StrUpper(IniRead(SETTINGS_PATH, "Settings", "LayoutB", DEFAULT_LAYOUT_B))
    if ConvertHotkey = ""
        ConvertHotkey := DEFAULT_HOTKEY
    if LayoutA = ""
        LayoutA := DEFAULT_LAYOUT_A
    if LayoutB = ""
        LayoutB := DEFAULT_LAYOUT_B
}

SaveSettings() {
    global ConvertHotkey, LayoutA, LayoutB, SETTINGS_PATH
    IniWrite(ConvertHotkey, SETTINGS_PATH, "Settings", "Hotkey")
    IniWrite(LayoutA, SETTINGS_PATH, "Settings", "LayoutA")
    IniWrite(LayoutB, SETTINGS_PATH, "Settings", "LayoutB")
}

; --- Installed layouts ------------------------------------------------------

GetInstalledLayouts() {
    layouts := []
    seen := Map()

    ; User-installed input languages (does not change the active layout).
    loop {
        try
            entry := RegRead("HKEY_CURRENT_USER\Keyboard Layout\Preload", String(A_Index))
        catch
            break
        if entry = ""
            break
        klid := ResolveLayoutKlid(entry)
        if klid = "" || seen.Has(klid)
            continue
        seen[klid] := true
        layouts.Push(MakeLayoutEntry(klid))
    }

    ; Also include layouts currently loaded in the session.
    count := DllCall("GetKeyboardLayoutList", "Int", 0, "Ptr", 0)
    if count > 0 {
        buf := Buffer(count * A_PtrSize)
        count := DllCall("GetKeyboardLayoutList", "Int", count, "Ptr", buf.Ptr)
        loop count {
            hkl := NumGet(buf, (A_Index - 1) * A_PtrSize, "UPtr")
            klid := Format("{:08X}", hkl & 0xFFFFFFFF)
            ; Prefer language-form KLID when high/low words match (e.g. 04090409 -> 00000409).
            lang := Format("{:04X}", hkl & 0xFFFF)
            device := Format("{:04X}", (hkl >> 16) & 0xFFFF)
            if device = lang || device = "0000"
                klid := "0000" lang
            if seen.Has(klid)
                continue
            seen[klid] := true
            layouts.Push(MakeLayoutEntry(klid, hkl))
        }
    }

    loop layouts.Length {
        i := A_Index
        loop layouts.Length - i {
            j := i + A_Index
            if StrCompare(layouts[j].name, layouts[i].name, "Locale") < 0 {
                tmp := layouts[i]
                layouts[i] := layouts[j]
                layouts[j] := tmp
            }
        }
    }
    return layouts
}

ResolveLayoutKlid(entry) {
    klid := entry
    try
        klid := RegRead("HKEY_CURRENT_USER\Keyboard Layout\Substitutes", entry)
    catch {
        ; Preload entry is already a KLID.
    }
    return StrUpper(klid)
}

MakeLayoutEntry(klid, hkl := 0) {
    if !hkl
        hkl := DllCall("LoadKeyboardLayout", "Str", klid, "UInt", 0, "UPtr")
    return {
        klid: StrUpper(klid),
        hkl: hkl,
        name: LayoutDisplayName(klid)
    }
}

LayoutDisplayName(klid) {
    langHex := SubStr(klid, -4)
    try
        langId := Integer("0x" langHex)
    catch
        langId := 0
    localeName := Buffer(512)
    if langId && DllCall("GetLocaleInfoW", "UInt", langId, "UInt", 0x2, "Ptr", localeName.Ptr, "Int", 256)
        label := StrGet(localeName, "UTF-16")
    else
        label := "Layout"
    return label " [" StrUpper(klid) "]"
}

FindLayoutIndex(layouts, klid) {
    klid := StrUpper(klid)
    loop layouts.Length {
        if layouts[A_Index].klid = klid
            return A_Index
    }
    return 0
}

EnsureLayoutInList(layouts, klid) {
    klid := StrUpper(klid)
    if FindLayoutIndex(layouts, klid)
        return layouts
    hkl := DllCall("LoadKeyboardLayout", "Str", klid, "UInt", 0, "UPtr")
    if !hkl
        return layouts
    layouts.Push(MakeLayoutEntry(klid, hkl))
    return layouts
}

; --- Dynamic remap maps -----------------------------------------------------

ApplyLayoutPair(klidA, klidB, showError := true) {
    global A_TO_B, B_TO_A, LayoutA, LayoutB
    if klidA = klidB {
        if showError
            MsgBox("Choose two different layouts.", "len-switcher", "Icon!")
        return false
    }
    hklA := DllCall("LoadKeyboardLayout", "Str", klidA, "UInt", 0, "UPtr")
    hklB := DllCall("LoadKeyboardLayout", "Str", klidB, "UInt", 0, "UPtr")
    if !hklA || !hklB {
        if showError
            MsgBox("Could not load one of the selected layouts.", "len-switcher", "Icon!")
        return false
    }
    maps := BuildRemapMaps(hklA, hklB)
    if maps.aToB.Count = 0 {
        if showError
            MsgBox("Could not build a remap between those layouts.`nTry a different pair (IME/CJK layouts are not supported).", "len-switcher", "Icon!")
        return false
    }
    A_TO_B := maps.aToB
    B_TO_A := maps.bToA
    LayoutA := StrUpper(klidA)
    LayoutB := StrUpper(klidB)
    return true
}

BuildRemapMaps(hklA, hklB) {
    aToB := Map()
    bToA := Map()
    vks := RemapVirtualKeys()
    for vk in vks {
        loop 2 {
            shifted := A_Index = 2
            charA := CharFromVk(vk, shifted, hklA)
            charB := CharFromVk(vk, shifted, hklB)
            if charA = "" || charB = "" || charA = charB
                continue
            if !aToB.Has(charA)
                aToB[charA] := charB
            if !bToA.Has(charB)
                bToA[charB] := charA
        }
    }
    return { aToB: aToB, bToA: bToA }
}

RemapVirtualKeys() {
    vks := []
    loop 10 ; 0-9
        vks.Push(0x30 + A_Index - 1)
    loop 26 ; A-Z
        vks.Push(0x41 + A_Index - 1)
    ; Common OEM / punctuation VKs
    for vk in [0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xDB, 0xDC, 0xDD, 0xDE, 0xE2]
        vks.Push(vk)
    return vks
}

CharFromVk(vk, shifted, hkl) {
    state := Buffer(256, 0)
    if shifted {
        NumPut("UChar", 0x80, state, 0x10) ; VK_SHIFT
        NumPut("UChar", 0x80, state, 0xA0) ; VK_LSHIFT
    }
    sc := DllCall("MapVirtualKeyExW", "UInt", vk, "UInt", 0, "UPtr", hkl, "UInt")
    buf := Buffer(16, 0)
    ; First call may return a dead key (-1); flush and retry once.
    n := DllCall("ToUnicodeEx", "UInt", vk, "UInt", sc, "Ptr", state.Ptr, "Ptr", buf.Ptr, "Int", 8, "UInt", 0, "UPtr", hkl, "Int")
    if n < 0 {
        flushBuf := Buffer(16, 0)
        blankState := Buffer(256, 0)
        DllCall("ToUnicodeEx", "UInt", 0x20, "UInt", 0x39, "Ptr", blankState.Ptr, "Ptr", flushBuf.Ptr, "Int", 8, "UInt", 0, "UPtr", hkl)
        return ""
    }
    if n = 0
        return ""
    return StrGet(buf, n, "UTF-16")
}

; --- Hotkey binding ---------------------------------------------------------

BindConvertHotkey(newHotkey) {
    global ConvertHotkey
    try {
        if ConvertHotkey != "" {
            try Hotkey(ConvertHotkey, "Off")
        }
    }
    try {
        Hotkey(newHotkey, ConvertCurrentField, "On")
        ConvertHotkey := newHotkey
        return true
    } catch {
        ; Restore previous binding if the new one failed
        try Hotkey(ConvertHotkey, ConvertCurrentField, "On")
        return false
    }
}

HotkeyToDisplay(hk) {
    out := ""
    i := 1
    while i <= StrLen(hk) {
        ch := SubStr(hk, i, 1)
        if ch = "^" {
            out .= "Ctrl+"
        } else if ch = "+" {
            out .= "Shift+"
        } else if ch = "!" {
            out .= "Alt+"
        } else if ch = "#" {
            out .= "Win+"
        } else {
            rest := SubStr(hk, i)
            if StrLen(rest) = 1
                return out StrUpper(rest)
            return out rest
        }
        i++
    }
    return out = "" ? hk : RTrim(out, "+")
}

; --- Convert ----------------------------------------------------------------

ConvertCurrentField(*) {
    global savedClip, A_TO_B, B_TO_A, LayoutA, LayoutB
    if A_TO_B.Count = 0 || B_TO_A.Count = 0
        return

    savedClip := ClipboardAll()
    A_Clipboard := ""

    Send "^a"
    Sleep 40
    Send "^c"
    if !ClipWait(1) {
        RestoreClipboard()
        return
    }

    text := A_Clipboard
    if text = "" {
        RestoreClipboard()
        return
    }

    scoreA := CountMapped(text, A_TO_B)
    scoreB := CountMapped(text, B_TO_A)
    if scoreA = 0 && scoreB = 0 {
        RestoreClipboard()
        return
    }

    toB := scoreA >= scoreB
    converted := toB ? ConvertWith(text, A_TO_B) : ConvertWith(text, B_TO_A)
    if converted = text {
        RestoreClipboard()
        return
    }

    A_Clipboard := converted
    Sleep 30
    Send "^v"
    Sleep 80
    SwitchLayout(toB ? LayoutB : LayoutA)
    SetTimer RestoreClipboard, -400
}

CountMapped(text, table) {
    count := 0
    loop parse text {
        ch := A_LoopField
        key := ch
        if ch ~= "^[A-Z]$"
            key := StrLower(ch)
        if table.Has(ch) || table.Has(key)
            count++
    }
    return count
}

ConvertWith(text, table) {
    out := ""
    loop parse text {
        ch := A_LoopField
        if table.Has(ch) {
            out .= table[ch]
            continue
        }
        key := ch
        if ch ~= "^[A-Z]$"
            key := StrLower(ch)
        if table.Has(key) {
            mapped := table[key]
            ; Preserve Latin case when the mapped side is a single Latin letter
            if ch ~= "^[A-Z]$" && mapped ~= "^[a-z]$"
                out .= StrUpper(mapped)
            else
                out .= mapped
        } else {
            out .= ch
        }
    }
    return out
}

SwitchLayout(hklName) {
    hkl := DllCall("LoadKeyboardLayout", "Str", hklName, "UInt", 1, "UPtr")
    PostMessage 0x50, 0, hkl, , "A"
}

RestoreClipboard(*) {
    global savedClip
    if IsSet(savedClip) {
        A_Clipboard := savedClip
        savedClip := unset
    }
}

; --- Settings GUI -----------------------------------------------------------

OpenSettings(*) {
    global settingsGui, ConvertHotkey, LayoutA, LayoutB, pendingHotkey, layoutList, selectedKlidA, selectedKlidB
    if settingsGui {
        settingsGui.Show()
        return
    }

    layoutList := GetInstalledLayouts()
    layoutList := EnsureLayoutInList(layoutList, LayoutA)
    layoutList := EnsureLayoutInList(layoutList, LayoutB)
    if layoutList.Length < 2 {
        MsgBox("Need at least two keyboard layouts installed in Windows.", "len-switcher", "Icon!")
        return
    }

    pendingHotkey := ConvertHotkey
    names := []
    for item in layoutList
        names.Push(item.name)

    idxA := FindLayoutIndex(layoutList, LayoutA)
    idxB := FindLayoutIndex(layoutList, LayoutB)
    if !idxA
        idxA := 1
    if !idxB
        idxB := idxA = 1 && layoutList.Length > 1 ? 2 : 1
    selectedKlidA := layoutList[idxA].klid
    selectedKlidB := layoutList[idxB].klid

    g := Gui("+AlwaysOnTop -MinimizeBox", "len-switcher :: settings")
    g.BackColor := "0x0d1117"
    g.MarginX := 16
    g.MarginY := 12
    g.SetFont("s10 c0x3fb950", "Consolas")
    g.AddText("w420",
        "┌──────────────────────────────────────────┐`n"
        "│           LEN-SWITCHER SETTINGS          │`n"
        "└──────────────────────────────────────────┘")

    g.SetFont("s9 c0x8b949e", "Consolas")
    g.AddText("xm w420", "Hotkey that converts the current field")
    g.SetFont("s10 c0x3fb950", "Consolas")
    g.AddText("xm w280 vHotkeyDisplay", HotkeyToDisplay(pendingHotkey))
    g.SetFont("s9 c0x0d1117", "Consolas")
    btnCapture := g.AddButton("x+8 yp-4 w120 h24", "Set Hotkey")
    btnCapture.OnEvent("Click", StartHotkeyCapture)

    g.SetFont("s9 c0x8b949e", "Consolas")
    g.AddText("xm y+14 w420", "Language pair (from installed layouts)")
    g.SetFont("s9 c0x3fb950", "Consolas")
    g.AddText("xm w40", "From")
    ddlA := g.AddDropDownList("x+8 yp-3 w360 vLayoutAChoice", names)
    ddlA.Choose(idxA)
    ddlA.OnEvent("Change", LayoutAChanged)
    g.AddText("xm w40", "To")
    ddlB := g.AddDropDownList("x+8 yp-3 w360 vLayoutBChoice", names)
    ddlB.Choose(idxB)
    ddlB.OnEvent("Change", LayoutBChanged)

    g.SetFont("s9 c0x8b949e", "Consolas")
    g.AddText("xm y+14 w420", "Tip: mistyped text remaps by physical key between these two.")

    g.SetFont("s9 c0x0d1117", "Consolas")
    btnSave := g.AddButton("xm y+12 w100 h28 Default", "Save")
    btnCancel := g.AddButton("x+10 yp w100 h28", "Cancel")
    btnSave.OnEvent("Click", SaveSettingsFromGui)
    btnCancel.OnEvent("Click", CloseSettings)
    g.OnEvent("Close", CloseSettings)
    g.OnEvent("Escape", CloseSettings)

    settingsGui := g
    g.Show()
}

LayoutAChanged(ctrl, *) {
    global layoutList, selectedKlidA
    idx := DropDownIndex(ctrl)
    if idx >= 1 && idx <= layoutList.Length
        selectedKlidA := layoutList[idx].klid
}

LayoutBChanged(ctrl, *) {
    global layoutList, selectedKlidB
    idx := DropDownIndex(ctrl)
    if idx >= 1 && idx <= layoutList.Length
        selectedKlidB := layoutList[idx].klid
}

; CB_GETCURSEL — reliable even if Alt clears the displayed text during hotkey capture.
DropDownIndex(ctrl) {
    sel := SendMessage(0x147, 0, 0, ctrl) ; CB_GETCURSEL
    if sel < 0
        return 0
    return sel + 1
}

CloseSettings(*) {
    global settingsGui, captureIh
    StopHotkeyCapture()
    if settingsGui {
        settingsGui.Destroy()
        settingsGui := 0
    }
}

StartHotkeyCapture(*) {
    global settingsGui, captureIh, captureCtrl, captureShift, captureAlt, captureWin
    if !settingsGui
        return
    StopHotkeyCapture()
    captureCtrl := false
    captureShift := false
    captureAlt := false
    captureWin := false
    ; Move focus off dropdowns so Alt during capture cannot clear their selection.
    try settingsGui["HotkeyDisplay"].Focus()
    settingsGui["HotkeyDisplay"].Value := "Press combo... (Esc cancel)"
    captureIh := InputHook("L0 T60", "{Escape}")
    ; Suppress keys so Alt does not trigger Win32 menu/mnemonic side effects.
    ; Track modifiers in OnKeyDown/OnKeyUp — suppressed Alt is invisible to logical GetKeyState.
    captureIh.KeyOpt("{All}", "NS")
    captureIh.OnKeyDown := HotkeyCapture_OnKeyDown
    captureIh.OnKeyUp := HotkeyCapture_OnKeyUp
    captureIh.OnEnd := HotkeyCapture_OnEnd
    captureIh.Start()
}

StopHotkeyCapture() {
    global captureIh
    if captureIh {
        try captureIh.Stop()
        captureIh := 0
    }
}

IsModifierKeyName(name) {
    return name ~= "i)^(Control|Ctrl|Alt|Shift|LWin|RWin|LControl|RControl|LShift|RShift|LAlt|RAlt)$"
}

UpdateCaptureModifier(name, isDown) {
    global captureCtrl, captureShift, captureAlt, captureWin
    if name ~= "i)^(Control|Ctrl|LControl|RControl)$"
        captureCtrl := isDown
    else if name ~= "i)^(Shift|LShift|RShift)$"
        captureShift := isDown
    else if name ~= "i)^(Alt|LAlt|RAlt)$"
        captureAlt := isDown
    else if name ~= "i)^(LWin|RWin)$"
        captureWin := isDown
}

HotkeyCapture_OnKeyUp(ih, vk, sc) {
    name := GetKeyName(Format("vk{:x}", vk))
    if name = ""
        name := GetKeyName(Format("sc{:x}", sc))
    if IsModifierKeyName(name)
        UpdateCaptureModifier(name, false)
}

HotkeyCapture_OnKeyDown(ih, vk, sc) {
    global pendingHotkey, settingsGui, captureCtrl, captureShift, captureAlt, captureWin
    name := GetKeyName(Format("vk{:x}", vk))
    if name = ""
        name := GetKeyName(Format("sc{:x}", sc))
    if IsModifierKeyName(name) {
        UpdateCaptureModifier(name, true)
        return
    }

    ; Prefer hook-tracked modifiers; also check physical state as backup.
    ctrl := captureCtrl || GetKeyState("Ctrl", "P")
    shift := captureShift || GetKeyState("Shift", "P")
    alt := captureAlt || GetKeyState("Alt", "P") || GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P")
    win := captureWin || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")

    mods := ""
    if ctrl
        mods .= "^"
    if shift
        mods .= "+"
    if alt
        mods .= "!"
    if win
        mods .= "#"

    key := NormalizeHotkeyKey(name)
    if key = "" {
        ih.Stop()
        return
    }

    pendingHotkey := mods . key
    if settingsGui
        settingsGui["HotkeyDisplay"].Value := HotkeyToDisplay(pendingHotkey)
    ih.Stop()
}

HotkeyCapture_OnEnd(ih) {
    global captureIh, settingsGui, pendingHotkey, ConvertHotkey
    captureIh := 0
    if ih.EndReason = "EndKey" && ih.EndKey = "Escape" {
        pendingHotkey := ConvertHotkey
        if settingsGui
            settingsGui["HotkeyDisplay"].Value := HotkeyToDisplay(pendingHotkey)
    } else if ih.EndReason = "Timeout" {
        pendingHotkey := ConvertHotkey
        if settingsGui
            settingsGui["HotkeyDisplay"].Value := HotkeyToDisplay(pendingHotkey)
    }
}

NormalizeHotkeyKey(name) {
    if name = ""
        return ""
    if StrLen(name) = 1
        return StrLower(name)
    ; Space, Tab, F-keys, etc.
    switch StrLower(name) {
        case "space":
            return "Space"
        case "tab":
            return "Tab"
        case "enter", "return":
            return "Enter"
        case "escape", "esc":
            return ""
        case "backspace":
            return "Backspace"
        default:
            return name
    }
}

SaveSettingsFromGui(*) {
    global settingsGui, layoutList, pendingHotkey, ConvertHotkey, LayoutA, LayoutB, A_TO_B, B_TO_A, selectedKlidA, selectedKlidB
    if !settingsGui
        return

    ; Prefer tracked KLIDs (survives Alt clearing dropdown text during capture).
    SyncSelectedLayoutsFromGui()
    klidA := selectedKlidA
    klidB := selectedKlidB
    if klidA = "" || klidB = "" {
        MsgBox("Invalid layout selection.", "len-switcher", "Icon!")
        return
    }
    if pendingHotkey = ""
        pendingHotkey := ConvertHotkey

    ; Snapshot so a failed hotkey bind does not leave half-applied settings.
    prevHotkey := ConvertHotkey
    prevA := LayoutA
    prevB := LayoutB
    prevAToB := A_TO_B
    prevBToA := B_TO_A

    if !ApplyLayoutPair(klidA, klidB, true) {
        return
    }
    if !BindConvertHotkey(pendingHotkey) {
        ConvertHotkey := prevHotkey
        LayoutA := prevA
        LayoutB := prevB
        A_TO_B := prevAToB
        B_TO_A := prevBToA
        try Hotkey(ConvertHotkey, ConvertCurrentField, "On")
        MsgBox("Could not register hotkey: " HotkeyToDisplay(pendingHotkey) "`nPick a different combo.", "len-switcher", "Icon!")
        return
    }

    SaveSettings()
    CloseSettings()
}

SyncSelectedLayoutsFromGui() {
    global settingsGui, layoutList, selectedKlidA, selectedKlidB
    if !settingsGui
        return
    idxA := DropDownIndex(settingsGui["LayoutAChoice"])
    idxB := DropDownIndex(settingsGui["LayoutBChoice"])
    if idxA >= 1 && idxA <= layoutList.Length
        selectedKlidA := layoutList[idxA].klid
    if idxB >= 1 && idxB <= layoutList.Length
        selectedKlidB := layoutList[idxB].klid
    ; If CB_GETCURSEL failed (e.g. Alt wiped selection), keep prior selectedKlid* values.
}
