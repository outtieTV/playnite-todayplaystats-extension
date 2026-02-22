# =========================================================
# TodayPlayStats - JSON Version with Session Metadata
# =========================================================

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
# Show Selected Game Stats (Formatted Output)
# ---------------------------------------------------------

function Show-TodayStats {
    param($args)

    $JSONPath = Join-Path $PSScriptRoot "sessions.json"
    $today = (Get-Date).ToString("yyyy-MM-dd")

    $selected = $PlayniteApi.MainView.SelectedGames
    if (-not $selected -or $selected.Count -eq 0) {
        $PlayniteApi.Dialogs.ShowMessage("No game selected.", "Today Stats")
        return
    }

    $game = $selected[0]
    $gameId = $game.Id.ToString()

    if (-not (Test-Path $JSONPath)) {
        $PlayniteApi.Dialogs.ShowMessage("$($game.Name)`nNo sessions today.", "Today Stats")
        return
    }

    $all = Get-Content $JSONPath -Raw | ConvertFrom-Json
    $sessions = $all | Where-Object {
        $_.game_id -eq $gameId -and $_.date -eq $today
    }

    if (-not $sessions) {
        $PlayniteApi.Dialogs.ShowMessage("$($game.Name)`nNo sessions today.", "Today Stats")
        return
    }

    $totalSeconds = ($sessions | Measure-Object duration_seconds -Sum).Sum
    $totalSeconds = [int]$totalSeconds
    $h = [math]::Floor($totalSeconds / 3600)
    $m = [math]::Floor(($totalSeconds % 3600) / 60)

    $sessionCount = @($sessions).Count

    $output = ""
    $output += "$($game.Name)`n"
    $output += "----------------------------------`n"
    $output += "Total Time: $h h $m m`n"
    $output += "Sessions: $sessionCount`n"

    if ($sessionCount -ge 1) {

        $output += "`n# | Start Time       | End Time         | Duration"
        $output += "`n-------------------------------------------------------------"

        foreach ($s in $sessions | Sort-Object session_number) {

            $start = ([datetime]$s.start_time).ToString("HH:mm:ss")
            $end   = ([datetime]$s.end_time).ToString("HH:mm:ss")

            $sec = [int]$s.duration_seconds
            $sh = [math]::Floor($sec / 3600)
            $sm = [math]::Floor(($sec % 3600) / 60)

            $durText = "$sh h $sm m"

            $line = "{0,2} | {1,-15} | {2,-15} | {3}" -f `
                $s.session_number, $start, $end, $durText

            $output += "`n$line"
        }
    }

    $PlayniteApi.Dialogs.ShowMessage($output, "Today Stats")
}

# ---------------------------------------------------------
# Top Played
# ---------------------------------------------------------

function Show-TopPlayedToday {
    param($args)

    $JSONPath = Join-Path $PSScriptRoot "sessions.json"
    $today = (Get-Date).ToString("yyyy-MM-dd")

    if (-not (Test-Path $JSONPath)) {
        $PlayniteApi.Dialogs.ShowMessage("No stats recorded.", "Top Played")
        return
    }

    $sessions = Get-Content $JSONPath -Raw | ConvertFrom-Json
    $sessions = $sessions | Where-Object { $_.date -eq $today }

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

    $PlayniteApi.Dialogs.ShowMessage("Top Today:`n$($top.Name)`n$h h $m m", "Top Played")
}

# ---------------------------------------------------------
# Reset Functions (Same Logic)
# ---------------------------------------------------------

function Reset-TodayStats {
    param($args)

    $JSONPath = Join-Path $PSScriptRoot "sessions.json"
    $today = (Get-Date).ToString("yyyy-MM-dd")

    $selected = $PlayniteApi.MainView.SelectedGames
    if (-not $selected -or -not (Test-Path $JSONPath)) { return }

    $targetId = $selected[0].Id.ToString()
    $all = Get-Content $JSONPath -Raw | ConvertFrom-Json

    $remaining = $all | Where-Object {
        -not ($_.game_id -eq $targetId -and $_.date -eq $today)
    }

    if ($remaining) {
        $remaining | ConvertTo-Json -Depth 5 | Out-File $JSONPath -Encoding utf8
    }
    else {
        Remove-Item $JSONPath -ErrorAction SilentlyContinue
    }

    $PlayniteApi.Dialogs.ShowMessage("Cleared today's stats.", "Reset")
}

