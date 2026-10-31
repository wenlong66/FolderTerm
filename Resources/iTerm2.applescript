on openfolder(commandText, openMode)
    tell application id "com.googlecode.iterm2"
        if openMode is "tab" and (count of windows) > 0 then
            tell current window
                set newTab to (create tab with default profile)
            end tell
            set newSession to current session of newTab
        else
            set newWindow to (create window with default profile)
            set newSession to current session of newWindow
        end if
        tell newSession to write text commandText
        activate
    end tell
end openfolder
