-- Never activate Finder or use its insertion location: this preserves the clicked window.
tell application "Finder"
    if (count of Finder windows) is 0 then error "请先打开一个 Finder 文件夹窗口。" number 1001
    set folderPath to ""
    try
        set windowTarget to target of front Finder window
        if class of windowTarget is folder or class of windowTarget is disk then
            set targetAlias to windowTarget as alias
            set folderPath to POSIX path of targetAlias
        end if
    end try
    set selectedPaths to {}
    repeat with selectedItem in (get selection)
        try
            set end of selectedPaths to POSIX path of (selectedItem as alias)
        on error
            -- Preserve a failed item so the resolver rejects an ambiguous selection.
            set end of selectedPaths to ""
        end try
    end repeat
    return {folderPath, selectedPaths}
end tell
