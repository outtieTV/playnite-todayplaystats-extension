# =========================================================
# TodayPlayStats - Fully Self-Contained Robust Version
# =========================================================

# ---------------------------------------------------------
# Menu Integration (Main Menu Only)
# ---------------------------------------------------------

function GetMainMenuItems {
    param($args)
    $items = @()
    
    $item1 = New-Object Playnite.SDK.Plugins.ScriptMainMenuItem
    $item1.Description = "Today Stats - Show Selected Game"
    $item1.FunctionName = "Show-TodayStats"
    $items += $item1

    $item2 = New-Object Playnite.SDK.Plugins.ScriptMainMenuItem
    $item2.Description = "Today Stats - Top Played"
    $item2.FunctionName = "Show-TopPlayedToday"
    $items += $item2

    $item3 = New-Object Playnite.SDK.Plugins.ScriptMainMenuItem
    $item3.Description = "Today Stats - Reset Selected Game"
    $item3.FunctionName = "Reset-TodayStats"
    $items += $item3

    $item4 = New-Object Playnite.SDK.Plugins.ScriptMainMenuItem
    $item4.Description = "Today Stats - Reset All Games"
    $item4.FunctionName = "Reset-AllTodayStats"
    $items += $item4

    return $items
}

# ---------------------------------------------------------
# Show Selected Game Stats
# ---------------------------------------------------------

function Show-TodayStats {
    param($args)

    $CSVPath = Join-Path $PSScriptRoot "sessions.csv"
    $today = (Get-Date).ToString("yyyy-MM-dd")

    $selected = $PlayniteApi.MainView.SelectedGames
    if (-not $selected -or $selected.Count -eq 0) {
        $PlayniteApi.Dialogs.ShowMessage("No game selected.", "Today Stats")
        return
    }

    $game = $selected[0]
    $gameId = $game.Id.ToString()

    if (-not (Test-Path $CSVPath)) {
        $PlayniteApi.Dialogs.ShowMessage("$($game.Name)`nTotal Today: 0h 0m", "Today Stats")
        return
    }

    $allSessions = Import-Csv $CSVPath
    $sessions = $allSessions | Where-Object { 
        $_.game_id -eq $gameId -and $_.date -eq $today
    }

    if (-not $sessions) {
        $PlayniteApi.Dialogs.ShowMessage("$($game.Name)`nTotal Today: 0h 0m", "Today Stats")
        return
    }

    $totalSeconds = [int](($sessions | Measure-Object duration_seconds -Sum).Sum)

    $h = [math]::Floor($totalSeconds / 3600)
    $m = [math]::Floor(($totalSeconds % 3600) / 60)

    $sessionCount = @($sessions).Count

    $message = "$($game.Name)`n"
    $message += "Total Today: $h h $m m`n"
    $message += "Sessions: $sessionCount"

    if ($sessionCount -ge 2) {
        $message += "`n`nSession Breakdown:"
        $index = 1
        foreach ($s in $sessions) {
            $sec = [int]$s.duration_seconds
            $sh = [math]::Floor($sec / 3600)
            $sm = [math]::Floor(($sec % 3600) / 60)
            $message += "`n$index) $sh h $sm m"
            $index++
        }
    }

    $PlayniteApi.Dialogs.ShowMessage($message, "Today Stats")
}

# ---------------------------------------------------------
# Show Top Played Game Today
# ---------------------------------------------------------

function Show-TopPlayedToday {
    param($args)

    $CSVPath = Join-Path $PSScriptRoot "sessions.csv"
    $today = (Get-Date).ToString("yyyy-MM-dd")

    if (-not (Test-Path $CSVPath)) {
        $PlayniteApi.Dialogs.ShowMessage("No stats recorded.", "Top Played")
        return
    }

    $sessions = Import-Csv $CSVPath | Where-Object { $_.date -eq $today }

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

    $seconds = [int]$top.Time
    $h = [math]::Floor($seconds / 3600)
    $m = [math]::Floor(($seconds % 3600) / 60)

    $PlayniteApi.Dialogs.ShowMessage("Top Today: $($top.Name)`nTime: $h h $m m", "Top Played")
}

# ---------------------------------------------------------
# Reset Selected Game Stats (Today Only)
# ---------------------------------------------------------

