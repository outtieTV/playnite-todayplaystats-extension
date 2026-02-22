# =========================================================
# TodayPlayStats - Combined Robust Version
# =========================================================

# ---------------------------------------------------------
# Menu Integration
# ---------------------------------------------------------
function GetMainMenuItems {
    param($args)
    $items = @()
    
    $item1 = New-Object Playnite.SDK.Plugins.ScriptMainMenuItem
    $item1.Description = "Show Today's Play Stats"
    $item1.FunctionName = "Show-TodayStats"
    $items += $item1

    $item2 = New-Object Playnite.SDK.Plugins.ScriptMainMenuItem
    $item2.Description = "Show Top Played Game Today"
    $item2.FunctionName = "Show-TopPlayedToday"
    $items += $item2

    $item3 = New-Object Playnite.SDK.Plugins.ScriptMainMenuItem
    $item3.Description = "Reset Selected Game Stats"
    $item3.FunctionName = "Reset-TodayStats"
    $items += $item3

    return $items
}

# ---------------------------------------------------------
# Logic Functions
# ---------------------------------------------------------

function Show-TodayStats {
    param($args)
    $CSVPath = Join-Path $PSScriptRoot "sessions.csv"
    
    $selected = $PlayniteApi.MainView.SelectedGames
    if (-not $selected -or $selected.Count -eq 0) {
        $PlayniteApi.Dialogs.ShowMessage("No game selected.", "Today Stats")
        return
    }

    $game = $selected[0]
    $gameId = $game.Id.ToString()
    
    # Check both formats just in case
    $t1 = (Get-Date).ToString("yyyy-MM-dd")
    $t2 = (Get-Date).ToString("M/d/yyyy")

    if (-not (Test-Path $CSVPath)) {
        $PlayniteApi.Dialogs.ShowMessage("$($game.Name)`nTotal Today: 0h 0m", "Today Stats")
        return
    }

    # Import and filter
    $sessions = Import-Csv -Path $CSVPath | Where-Object { 
        $_.game_id -eq $gameId -and ($_.date -eq $t1 -or $_.date -eq $t2)
    }

    $totalSeconds = 0
    if ($sessions) {
        foreach ($s in @($sessions)) { $totalSeconds += [int]$s.duration_seconds }
    }

    $h = [math]::Floor($totalSeconds / 3600)
    $m = [math]::Floor(($totalSeconds % 3600) / 60)

    $PlayniteApi.Dialogs.ShowMessage("$($game.Name)`nTotal Today: $h h $m m", "Today Stats")
}

function Show-TopPlayedToday {
    param($args)
    $CSVPath = Join-Path $PSScriptRoot "sessions.csv"
    if (-not (Test-Path $CSVPath)) {
        $PlayniteApi.Dialogs.ShowMessage("No stats recorded.", "Top Played")
        return
    }

    $t1 = (Get-Date).ToString("yyyy-MM-dd")
    $t2 = (Get-Date).ToString("M/d/yyyy")

    $sessions = Import-Csv -Path $CSVPath | Where-Object { $_.date -eq $t1 -or $_.date -eq $t2 }
    if (-not $sessions) {
        $PlayniteApi.Dialogs.ShowMessage("No sessions today.", "Top Played")
        return
    }

    $top = $sessions | Group-Object game_id | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Group[0].game_name
            Time = ($_.Group | Measure-Object duration_seconds -Sum).Sum
        }
    } | Sort-Object Time -Descending | Select-Object -First 1

    $h = [math]::Floor($top.Time / 3600)
    $m = [math]::Floor(($top.Time % 3600) / 60)

    $PlayniteApi.Dialogs.ShowMessage("Top Today: $($top.Name)`nTime: $h h $m m", "Top Played")
}

function Reset-TodayStats {
    param($args)
    $CSVPath = Join-Path $PSScriptRoot "sessions.csv"
    $selected = $PlayniteApi.MainView.SelectedGames
    if (-not $selected -or $selected.Count -eq 0 -or -not (Test-Path $CSVPath)) { return }

    $targetId = $selected[0].Id.ToString()
    $remaining = Import-Csv -Path $CSVPath | Where-Object { $_.game_id -ne $targetId }

    if ($remaining) {
        $remaining | Export-Csv -Path $CSVPath -NoTypeInformation -Encoding utf8 -Force
    } else {
        Remove-Item $CSVPath -ErrorAction SilentlyContinue
    }
    $PlayniteApi.Dialogs.ShowMessage("Cleared stats for $($selected[0].Name)", "Reset")
}

# ---------------------------------------------------------
# Event Hooks
# ---------------------------------------------------------

function OnGameStarted {
    param($args)
    $ActivePath = Join-Path $PSScriptRoot "active_sessions.csv"
    $CSVPath = Join-Path $PSScriptRoot "sessions.csv"

    # Cleanup Old Days (Maintenance)
    if (Test-Path $CSVPath) {
        $t1 = (Get-Date).ToString("yyyy-MM-dd")
        $t2 = (Get-Date).ToString("M/d/yyyy")
        $current = Import-Csv $CSVPath
        if (-not ($current | Where-Object { $_.date -eq $t1 -or $_.date -eq $t2 })) {
            Remove-Item $CSVPath -Force
        }
    }

    $newSession = [PSCustomObject]@{
        game_id    = $args.Game.Id.ToString()
        game_name  = $args.Game.Name
        start_time = (Get-Date).ToString("o")
    }
    $newSession | Export-Csv -Path $ActivePath -Append -NoTypeInformation -Encoding utf8
}

function OnGameStopped {
    param($args)
    $ActivePath = Join-Path $PSScriptRoot "active_sessions.csv"
    $CSVPath    = Join-Path $PSScriptRoot "sessions.csv"

    if (-not (Test-Path $ActivePath)) { return }

    $gameId = $args.Game.Id.ToString()
    $activeItems = Import-Csv -Path $ActivePath
    $remaining = @()

    foreach ($item in @($activeItems)) {
        if ($item.game_id -eq $gameId) {
            $start = [datetime]::Parse($item.start_time)
            $duration = [int]((Get-Date) - $start).TotalSeconds
            
            $finished = [PSCustomObject]@{
                game_id          = $item.game_id
                game_name        = $item.game_name
                date              = (Get-Date).ToString("yyyy-MM-dd")
                duration_seconds = $duration
            }
            $finished | Export-Csv -Path $CSVPath -Append -NoTypeInformation -Encoding utf8
        } else {
            $remaining += $item
        }
    }

    if ($remaining.Count -gt 0) {
        $remaining | Export-Csv -Path $ActivePath -Force -NoTypeInformation -Encoding utf8
    } else {
        Remove-Item $ActivePath -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------
# Exports
# ---------------------------------------------------------
Export-ModuleMember -Function GetMainMenuItems, Show-TodayStats, Show-TopPlayedToday, Reset-TodayStats, OnGameStarted, OnGameStopped
