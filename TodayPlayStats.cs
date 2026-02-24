using Playnite.SDK;
using Playnite.SDK.Models;
using Playnite.SDK.Events;
using Playnite.SDK.Plugins;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Newtonsoft.Json;

namespace TodayPlayStats
{
    // -----------------------------
    // DATA MODELS
    // -----------------------------
    public class SessionRecord
    {
        public int session_number { get; set; }
        public string game_id { get; set; }
        public string game_name { get; set; }
        public string date { get; set; }
        public DateTime start_time { get; set; }
        public DateTime end_time { get; set; }
        public int duration_seconds { get; set; }

        public string DurationFormatted =>
            TimeSpan.FromSeconds(duration_seconds).ToString(@"hh\:mm\:ss");
    }

    public class ActiveSession
    {
        public string game_id { get; set; }
        public string game_name { get; set; }
        public DateTime start_time { get; set; }
    }

    // -----------------------------
    // MAIN PLUGIN
    // -----------------------------
    public class TodayPlayStats : GenericPlugin
    {
        public override Guid Id { get; } =
            Guid.Parse("00000000-0000-0000-0000-000000000001");

        private string SessionsPath =>
            Path.Combine(GetPluginUserDataPath(), "sessions.json");

        private string ActivePath =>
            Path.Combine(GetPluginUserDataPath(), "active_sessions.json");

        private TopPanelItem playbackItem;

        public TodayPlayStats(IPlayniteAPI api) : base(api) { }

        // -----------------------------
        // TOP PANEL
        // -----------------------------
        public override IEnumerable<TopPanelItem> GetTopPanelItems()
        {
            playbackItem = new TopPanelItem
            {
                Title = GetTotalTimeText(),
                Activated = () => ShowTopPlayedToday()
            };

            yield return playbackItem;
        }

        private string GetTotalTimeText()
        {
            try
            {
                var today = DateTime.Now.ToString("yyyy-MM-dd");
                int totalSec = LoadSessions()
                    .Where(s => s.date == today)
                    .Sum(s => s.duration_seconds);

                return $"{totalSec / 3600}h {(totalSec % 3600) / 60}m";
            }
            catch { return "0h 0m"; }
        }

        private void RefreshTopPanel()
        {
            if (playbackItem != null)
                playbackItem.Title = GetTotalTimeText();
        }

        // -----------------------------
        // MENU
        // -----------------------------
        public override IEnumerable<MainMenuItem> GetMainMenuItems(GetMainMenuItemsArgs args)
        {
            return new List<MainMenuItem>
            {
                new MainMenuItem { Description="Show Selected Game Stats", MenuSection="@Today Stats", Action=_=>ShowTodayStats() },
                new MainMenuItem { Description="Show Top Played Today", MenuSection="@Today Stats", Action=_=>ShowTopPlayedToday() },
                new MainMenuItem { Description="Show All Sessions Today", MenuSection="@Today Stats", Action=_=>ShowAllSessionsToday() },
                new MainMenuItem { Description="Reset Selected Game", MenuSection="@Today Stats", Action=_=>ResetTodayStats() },
                new MainMenuItem { Description="Reset All Today", MenuSection="@Today Stats", Action=_=>ResetAllTodayStats() }
            };
        }

        // -----------------------------
        // EVENTS
        // -----------------------------
        public override void OnGameStarted(OnGameStartedEventArgs args)
        {
            var active = LoadActive();
            if (active.Any(a => a.game_id == args.Game.Id.ToString())) return;

            active.Add(new ActiveSession
            {
                game_id = args.Game.Id.ToString(),
                game_name = args.Game.Name,
                start_time = DateTime.Now
            });

            SaveActive(active);
        }

        public override void OnGameStopped(OnGameStoppedEventArgs args)
        {
            var active = LoadActive();
            var current = active.FirstOrDefault(a =>
                a.game_id == args.Game.Id.ToString());

            if (current == null) return;

            var duration = (int)(DateTime.Now - current.start_time).TotalSeconds;

            if (duration >= 5)
            {
                var all = LoadSessions();
                var today = DateTime.Now.ToString("yyyy-MM-dd");

                all.Add(new SessionRecord
                {
                    session_number = all.Count(s =>
                        s.game_id == current.game_id &&
                        s.date == today) + 1,
                    game_id = current.game_id,
                    game_name = current.game_name,
                    date = today,
                    start_time = current.start_time,
                    end_time = DateTime.Now,
                    duration_seconds = duration
                });

                SaveSessions(all);
                RefreshTopPanel();
            }

            active.Remove(current);
            SaveActive(active);
        }

