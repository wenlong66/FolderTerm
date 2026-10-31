on openfolder(commandText, openMode)
    tell application "Terminal"
        -- No target means a new window. Never type into an existing shell/process.
        do script commandText
        activate
    end tell
end openfolder
