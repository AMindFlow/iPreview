using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;

namespace IPreview;

public sealed partial class AlbumMediaPicker : UserControl
{
    private sealed record CreatorOption(string Label, string SourcePath, List<FolderOption> Folders);
    private sealed record FolderOption(string Label, List<Candidate> Items);
    private sealed class Candidate(Media media)
    {
        public Media Media { get; } = media;
        public string PlaceholderGlyph => Media.IsVideo ? "\uE714" : "\uE91B";
        public Visibility VideoBadge => Media.IsVideo ? Visibility.Visible : Visibility.Collapsed;
        public string RemoveLabel => $"移除 {Media.FileName}";
    }

    private readonly ObservableCollection<Candidate> staged = [];
    private readonly HashSet<long> stagedIDs = [];
    private readonly Func<Media, Task<BitmapImage?>> thumbnail;
    private bool changingSelection;
    private CancellationTokenSource? albumCheck;

    internal AlbumMediaPicker(IEnumerable<Media> available, IEnumerable<long> existing,
                              Func<Media, Task<BitmapImage?>> thumbnailLoader)
    {
        thumbnail = thumbnailLoader;
        InitializeComponent();
        Unloaded += (_, _) => albumCheck?.Cancel();
        var existingIDs = existing.ToHashSet();
        var groups = MediaSearch.ByPath(available.Where(item => item.Available))
            .GroupBy(item => (item.Source.Id, Creator: item.Source.Layout == Layout.MultiCreator
                ? item.RelativePath.Split('/')[0] : item.Source.Name));
        var options = groups.Select(group =>
        {
            var source = group.First().Source;
            var label = source.Layout == Layout.MultiCreator
                ? $"{group.Key.Creator} · {source.Name}" : source.Name;
            var folders = group.GroupBy(item => item.RelativePath[..(item.RelativePath.LastIndexOf('/') + 1)])
                .Select(folder => new FolderOption(
                    source.Layout == Layout.Flat ? source.Name : folder.Key.TrimEnd('/').Split('/')[^1],
                    folder.Where(item => !existingIDs.Contains(item.Id)).Select(item => new Candidate(item)).ToList()));
            return new CreatorOption(label, source.Path, folders.ToList());
        }).ToList();
        StagedList.ItemsSource = staged;
        Creators.ItemsSource = options;
        Creators.IsEnabled = options.Count != 0;
        Folders.IsEnabled = false;
        if (options.Count == 0)
            CandidateStatus.Text = "没有可用的媒体源";
    }

    internal Media[] SelectedMedia => staged.Select(item => item.Media).ToArray();
    internal event Action<bool>? CanAddChanged;

    internal void ShowAddError(string? message)
    {
        AddError.Message = message ?? string.Empty;
        AddError.IsOpen = message is not null;
    }

    private void CandidateGridSizeChanged(object sender, SizeChangedEventArgs args) => FitCandidateWidth();

    private void FitCandidateWidth()
    {
        if (Candidates.ItemsPanelRoot is ItemsWrapGrid grid && Candidates.ActualWidth > 0)
            grid.ItemWidth = Math.Min(152, Candidates.ActualWidth);
    }

    private void CreatorChanged(object sender, SelectionChangedEventArgs args)
    {
        var creator = Creators.SelectedItem as CreatorOption;
        Folders.ItemsSource = creator?.Folders;
        Folders.SelectedItem = null;
        Folders.IsEnabled = creator is not null;
        ChangeDisplayedAlbum(null);
    }

    private void AlbumChanged(object sender, SelectionChangedEventArgs args) =>
        ChangeDisplayedAlbum(Folders.SelectedItem as FolderOption);

    internal void RecheckCurrentAlbum() => ChangeDisplayedAlbum(Folders.SelectedItem as FolderOption);

