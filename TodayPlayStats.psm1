# TodayPlayStats.psm1

# ---------------------------------------------------------
# Menu Integration
# ---------------------------------------------------------

function GetMainMenuItems {
    param($args)
    $item = New-Object Playnite.SDK.Plugins.ScriptMainMenuItem
    $item.Description = "Show Today's Play Stats"
    $item.FunctionName = "Show-TodayStats"
    return $item
}

function Show-TodayStats {
    param($args)
    # Define paths locally so they are never null
    $CSVPath = Join-Path $PSScriptRoot "sessions.csv"
    
    $selected = $PlayniteApi.MainView.SelectedGames
    if (-not $selected -or $selected.Count -eq 0) {
        $PlayniteApi.Dialogs.ShowMessage("No game selected.", "Today Stats")
        return
    }

    $game = $selected[0]
    $gameId = $game.Id.ToString()
    $today = (Get-Date).ToString("yyyy-MM-dd")

    if (-not (Test-Path $CSVPath)) {
        $PlayniteApi.Dialogs.ShowMessage("No sessions recorded yet. Start a game to begin tracking!", "Today Stats")
        return
    }

    $sessions = Import-Csv -Path $CSVPath | Where-Object { 
        $_.game_id -eq $gameId -and $_.date -eq $today 
    }

    if (-not $sessions) {
        $PlayniteApi.Dialogs.ShowMessage("No recorded sessions for $($game.Name) today.", "Today Stats")
        return
    }

    $totalSeconds = 0
    # CSV values are strings by default, force to INT
    foreach ($s in @($sessions)) { $totalSeconds += [int]$s.duration_seconds }

    $h = [math]::Floor($totalSeconds / 3600)
    $m = [math]::Floor(($totalSeconds % 3600) / 60)

    $PlayniteApi.Dialogs.ShowMessage("$($game.Name)`nDate: $today`n`nTotal Today: $h h $m m", "Today Stats")
}

# ---------------------------------------------------------
# Event Hooks
# ---------------------------------------------------------

function OnGameStarted {
    param($args)
    $game = $args.Game
    if ($null -eq $game) { return }

    $ActivePath = Join-Path $PSScriptRoot "active_sessions.csv"

    $newSession = [PSCustomObject]@{
        game_id    = $game.Id.ToString()
        game_name  = $game.Name
        start_time = (Get-Date).ToString("o")
    }

    $newSession | Export-Csv -Path $ActivePath -Append -NoTypeInformation -Encoding utf8
}

function OnGameStopped {
    param($args)
    $game = $args.Game
    if ($null -eq $game) { return }
    
    $ActivePath = Join-Path $PSScriptRoot "active_sessions.csv"
    $CSVPath    = Join-Path $PSScriptRoot "sessions.csv"

    if (-not (Test-Path $ActivePath)) { return }

    $gameId = $game.Id.ToString()
    $activeItems = Import-Csv -Path $ActivePath
    $remaining = @()

    foreach ($item in @($activeItems)) {
        if ($item.game_id -eq $gameId) {
            $start = [datetime]::Parse($item.start_time)
            $duration = [int]((Get-Date) - $start).TotalSeconds
            
            $finishedSession = [PSCustomObject]@{
                game_id          = $item.game_id
                game_name        = $item.game_name
                date             = (Get-Date).ToString("yyyy-MM-dd")
                duration_seconds = $duration
            }
            $finishedSession | Export-Csv -Path $CSVPath -Append -NoTypeInformation -Encoding utf8
        } else {
            $remaining += $item
        }
    }

    # Update active list
    if ($remaining.Count -gt 0) {
        $remaining | Export-Csv -Path $ActivePath -Force -NoTypeInformation -Encoding utf8
    } else {
        Remove-Item $ActivePath -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------
# Exports
# ---------------------------------------------------------
Export-ModuleMember -Function GetMainMenuItems, Show-TodayStats, OnGameStarted, OnGameStopped