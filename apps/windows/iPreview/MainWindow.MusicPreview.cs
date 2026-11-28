using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Media;
using Windows.Media.Playback;
using Windows.Storage;
using Windows.Storage.Streams;

namespace IPreview;

public sealed partial class MainWindow
{
    private sealed record MusicAlbum(string Name, Media[] Tracks, Media[] Covers);

    private MusicAlbum? musicPreview;
    private CancellationTokenSource? musicCoverLoad;
    private Media? currentAlbumTrack;

    private static MusicAlbum? MusicAlbumFrom(string name, IEnumerable<Media> members, string folder)
    {
        var files = members.Where(item => item.ParentRelativePath == folder).ToArray();
        var tracks = files.Where(item => item.IsAudio)
            .OrderBy(item => item.FileName, MediaSearch.NaturalName).ToArray();
        if (tracks.Length == 0)
            return null;
        var covers = files.Where(item => item.IsImage && item.Available)
            .OrderBy(item => item.FileName, MediaSearch.NaturalName).ToArray();
        return new(name, tracks, covers);
    }

    private MusicAlbum AlbumForTrack(Media track)
    {
        var folder = track.ParentRelativePath;
        var name = folder.Length == 0 ? track.Source.Name : MediaFiles.FolderName(folder);
        var members = media.Where(item => item.Source.Id == track.Source.Id && item.Present && item.Id != track.Id);
        return MusicAlbumFrom(name, members.Append(track), folder)
            ?? throw new InvalidOperationException("已索引曲目应归属于其实际目录。");
    }

    private void PreviewCurrentMusic(object sender, RoutedEventArgs args)
    {
        if (currentAlbumTrack is not { } track || SelectingAlbumMembers)
            return;
        var items = tiles.ToList();
        var index = items.FindIndex(tile => tile.Media.Id == track.Id);
        if (index >= 0)
            OpenPreview(items, index, new(browseMode, Columns));
    }

    private async Task ShowMusicTrack(Media track, int generation)
    {
        if (musicPreview is null)
        {
            musicPreview = AlbumForTrack(track);
            previewSort.Cancel();
            previewTiles = musicPreview.Tracks.Select((media, index) => new Tile(media, index)).ToList();
            originalPreviewTiles = previewTiles;
            previewIndex = previewTiles.FindIndex(tile => tile.Media.Id == track.Id);
            MusicAlbumTitle.Text = musicPreview.Name;
            MusicTracks.ItemsSource = previewTiles;
            PreviewSortButton.Visibility = IndexLabel.Visibility = Visibility.Collapsed;
            VideoLock.Visibility = Visibility.Collapsed;
            UpdateMusicButtonLabels(true);
            _ = LoadMusicPreviewCover(musicPreview);
        }

        MusicStage.Visibility = Visibility.Visible;
        MusicDeck.IsPlaying = false;
        PrepareImagePreview(image: false);
        PreviewTopRail.Height = PreviewBottomRail.Height = new(0);
        PreviewLeftRail.Width = PreviewRightRail.Width = new(0);
        MainImage.Visibility = VideoSurface.Visibility = PreviewError.Visibility = Visibility.Collapsed;
        VideoControls.Visibility = Visibility.Visible;
        PlayPause.IsEnabled = false;
        PlayPause.Content = "播放";
        SetPreviewSeekEnabled(false);
        settingPosition = true;
        Timeline.Maximum = 1;
        Timeline.Value = 0;
        settingPosition = false;
        TimeLabel.Text = DurationLabel.Text = "0:00";
        MusicTrackError.Visibility = Visibility.Collapsed;
        PreviewTitle.Text = track.FileName;
        PreviewHint.Text = "";
        MusicTracks.SelectedIndex = previewIndex;
        MusicTracks.ScrollIntoView(previewTiles[previewIndex]);
        UpdatePreviewNavigation();
        RefreshPreviewNeighbors();

        try
        {
            var file = await OpenMediaFile(track);
            if (CanUpdatePreview(generation))
                StartMedia(file, track, generation);
        }
        catch (Exception error) when (MediaFailure(error))
        {
            if (CanUpdatePreview(generation))
                ShowMusicTrackError(error.Message);
        }
    }

    private void ChangeMusicTrack(object sender, SelectionChangedEventArgs args)
    {
        if (musicPreview is not null && !previewClosing && MusicTracks.SelectedIndex >= 0 &&
            MusicTracks.SelectedIndex != previewIndex)
            ShowPreview(MusicTracks.SelectedIndex, poster: null);
    }

    private void MoveMusicTrack(int direction)
    {
        var destination = previewIndex + direction;
        if (!previewClosing && destination >= 0 && destination < previewTiles.Count)
            ShowPreview(destination, poster: null);
    }

    private void ShowMusicTrackError(string detail)
    {
        StopVideo();
        MusicDeck.IsPlaying = false;
        PlayPause.IsEnabled = false;
        PlayPause.Content = "播放";
        SetPreviewSeekEnabled(false);
        MusicTrackError.Text = string.IsNullOrWhiteSpace(detail)
            ? "无法播放此曲目。" : $"无法播放此曲目。{Environment.NewLine}{detail}";
        MusicTrackError.Visibility = Visibility.Visible;
    }

    private void UpdateMusicButtonLabels(bool music)
    {
        VideoBack.Content = music ? "上一曲" : "−15 秒";
        VideoForward.Content = music ? "下一曲" : "+15 秒";
        AutomationProperties.SetName(VideoBack, music ? "上一曲" : "后退 15 秒");
        AutomationProperties.SetName(VideoForward, music ? "下一曲" : "前进 15 秒");
        AutomationProperties.SetName(Timeline, music ? "曲目进度" : "视频进度");
    }

