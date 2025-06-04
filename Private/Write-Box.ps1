function Remove-AllEmojis {
    param ([string]$text)

    # Improved regex to match and remove ALL emojis, including:
    # - Standard emojis (Symbols)
    # - Flags (Regional Indicators)
    # - ZWJ Sequences (Family, Handshake)
    # - Variation Selectors (⚠️ vs ⚠)
    # - Skin Tones
    $emojiRegex = "[\p{So}\p{Sk}\p{Cn}\u200D\uFE0F\uD83C-\uDBFF][\uDC00-\uDFFF]?"

    # Remove all emojis from the text
    return ($text -replace $emojiRegex, "")
}

function Get-DisplayWidth($text) {
    if (-not $text) { return 0 }  # Handles $null, empty string, etc.

    $runes = $text.EnumerateRunes()
    $visibleWidth = 0

    foreach ($rune in $runes) {
        $visibleWidth += 1  # Each character is one space wide
    }

    return $visibleWidth
}

function Wrap-Line {
    param (
        [string]$line,
        [int]$maxWidth
    )

    $wrapped = @()
    while ($line.Length -gt $maxWidth) {
        $segment = $line.Substring(0, $maxWidth)
        $wrapped += $segment
        $line = $line.Substring($maxWidth)
    }
    if ($line.Length -gt 0) {
        $wrapped += $line
    }
    return $wrapped
}

function Write-SpeechBubble {
    param (
        [string[]]$msg,           
        [string]$color = "Cyan",  
        [string]$icon = "🤖", # No emojis
        [string]$lastColor = "Red",
        [int]$delay = 50  # Typing effect speed (milliseconds per word)
    )


    $maxConsoleWidth = $Host.UI.RawUI.WindowSize.Width
    $availableBubbleWidth = [math]::Min($maxConsoleWidth - 15, 100)  # Padding from left and borders
    
    $msgInput = $msg
    $msg = @()
    
    foreach ($line in $msgInput) {
        if ($null -eq $line -or $line.Trim() -eq "") {
            # Preserve empty lines
            $msg += ""
            continue
        }
    
        $cleaned = Remove-AllEmojis $line
        $wrapped = Wrap-Line -line $cleaned -maxWidth $availableBubbleWidth
        $msg += $wrapped
    }
    

    # Calculate the max line width dynamically
    $maxLength = ($msg | ForEach-Object { Get-DisplayWidth $_ } | Measure-Object -Maximum).Maximum
    $boxWidth = $maxLength + 4  

    # Display the bot icon
    Write-Host "  $icon" -ForegroundColor $color
    Write-Host "    ◤" -ForegroundColor $color
    Write-Host "     ◢" -ForegroundColor $color

    Start-Sleep -Milliseconds 500  # Short delay before speaking starts

    # Build rounded speech bubble top (connecting to the speech tail)
    $topBorder = "       ╭" + ("─" * $boxWidth) + "╮"
    Write-Host "$topBorder" -ForegroundColor $color

    # Print each message line inside the bubble with word-by-word effect
    for ($i = 0; $i -lt $msg.Length; $i++) {
        $lineText = $msg[$i]
        $rightBorder = " │"
        $lineColor = $color 

        # Apply coloring logic:
        # If this message is an AI block (detected by prior context), color all recommendation lines yellow
        $lineColor = $color  # default

        if ($msg -match "📎 Recommendation:") {
            # If it's an AI recommendation block, make all lines following 📎 yellow
            $recommendationIndex = ($msg | Select-String "Recommendation:").LineNumber
            if ($i -ge $recommendationIndex) {
                $lineColor = $lastColor
            }
        }
        elseif ($i -eq $msg.Length - 1) {
            # Fallback: just color the last line yellow
            $lineColor = $lastColor
        }


        # Pad the line to fit the box width correctly
        $paddedLine = $lineText.PadRight($maxLength + 1)

        # Print left border in cyan
        Write-Host "       │ " -NoNewline -ForegroundColor $color

        # Print the text **word-by-word** with delay
        $words = $paddedLine -split " "  # Split into words

        foreach ($word in $words) {
            if ($word -match "^\s*$") {
                # Skip empty words and spaces
                Write-Host " " -NoNewline
                continue
            }
            
            Write-Host "$word " -NoNewline -ForegroundColor $lineColor
        
            if ($delay -gt 0) { Start-Sleep -Milliseconds $delay }  # Only delay on actual words
        }

        # Print right border in cyan
        Write-Host "$rightBorder" -ForegroundColor $color
    }

    # Build rounded speech bubble bottom
    $bottomBorder = "       ╰" + ("─" * $boxWidth) + "╯"
    Write-Host "$bottomBorder" -ForegroundColor $color
    Write-Host ""
}