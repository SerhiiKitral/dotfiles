# Path-segment word movement, mirroring the zsh widgets:
# separators are whitespace, / and \ (plus quotes and a few shell
# punctuation characters), so on  C:\Users\User1\file.txt
# Ctrl+Backspace removes file.txt -> User1\ -> Users\ -> C:\ one press at a time.

function Test-DotSegmentSeparator {
    param([char]$Char)
    return [char]::IsWhiteSpace($Char) -or ('/\"''|,;=:'.IndexOf($Char) -ge 0)
}

# Index where a backward kill/move from $Cursor should stop.
function Get-DotSegmentStart {
    param([string]$Line, [int]$Cursor)
    if ($null -eq $Line) { $Line = '' }
    $i = [Math]::Max(0, [Math]::Min($Cursor, $Line.Length))
    while ($i -gt 0 -and (Test-DotSegmentSeparator $Line[$i - 1])) { $i-- }
    while ($i -gt 0 -and -not (Test-DotSegmentSeparator $Line[$i - 1])) { $i-- }
    return $i
}

# Index where a forward kill/move from $Cursor should stop.
function Get-DotSegmentEnd {
    param([string]$Line, [int]$Cursor)
    if ($null -eq $Line) { $Line = '' }
    $i = [Math]::Max(0, [Math]::Min($Cursor, $Line.Length))
    while ($i -lt $Line.Length -and (Test-DotSegmentSeparator $Line[$i])) { $i++ }
    while ($i -lt $Line.Length -and -not (Test-DotSegmentSeparator $Line[$i])) { $i++ }
    return $i
}
