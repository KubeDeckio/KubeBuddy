function Get-TerminalWidth {
    try {
        return $Host.UI.RawUI.WindowSize.Width
    } catch {
        return 80  # Default width if detection fails
    }
}

function Wrap-Text {
    param (
        [string]$text,
        [int]$maxWidth
    )

    $words = $text -split ' '
    $lines = @()
    $currentLine = ""

    foreach ($word in $words) {
        if (($currentLine.Length + $word.Length) -lt $maxWidth) {
            $currentLine += "$word "
        } else {
            $lines += $currentLine.TrimEnd()
            $currentLine = "$word "
        }
    }

    if ($currentLine.Length -gt 0) {
        $lines += $currentLine.TrimEnd()
    }

    return ,$lines  # Forces return type to an array
}

function Write-SpeechBubble {
    param (
        [string[]]$msg,
        [string]$color = "Cyan",
        [string]$icon = "[BOT]",
        [string]$warningText = "[WARNING]",
        [string]$lastColor = "Red",
        [int]$delay = 50
    )

    # Get terminal width and set max bubble width (keep some margin)
    $terminalWidth = Get-TerminalWidth
    $maxTextWidth = $terminalWidth - 10  # Keep a 10-char margin

    # Wrap each line to fit within terminal width
    $wrappedMsg = @()
    foreach ($line in $msg[0..($msg.Length - 2)]) {  # Process all except last line
        $wrappedMsg += Wrap-Text -text $line -maxWidth $maxTextWidth
    }

    # Process the last line separately to ensure `[WARNING]` is only added once
    $lastWrappedLines = @(Wrap-Text -text $msg[-1] -maxWidth $maxTextWidth)  # Ensures array format

    # Add `[WARNING]` only to the first wrapped part of the last line
    if ($lastWrappedLines.Count -gt 0) {
        $lastWrappedLines[0] = "$warningText $lastWrappedLines[0]"
    }

    $wrappedMsg += $lastWrappedLines

    # Calculate max line width dynamically
    $maxLength = ($wrappedMsg | Measure-Object -Property Length -Maximum).Maximum
    $boxWidth = $maxLength + 4  

    # Print the bot icon
    Write-Host "  $icon" -ForegroundColor $color
    Write-Host "     🭽" -ForegroundColor $color
    Write-Host "      🭿" -ForegroundColor $color

    Start-Sleep -Milliseconds 500  # Short delay before speaking starts

    # Top border
    Write-Host ("     ╭" + ("─" * $boxWidth) + "╮") -ForegroundColor $color

    # Print each message line inside the bubble
    foreach ($line in $wrappedMsg) {
        $paddedLine = $line.PadRight($maxLength)
        Write-Host "     │ " -NoNewline -ForegroundColor $color
        Write-Host "$paddedLine   │" -ForegroundColor $color
    }

    # Bottom border
    Write-Host ("     ╰" + ("─" * $boxWidth) + "╯") -ForegroundColor $color
    Write-Host ""
}

# Example Usage:
$msg = @(
    "SYSTEM STATUS REPORT:",
    "",
    "This is an extremely long single line designed to test how the speech bubble handles word wrapping within a constrained width. If everything works correctly, this sentence should automatically wrap within the defined text box without breaking alignment, misplacing words, or shifting the right-side border. The goal is to ensure that the box expands properly and the text remains readable without being cut off or causing formatting issues in different terminal environments, including Windows Terminal.",
    "",
    "If the formatting looks incorrect, word-wrapping might need adjustments!"
)

Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