function Reset-AllTodayStats {
    param($args)

    $JSONPath = Join-Path $PSScriptRoot "sessions.json"
    $today = (Get-Date).ToString("yyyy-MM-dd")

    if (-not (Test-Path $JSONPath)) { return }

    $all = Get-Content $JSONPath -Raw | ConvertFrom-Json
    $remaining = $all | Where-Object { $_.date -ne $today }

    if ($remaining) {
        $remaining | ConvertTo-Json -Depth 5 | Out-File $JSONPath -Encoding utf8
    }
    else {
        Remove-Item $JSONPath -ErrorAction SilentlyContinue
    }

    $PlayniteApi.Dialogs.ShowMessage("All today's stats cleared.", "Reset")
}

# ---------------------------------------------------------
# Game Started
# ---------------------------------------------------------

function OnGameStarted {
    param($args)

    $ActivePath = Join-Path $PSScriptRoot "active_sessions.json"
    $gameId = $args.Game.Id.ToString()

    if (Test-Path $ActivePath) {
        $active = Get-Content $ActivePath -Raw | ConvertFrom-Json
        if ($active | Where-Object { $_.game_id -eq $gameId }) { return }
    }

    $newSession = [PSCustomObject]@{
        game_id    = $gameId
        game_name  = $args.Game.Name
        start_time = (Get-Date).ToString("o")
    }

    if (Test-Path $ActivePath) {
        $active = Get-Content $ActivePath -Raw | ConvertFrom-Json
        $active += $newSession
    } else {
        $active = @($newSession)
    }

    $active | ConvertTo-Json -Depth 5 | Out-File $ActivePath -Encoding utf8
}

# ---------------------------------------------------------
# Game Stopped (Adds Session # + Start/End)
# ---------------------------------------------------------

function OnGameStopped {
    param($args)

    $ActivePath = Join-Path $PSScriptRoot "active_sessions.json"
    $JSONPath   = Join-Path $PSScriptRoot "sessions.json"
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $gameId = $args.Game.Id.ToString()

    if (-not (Test-Path $ActivePath)) { return }

    $activeItems = Get-Content $ActivePath -Raw | ConvertFrom-Json
    $remaining = @()

    foreach ($item in $activeItems) {

        if ($item.game_id -eq $gameId) {

            $startTime = [datetime]::Parse($item.start_time)
            $endTime = Get-Date
            $duration = [int]($endTime - $startTime).TotalSeconds

            if ($duration -ge 5) {

                if (Test-Path $JSONPath) {
                    $all = Get-Content $JSONPath -Raw | ConvertFrom-Json
                } else {
                    $all = @()
                }

                $todaySessions = $all | Where-Object {
                    $_.game_id -eq $gameId -and $_.date -eq $today
                }

                $sessionNumber = (@($todaySessions).Count) + 1

                $finished = [PSCustomObject]@{
                    session_number   = $sessionNumber
                    game_id          = $item.game_id
                    game_name        = $item.game_name
                    date             = $today
                    start_time       = $startTime.ToString("o")
                    end_time         = $endTime.ToString("o")
                    duration_seconds = $duration
                }

                $all += $finished
                $all | ConvertTo-Json -Depth 5 | Out-File $JSONPath -Encoding utf8
            }
        }
        else {
            $remaining += $item
        }
    }

    if ($remaining.Count -gt 0) {
        $remaining | ConvertTo-Json -Depth 5 | Out-File $ActivePath -Encoding utf8
    }
    else {
        Remove-Item $ActivePath -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function `
GetMainMenuItems, `
Show-TodayStats, `
Show-TopPlayedToday, `
Reset-TodayStats, `
Reset-AllTodayStats, `
OnGameStarted, `
OnGameStopped