function Reset-TodayStats {
    param($args)

    $CSVPath = Join-Path $PSScriptRoot "sessions.csv"
    $today = (Get-Date).ToString("yyyy-MM-dd")

    $selected = $PlayniteApi.MainView.SelectedGames
    if (-not $selected -or $selected.Count -eq 0 -or -not (Test-Path $CSVPath)) {
        return
    }

    $targetId = $selected[0].Id.ToString()

    $remaining = Import-Csv $CSVPath | Where-Object {
        -not ($_.game_id -eq $targetId -and $_.date -eq $today)
    }

    if ($remaining) {
        $remaining | Export-Csv -Path $CSVPath -NoTypeInformation -Encoding utf8 -Force
    }
    else {
        Remove-Item $CSVPath -ErrorAction SilentlyContinue
    }

    $PlayniteApi.Dialogs.ShowMessage("Cleared today's stats for $($selected[0].Name)", "Reset")
}

# ---------------------------------------------------------
# Reset All Games Today
# ---------------------------------------------------------

function Reset-AllTodayStats {
    param($args)

    $CSVPath = Join-Path $PSScriptRoot "sessions.csv"
    $today = (Get-Date).ToString("yyyy-MM-dd")

    if (-not (Test-Path $CSVPath)) {
        $PlayniteApi.Dialogs.ShowMessage("No stats recorded.", "Reset")
        return
    }

    $remaining = Import-Csv $CSVPath | Where-Object { $_.date -ne $today }

    if ($remaining) {
        $remaining | Export-Csv -Path $CSVPath -NoTypeInformation -Encoding utf8 -Force
    }
    else {
        Remove-Item $CSVPath -ErrorAction SilentlyContinue
    }

    $PlayniteApi.Dialogs.ShowMessage("All today's stats cleared.", "Reset")
}

# ---------------------------------------------------------
# Event Hooks
# ---------------------------------------------------------

function OnGameStarted {
    param($args)

    $ActivePath = Join-Path $PSScriptRoot "active_sessions.csv"
    $CSVPath = Join-Path $PSScriptRoot "sessions.csv"
    $today = (Get-Date).ToString("yyyy-MM-dd")

    # Daily cleanup
    if (Test-Path $CSVPath) {
        $existing = Import-Csv $CSVPath
        if (-not ($existing | Where-Object { $_.date -eq $today })) {
            Remove-Item $CSVPath -Force
        }
    }

    $gameId = $args.Game.Id.ToString()

    # Prevent duplicate active session
    if (Test-Path $ActivePath) {
        $active = Import-Csv $ActivePath
        if ($active | Where-Object { $_.game_id -eq $gameId }) {
            return
        }
    }

    $newSession = [PSCustomObject]@{
        game_id    = $gameId
        game_name  = $args.Game.Name
        start_time = (Get-Date).ToString("o")
    }

    $newSession | Export-Csv -Path $ActivePath -Append -NoTypeInformation -Encoding utf8
}

function OnGameStopped {
    param($args)

    $ActivePath = Join-Path $PSScriptRoot "active_sessions.csv"
    $CSVPath    = Join-Path $PSScriptRoot "sessions.csv"
    $today = (Get-Date).ToString("yyyy-MM-dd")

    if (-not (Test-Path $ActivePath)) { return }

    $gameId = $args.Game.Id.ToString()
    $activeItems = Import-Csv $ActivePath
    $remaining = @()

    foreach ($item in $activeItems) {
        if ($item.game_id -eq $gameId) {
            $start = [datetime]::Parse($item.start_time)
            $duration = [int]((Get-Date) - $start).TotalSeconds

            if ($duration -ge 5) {
                $finished = [PSCustomObject]@{
                    game_id          = $item.game_id
                    game_name        = $item.game_name
                    date             = $today
                    duration_seconds = $duration
                }

                $finished | Export-Csv -Path $CSVPath -Append -NoTypeInformation -Encoding utf8
            }
        }
        else {
            $remaining += $item
        }
    }

    if ($remaining.Count -gt 0) {
        $remaining | Export-Csv -Path $ActivePath -NoTypeInformation -Encoding utf8 -Force
    }
    else {
        Remove-Item $ActivePath -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------
# Exports
# ---------------------------------------------------------

Export-ModuleMember -Function `
GetMainMenuItems, `
Show-TodayStats, `
Show-TopPlayedToday, `
Reset-TodayStats, `
Reset-AllTodayStats, `
OnGameStarted, `
OnGameStopped