    private void ResetMusicPreview()
    {
        if (musicPreview is null)
            return;
        musicPreview = null;
        musicCoverLoad?.Cancel();
        MusicStage.Visibility = Visibility.Collapsed;
        MusicTracks.ItemsSource = null;
        MusicCoverImage.Source = null;
        MusicDeck.Artwork = null;
        MusicDeck.IsPlaying = false;
        MusicCoverPlaceholder.Visibility = Visibility.Visible;
        UpdateMusicButtonLabels(false);
    }

    private async Task LoadMusicPreviewCover(MusicAlbum album)
    {
        using var request = new CancellationTokenSource();
        musicCoverLoad = request;
        try
        {
            var cover = await ReadMusicCover(album, 720, request.Token);
            if (ReferenceEquals(album, musicPreview) && !request.IsCancellationRequested)
            {
                MusicCoverImage.Source = cover;
                MusicDeck.Artwork = cover;
                MusicCoverPlaceholder.Visibility = cover is null ? Visibility.Visible : Visibility.Collapsed;
            }
        }
        catch (OperationCanceledException) when (request.IsCancellationRequested) { }
        finally
        {
            if (ReferenceEquals(musicCoverLoad, request))
                musicCoverLoad = null;
        }
    }

    private static async Task<BitmapImage?> ReadMusicCover(MusicAlbum album, int width, CancellationToken cancellationToken = default)
    {
        foreach (var image in album.Covers)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (await ReadCoverImage(image, width, cancellationToken) is { } bitmap)
                return bitmap;
        }
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            using var reader = new MediaPlayer();
            reader.CommandManager.IsEnabled = false;
            var updater = reader.SystemMediaTransportControls.DisplayUpdater;
            foreach (var track in album.Tracks.Where(track => track.Available))
            {
                cancellationToken.ThrowIfCancellationRequested();
                try
                {
                    var file = await OpenMediaFile(track, cancellationToken);
                    var native = await ReadNativeMusicCover(updater, file, width, cancellationToken);
                    if (native is not null)
                        return native;
                    if (file.FileType.Equals(".mp3", StringComparison.OrdinalIgnoreCase) &&
                        await ReadMp3Cover(file, width, cancellationToken) is { } mp3)
                        return mp3;
                }
                catch (Exception error) when (MediaFailure(error)) { }
            }
        }
        catch (Exception error) when (MediaFailure(error)) { }
        return null;
    }

    private static async Task<BitmapImage?> ReadNativeMusicCover(SystemMediaTransportControlsDisplayUpdater updater,
        StorageFile file, int width, CancellationToken cancellationToken)
    {
        try
        {
            updater.ClearAll();
            if (!await updater.CopyFromFileAsync(MediaPlaybackType.Music, file).AsTask(cancellationToken) ||
                updater.Thumbnail is not { } art)
                return null;
            using var stream = await art.OpenReadAsync().AsTask(cancellationToken);
            return await DecodeCoverStream(stream, width, cancellationToken);
        }
        catch (Exception error) when (MediaFailure(error))
        {
            return null;
        }
    }

    private static async Task<BitmapImage?> ReadMp3Cover(StorageFile file, int width, CancellationToken cancellationToken)
    {
        using var stream = await file.OpenReadAsync().AsTask(cancellationToken);
        using var input = stream.AsStreamForRead();
        foreach (var picture in await Mp3Artwork.ReadAsync(input, cancellationToken))
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                using var contents = new MemoryStream(picture.Array!, picture.Offset, picture.Count, writable: false);
                using var source = contents.AsRandomAccessStream();
                if (await DecodeCoverStream(source, width, cancellationToken) is { } bitmap)
                    return bitmap;
            }
            catch (Exception error) when (MediaFailure(error)) { }
        }
        return null;
    }

    private static async Task<BitmapImage?> DecodeCoverStream(IRandomAccessStream source, int width,
        CancellationToken cancellationToken)
    {
        var bitmap = new BitmapImage { DecodePixelWidth = width };
        await bitmap.SetSourceAsync(source).AsTask(cancellationToken);
        return bitmap.PixelWidth > 0 ? bitmap : null;
    }

    private static async Task<BitmapImage?> ReadCoverImage(Media image, int width, CancellationToken cancellationToken = default)
    {
        try
        {
            var bitmap = await DecodeImage(image, width, false, cancellationToken: cancellationToken);
            return bitmap.PixelWidth > 0 ? bitmap : null;
        }
        catch (Exception error) when (MediaFailure(error))
        {
            return null;
        }
    }

    private async void LoadLibraryMusicCover(Border surface, IReadOnlyList<Media> configured, MusicAlbum album)
    {
        var context = surface.DataContext;
        var artwork = new Grid();
        var placeholder = new FontIcon { Glyph = "\uE8D6", FontSize = 22, Opacity = 0.65 };
        artwork.Children.Add(placeholder);
        var image = new Image { Stretch = Stretch.UniformToFill };
        artwork.Children.Add(image);
        surface.Child = artwork;

        var manual = await Task.WhenAll(configured.Select(cover => ReadCoverImage(cover, 360)));
        if (!CurrentArtwork())
            return;
        if (manual.Length != 0 && manual.All(bitmap => bitmap is not null))
        {
            surface.Child = CoverGrid(manual.Select(bitmap => new Image
            {
                Source = bitmap!, Stretch = Stretch.UniformToFill
            }).ToArray());
            return;
        }

        var cover = await ReadMusicCover(album, 360);
        if (cover is not null && CurrentArtwork())
        {
            image.Source = cover;
            placeholder.Visibility = Visibility.Collapsed;
        }

        bool CurrentArtwork() => ReferenceEquals(context, surface.DataContext) && ReferenceEquals(surface.Child, artwork);
    }
}
