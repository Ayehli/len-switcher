#Requires AutoHotkey v2.0
#SingleInstance Force

; Change this hotkey if Ctrl+Shift+L conflicts with an app you use.
; ^ = Ctrl, + = Shift, ! = Alt, # = Win. Example: ^!q is Ctrl+Alt+Q.
ConvertHotkey := "^+l"

ENGLISH_HKL := "00000409"
HEBREW_HKL := "0000040D"

savedClip := unset

; Windows Hebrew vs US QWERTY (unshifted letter keys).
; Uppercase English maps through the lowercase key. Hebrew has no case.
EN_TO_HE := Map(
    "q", "/", "w", "'", "e", "ק", "r", "ר", "t", "א", "y", "ט", "u", "ו", "i", "ן", "o", "ם", "p", "פ",
    "[", "]", "]", "[",
    "a", "ש", "s", "ד", "d", "ג", "f", "כ", "g", "ע", "h", "י", "j", "ח", "k", "ל", "l", "ך", ";", "ף", "'", ",",
    "z", "ז", "x", "ס", "c", "ב", "v", "ה", "b", "נ", "n", "מ", "m", "צ", ",", "ת", ".", "ץ", "/", ".",
    "``", ";"
)

HE_TO_EN := Map()
for enChar, heChar in EN_TO_HE {
    if !HE_TO_EN.Has(heChar)
        HE_TO_EN[heChar] := enChar
}

Hotkey ConvertHotkey, ConvertCurrentField
return

ConvertCurrentField(*) {
    global savedClip
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

    heCount := CountHebrew(text)
    enCount := CountLatin(text)
    toEnglish := heCount > enCount

    converted := toEnglish ? ConvertWith(text, HE_TO_EN) : ConvertWith(text, EN_TO_HE)
    if converted = text {
        RestoreClipboard()
        return
    }

    A_Clipboard := converted
    Sleep 30
    Send "^v"
    Sleep 80
    SwitchLayout(toEnglish ? ENGLISH_HKL : HEBREW_HKL)
    SetTimer RestoreClipboard, -400
}

CountHebrew(text) {
    count := 0
    loop parse text {
        code := Ord(A_LoopField)
        if code >= 0x0590 && code <= 0x05FF
            count++
    }
    return count
}

CountLatin(text) {
    count := 0
    loop parse text {
        if A_LoopField ~= "^[a-zA-Z]$"
            count++
    }
    return count
}

ConvertWith(text, table) {
    out := ""
    loop parse text {
        ch := A_LoopField
        key := ch
        if ch ~= "^[A-Z]$"
            key := StrLower(ch)
        out .= table.Has(key) ? table[key] : ch
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