    private async void ChangeDisplayedAlbum(FolderOption? album)
    {
        albumCheck?.Cancel();
        albumCheck = null;
        ShowCandidates(null);

        if (album is null)
        {
            CandidateStatus.Text = Creators.SelectedItem is null ? "先选择媒体源或创作者" : "请选择一个专辑";
            return;
        }

        using var check = new CancellationTokenSource();
        albumCheck = check;
        CandidateStatus.Text = "正在检查媒体…";
        try
        {
            var readable = await Task.Run(() =>
            {
                var result = new List<Candidate>();
                foreach (var candidate in album.Items)
                {
                    check.Token.ThrowIfCancellationRequested();
                    if (CanRead(candidate.Media))
                        result.Add(candidate);
                }
                return result;
            });
            if (check.IsCancellationRequested || !ReferenceEquals(albumCheck, check))
                return;
            ShowCandidates(readable);
            CandidateStatus.Text = "此专辑没有可添加的媒体";
        }
        catch (OperationCanceledException) when (check.IsCancellationRequested) { }
        finally
        {
            if (ReferenceEquals(albumCheck, check))
                albumCheck = null;
        }
    }

    private void ShowCandidates(List<Candidate>? items)
    {
        changingSelection = true;
        try
        {
            Candidates.ItemsSource = items;
            Candidates.SelectedItems.Clear();
            if (items is not null)
            {
                foreach (var item in items)
                    if (stagedIDs.Contains(item.Media.Id))
                        Candidates.SelectedItems.Add(item);
            }
        }
        finally
        {
            changingSelection = false;
        }
        CandidateEmpty.Visibility = Candidates.Items.Count > 0 ? Visibility.Collapsed : Visibility.Visible;
        FitCandidateWidth();
        UpdateButtons();
    }

    internal static bool CanRead(Media media)
    {
        try
        {
            MediaFiles.OpenPath(media);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return false;
        }
    }

    private void MediaSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        if (changingSelection)
            return;

        foreach (var item in args.RemovedItems.OfType<Candidate>())
            Unstage(item);
        foreach (var item in args.AddedItems.OfType<Candidate>())
            Stage(item);
        UpdateButtons();
    }

    private void SelectCurrentAlbum(object sender, RoutedEventArgs args)
    {
        changingSelection = true;
        try
        {
            foreach (var item in Candidates.Items.OfType<Candidate>())
                Stage(item);
            Candidates.SelectAll();
        }
        finally
        {
            changingSelection = false;
        }
        UpdateButtons();
    }

    private void Stage(Candidate item)
    {
        if (stagedIDs.Add(item.Media.Id))
            staged.Add(item);
    }

    private void RemoveStaged(object sender, RoutedEventArgs args)
    {
        if (sender is not Button { DataContext: Candidate item })
            return;
        if (Candidates.SelectedItems.Contains(item))
            Candidates.SelectedItems.Remove(item);
        else
        {
            Unstage(item);
            UpdateButtons();
        }
    }

    private void Unstage(Candidate item)
    {
        if (stagedIDs.Remove(item.Media.Id))
            staged.Remove(item);
    }

    private void UpdateButtons()
    {
        StagedHeading.Text = $"待添加 · {staged.Count} 项";
        QueueEmpty.Visibility = staged.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        SelectAllButton.IsEnabled = Candidates.SelectedItems.Count < Candidates.Items.Count;
        CanAddChanged?.Invoke(staged.Count != 0);
    }

    private void ThumbnailLoaded(object sender, RoutedEventArgs args) => ReadThumbnail((Image)sender);
    private void ThumbnailContextChanged(FrameworkElement sender, DataContextChangedEventArgs args)
    {
        if (sender.IsLoaded)
            ReadThumbnail((Image)sender);
    }

    private async void ReadThumbnail(Image image)
    {
        image.Source = null;
        if (image.DataContext is not Candidate item)
            return;
        var bitmap = await thumbnail(item.Media);
        if (image.IsLoaded && ReferenceEquals(image.DataContext, item))
            image.Source = bitmap;
    }
}