        // -----------------------------
        // FANCY WINDOW
        // -----------------------------
        private void ShowFancyWindow(string title,
            List<SessionRecord> sessions,
            bool includeGameColumn)
        {
            var window = new Window
            {
                Title = title,
                Width = 900,
                Height = 550,
                Background = new SolidColorBrush(Color.FromRgb(30, 30, 30)),
                Foreground = Brushes.White,
                WindowStartupLocation = WindowStartupLocation.CenterScreen
            };

            var mainGrid = new Grid();
            mainGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            mainGrid.RowDefinitions.Add(new RowDefinition());
            mainGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            // Header
            var header = new TextBlock
            {
                Text = title,
                FontSize = 26,
                FontWeight = FontWeights.Bold,
                Margin = new Thickness(15),
                Foreground = Brushes.DeepSkyBlue
            };
            Grid.SetRow(header, 0);
            mainGrid.Children.Add(header);

            // DataGrid
            var dataGrid = new DataGrid
            {
                ItemsSource = sessions.OrderBy(s => s.start_time),
                AutoGenerateColumns = false,
                Margin = new Thickness(10),
                Background = new SolidColorBrush(Color.FromRgb(45, 45, 45)),
                RowBackground = new SolidColorBrush(Color.FromRgb(40, 40, 40)),
                AlternatingRowBackground = new SolidColorBrush(Color.FromRgb(55, 55, 55)),
                Foreground = Brushes.White,
                GridLinesVisibility = DataGridGridLinesVisibility.Horizontal
            };

            dataGrid.Columns.Add(new DataGridTextColumn { Header = "#", Binding = new System.Windows.Data.Binding("session_number") });

            if (includeGameColumn)
            {
                dataGrid.Columns.Add(new DataGridTextColumn
                {
                    Header = "Game",
                    Binding = new System.Windows.Data.Binding("game_name")
                });
            }

            dataGrid.Columns.Add(new DataGridTextColumn { Header = "Start", Binding = new System.Windows.Data.Binding("start_time") });
            dataGrid.Columns.Add(new DataGridTextColumn { Header = "End", Binding = new System.Windows.Data.Binding("end_time") });
            dataGrid.Columns.Add(new DataGridTextColumn { Header = "Duration", Binding = new System.Windows.Data.Binding("DurationFormatted") });

            Grid.SetRow(dataGrid, 1);
            mainGrid.Children.Add(dataGrid);

            int totalSec = sessions.Sum(s => s.duration_seconds);

            var totalText = new TextBlock
            {
                Text = $"Total: {TimeSpan.FromSeconds(totalSec):hh\\:mm\\:ss}",
                FontSize = 20,
                FontWeight = FontWeights.Bold,
                Margin = new Thickness(15),
                Foreground = Brushes.LimeGreen,
                HorizontalAlignment = HorizontalAlignment.Right
            };

            Grid.SetRow(totalText, 2);
            mainGrid.Children.Add(totalText);

            window.Content = mainGrid;
            window.ShowDialog();
        }

        // -----------------------------
        // LOGIC
        // -----------------------------
        private void ShowTodayStats()
        {
            var selected = PlayniteApi.MainView.SelectedGames.FirstOrDefault();
            if (selected == null) return;

            var today = DateTime.Now.ToString("yyyy-MM-dd");

            var sessions = LoadSessions()
                .Where(s => s.game_id == selected.Id.ToString() && s.date == today)
                .ToList();

            if (!sessions.Any())
            {
                PlayniteApi.Dialogs.ShowMessage("No sessions today.");
                return;
            }

            ShowFancyWindow(selected.Name + " - Today", sessions, false);
        }

        private void ShowTopPlayedToday()
        {
            var today = DateTime.Now.ToString("yyyy-MM-dd");

            var topGame = LoadSessions()
                .Where(s => s.date == today)
                .GroupBy(s => s.game_id)
                .Select(g => new
                {
                    Name = g.First().game_name,
                    Sessions = g.ToList(),
                    Total = g.Sum(x => x.duration_seconds)
                })
                .OrderByDescending(x => x.Total)
                .FirstOrDefault();

            if (topGame == null)
            {
                PlayniteApi.Dialogs.ShowMessage("No sessions today.");
                return;
            }

            ShowFancyWindow("Top Today: " + topGame.Name,
                topGame.Sessions,
                false);
        }

        private void ShowAllSessionsToday()
        {
            var today = DateTime.Now.ToString("yyyy-MM-dd");

            var sessions = LoadSessions()
                .Where(s => s.date == today)
                .OrderBy(s => s.start_time)
                .ToList();

            if (!sessions.Any())
            {
                PlayniteApi.Dialogs.ShowMessage("No sessions today.");
                return;
            }

            ShowFancyWindow("All Sessions Today",
                sessions,
                true);
        }

        private void ResetTodayStats()
        {
            var selected = PlayniteApi.MainView.SelectedGames.FirstOrDefault();
            if (selected == null) return;

            var today = DateTime.Now.ToString("yyyy-MM-dd");

            SaveSessions(
                LoadSessions()
                .Where(s => !(s.game_id == selected.Id.ToString() && s.date == today))
                .ToList());

            RefreshTopPanel();
        }

        private void ResetAllTodayStats()
        {
            var today = DateTime.Now.ToString("yyyy-MM-dd");

            SaveSessions(
                LoadSessions()
                .Where(s => s.date != today)
                .ToList());

            RefreshTopPanel();
        }

        // -----------------------------
        // STORAGE
        // -----------------------------
        private List<SessionRecord> LoadSessions() =>
            File.Exists(SessionsPath)
                ? JsonConvert.DeserializeObject<List<SessionRecord>>(File.ReadAllText(SessionsPath))
                : new List<SessionRecord>();

        private void SaveSessions(List<SessionRecord> data) =>
            File.WriteAllText(SessionsPath,
                JsonConvert.SerializeObject(data, Formatting.Indented));

        private List<ActiveSession> LoadActive() =>
            File.Exists(ActivePath)
                ? JsonConvert.DeserializeObject<List<ActiveSession>>(File.ReadAllText(ActivePath))
                : new List<ActiveSession>();

        private void SaveActive(List<ActiveSession> data) =>
            File.WriteAllText(ActivePath,
                JsonConvert.SerializeObject(data, Formatting.Indented));
    }
}