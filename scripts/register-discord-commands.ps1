param(
    [Parameter(Mandatory = $true)] [string] $ApplicationId,
    [Parameter(Mandatory = $true)] [string] $BotToken,
    [Parameter(Mandatory = $true)] [string] $GuildId,
    [switch] $RemoveLegacyGlobal
)

$commands = @(
    @{
        name = "start"
        description = "Start a Minecraft server"
        options = @(@{ type = 3; name = "server"; description = "Choose a server"; required = $true; autocomplete = $true })
    },
    @{
        name = "stop"
        description = "Gracefully stop a Minecraft server"
        options = @(@{ type = 3; name = "server"; description = "Choose a server"; required = $true; autocomplete = $true })
    },
    @{
        name = "status"
        description = "Show Minecraft fleet status"
    }
)

$uri = "https://discord.com/api/v10/applications/$ApplicationId/guilds/$GuildId/commands"
$headers = @{
    Authorization = "Bot $BotToken"
    Accept        = "application/json"
}

# Discord's edge may reject PowerShell's default request identity with error 40333.
$userAgent = "minecraft-fleet-command-registration/1.0"
Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -UserAgent $userAgent -ContentType "application/json" -Body ($commands | ConvertTo-Json -Depth 5)
Write-Host "Registered /start, /stop, and /status fleet commands successfully."

if ($RemoveLegacyGlobal) {
    $globalCommandsUri = "https://discord.com/api/v10/applications/$ApplicationId/commands"
    $legacyNames = @("mc", "start", "stop", "status")
    $globalCommands = Invoke-RestMethod -Method Get -Uri $globalCommandsUri -Headers $headers -UserAgent $userAgent

    foreach ($command in $globalCommands) {
        if ($legacyNames -contains $command.name) {
            Invoke-RestMethod -Method Delete -Uri "$globalCommandsUri/$($command.id)" -Headers $headers -UserAgent $userAgent
            Write-Host "Removed legacy global /$($command.name)."
        }
    }
}
