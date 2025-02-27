function Write-SpeechBubble {
    param (
        [string[]]$msg,          # Message array to display
        [string]$color = "Cyan", # Default color of the text
        [string]$icon = "🤖",    # Speaking icon at the bottom
        [string]$warningEmoji = "⚠️", # Warning emoji for the last line
        [string]$lastColor = "Red" # Color for the last line text
    )

    # Ensure the last line includes the warning emoji inside the function
    $msg[-1] = "$warningEmoji " + $msg[-1]

    # Calculate the max line width dynamically
    $maxLength = ($msg | Measure-Object -Property Length -Maximum).Maximum
    $boxWidth = $maxLength + 3  # Add padding for alignment

    # Build speech bubble top border manually
    $topBorder = "  ╭" + ("─" * $boxWidth) + "╮"
    Write-Host "`n$topBorder" -ForegroundColor $color

    # Print each message line inside the bubble with exact spacing
    for ($i = 0; $i -lt $msg.Length; $i++) {
        $lineText = $msg[$i]
        $rightBorder = " │"  # Default right border
        $lineColor = $color  # Default text color

        # Move ❌ line back by one space AND shift `│` back one space
        if ($lineText -match "❌") {
            $rightBorder = "│"  # Shift right border back one space
        }

        # Move last line forward one space and keep its `│` cyan
        if ($i -eq $msg.Length - 1) {
            $lineText = " " + $lineText  # Shift text forward
            $rightBorder = "  │"  # Shift right border right by one space
            $lineColor = $lastColor  # Make text red
        }

        # Pad the line to fit the box width correctly
        $paddedLine = $lineText.PadRight($maxLength + 1)

        # Print the left border in cyan
        Write-Host "  │ " -NoNewline -ForegroundColor $color

        # Print the text (red for last line)
        Write-Host "$paddedLine" -NoNewline -ForegroundColor $lineColor

        # Print the right border in cyan
        Write-Host "$rightBorder" -ForegroundColor $color
    }

    # Build speech bubble bottom border manually
    $bottomBorder = "  ╰" + ("─" * $boxWidth) + "╯"
    Write-Host "$bottomBorder" -ForegroundColor $color

    # Speech tail pointing to the robot
    Write-Host "     \\" -ForegroundColor $color
    Write-Host "      \_ $icon" -ForegroundColor $color
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

Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red"
