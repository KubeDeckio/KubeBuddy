function Write-SpeechBubble {
    param (
        [string[]]$msg,           
        [string]$color = "Cyan",  
        [string]$icon = "🤖",     
        [string]$warningEmoji = "⚠️",  
        [string]$lastColor = "Red",
        [int]$delay = 50  # Typing effect speed (milliseconds per word)
    )

    # Ensure the last line includes the warning emoji
    $msg[-1] = "$warningEmoji  " + $msg[-1]

    # Calculate the max line width dynamically
    $maxLength = ($msg | Measure-Object -Property Length -Maximum).Maximum
    $boxWidth = $maxLength + 4  

    # Display the robot first
    Write-Host "  $icon" -ForegroundColor $color
    Write-Host "     🭽" -ForegroundColor $color
    Write-Host "      🭿" -ForegroundColor $color

    Start-Sleep -Milliseconds 500  # Short delay before speaking starts

    # Build rounded speech bubble top (connecting to the speech tail)
    $topBorder = "        ╭" + ("─" * $boxWidth) + "╮"
    Write-Host "$topBorder" -ForegroundColor $color

    # Print each message line inside the bubble with word-by-word effect
    for ($i = 0; $i -lt $msg.Length; $i++) {
        $lineText = $msg[$i]
        $rightBorder = " │"
        $lineColor = $color 

        # Adjust ❌ line alignment
        if ($lineText -match "❌") {
            $rightBorder = "│"
        }

        # Move last line forward and keep its `│` cyan
        if ($i -eq $msg.Length - 1) {
            $lineText = " " + $lineText  
            $rightBorder = "  │"
            $lineColor = $lastColor
        }

        # Pad the line to fit the box width correctly
        $paddedLine = $lineText.PadRight($maxLength + 1)

        # Print left border in cyan
        Write-Host "        │ " -NoNewline -ForegroundColor $color

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
    $bottomBorder = "        ╰" + ("─" * $boxWidth) + "╯"
    Write-Host "$bottomBorder" -ForegroundColor $color
    Write-Host ""
}

# Example Usage:
$msg = @(
    "RBAC (Role-Based Access Control) defines who can do what in your cluster.",
    "",
    "📌 This check identifies:",
    "   - 🔍 Misconfigurations in RoleBindings & ClusterRoleBindings.",
    "   - ❌ Missing references to ServiceAccounts & Namespaces.",
    "   - 🔓 Overly permissive roles that may pose security risks.",
    "",
    "Total RBAC Misconfigurations Detected: 15"
)

Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
