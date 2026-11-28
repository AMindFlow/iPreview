using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace IPreview;

public sealed partial class AudioRecordDeck : UserControl
{
    public static readonly DependencyProperty ArtworkProperty = DependencyProperty.Register(
        nameof(Artwork), typeof(ImageSource), typeof(AudioRecordDeck),
        new PropertyMetadata(null, static (d, e) => ((AudioRecordDeck)d).ArtworkBrush.ImageSource = e.NewValue as ImageSource));

    public static readonly DependencyProperty IsPlayingProperty = DependencyProperty.Register(
        nameof(IsPlaying), typeof(bool), typeof(AudioRecordDeck),
        new PropertyMetadata(false, static (d, _) => ((AudioRecordDeck)d).UpdateTonearm()));

    public AudioRecordDeck()
    {
        InitializeComponent();
        UpdateTonearm();
    }

    public ImageSource? Artwork
    {
        get => (ImageSource?)GetValue(ArtworkProperty);
        set => SetValue(ArtworkProperty, value);
    }

    public bool IsPlaying
    {
        get => (bool)GetValue(IsPlayingProperty);
        set => SetValue(IsPlayingProperty, value);
    }

    private void UpdateTonearm() => TonearmRotate.Angle = IsPlaying ? 20d : 0d;
}
