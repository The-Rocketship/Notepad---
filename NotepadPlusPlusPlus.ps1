# Notepad+++ - Native Dark Mode Tabbed Text Editor for Windows
# Written in PowerShell + WPF (no installation required)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Compile native scroll synchronizer and syntax highlighter to run at native speed (0ms PowerShell overhead)
$source = @"
using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Media;

public static class ScrollHelper {
    public static ScrollViewer FindScrollViewer(DependencyObject obj) {
        if (obj == null) return null;
        if (obj is ScrollViewer) return (ScrollViewer)obj;
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(obj); i++) {
            var child = VisualTreeHelper.GetChild(obj, i);
            var result = FindScrollViewer(child);
            if (result != null) return result;
        }
        return null;
    }

    public static void BindScroll(TextBoxBase editor, TextBoxBase lineNumbers) {
        editor.Loaded += (s, e) => {
            var svEditor = FindScrollViewer(editor);
            var svLines = FindScrollViewer(lineNumbers);
            if (svEditor != null && svLines != null) {
                svEditor.ScrollChanged += (sender, args) => {
                    if (args.VerticalChange != 0) {
                        svLines.ScrollToVerticalOffset(svEditor.VerticalOffset);
                    }
                };
            }
        };
    }
}

public class HighlightRule {
    public Regex RegexPattern { get; set; }
    public Brush ColorBrush { get; set; }
    public bool Underline { get; set; }
}

public class MatchInfo {
    public int Index { get; set; }
    public int Length { get; set; }
    public Brush ColorBrush { get; set; }
    public bool Underline { get; set; }
}

public static class SyntaxHighlighter {
    private static readonly Dictionary<string, List<HighlightRule>> Rules = new Dictionary<string, List<HighlightRule>>();

    static SyntaxHighlighter() {
        // PowerShell
        Rules["PowerShell"] = new List<HighlightRule> {
            new HighlightRule { RegexPattern = new Regex(@"(?ms)<#.*?#>", RegexOptions.Compiled), ColorBrush = Brushes.Green, Underline = false },
            new HighlightRule { RegexPattern = new Regex(@"#.*", RegexOptions.Compiled), ColorBrush = Brushes.Green, Underline = false },
            new HighlightRule { RegexPattern = new Regex(@"""[^""\\]*(?:\\.[^""\\]*)*""", RegexOptions.Compiled), ColorBrush = Brushes.DarkRed, Underline = false },
            new HighlightRule { RegexPattern = new Regex(@"'[^'\\]*(?:\\.[^'\\]*)*'", RegexOptions.Compiled), ColorBrush = Brushes.DarkRed, Underline = false },
            new HighlightRule { RegexPattern = new Regex(@"\b(if|else|elseif|foreach|for|while|do|until|switch|case|default|break|continue|return|function|filter|workflow|param|class|using|try|catch|finally|throw|exit)\b", RegexOptions.IgnoreCase | RegexOptions.Compiled), ColorBrush = Brushes.Blue, Underline = true }
        };

        // Batch / CMD
        Rules["Batch / CMD"] = new List<HighlightRule> {
            new HighlightRule { RegexPattern = new Regex(@"(?i)\b(rem\b.*|::.*)", RegexOptions.Compiled), ColorBrush = Brushes.Green, Underline = false },
            new HighlightRule { RegexPattern = new Regex(@"\b(echo|set|if|else|goto|call|exit|pause|for|in|do|shift|cls)\b", RegexOptions.IgnoreCase | RegexOptions.Compiled), ColorBrush = Brushes.Blue, Underline = true }
        };

        // Bash
        Rules["Bash"] = new List<HighlightRule> {
            new HighlightRule { RegexPattern = new Regex(@"#.*", RegexOptions.Compiled), ColorBrush = Brushes.Green, Underline = false },
            new HighlightRule { RegexPattern = new Regex(@"""[^""\\]*(?:\\.[^""\\]*)*""", RegexOptions.Compiled), ColorBrush = Brushes.DarkRed, Underline = false },
            new HighlightRule { RegexPattern = new Regex(@"'[^'\\]*(?:\\.[^'\\]*)*'", RegexOptions.Compiled), ColorBrush = Brushes.DarkRed, Underline = false },
            new HighlightRule { RegexPattern = new Regex(@"\b(if|then|else|elif|fi|for|while|in|do|done|function|return|echo|exit|local|case|esac)\b", RegexOptions.IgnoreCase | RegexOptions.Compiled), ColorBrush = Brushes.Blue, Underline = true }
        };

        // VBScript
        Rules["VBScript"] = new List<HighlightRule> {
            new HighlightRule { RegexPattern = new Regex(@"'.*", RegexOptions.Compiled), ColorBrush = Brushes.Green, Underline = false },
            new HighlightRule { RegexPattern = new Regex(@"""[^""\\]*(?:\\.[^""\\]*)*""", RegexOptions.Compiled), ColorBrush = Brushes.DarkRed, Underline = false },
            new HighlightRule { RegexPattern = new Regex(@"\b(Dim|Sub|Function|If|Then|Else|ElseIf|End|For|To|Step|Next|While|Wend|Do|Loop|Select|Case|Exit|WScript)\b", RegexOptions.IgnoreCase | RegexOptions.Compiled), ColorBrush = Brushes.Blue, Underline = true }
        };

        // Registry
        Rules["Registry"] = new List<HighlightRule> {
            new HighlightRule { RegexPattern = new Regex(@";.*", RegexOptions.Compiled), ColorBrush = Brushes.Green, Underline = false },
            new HighlightRule { RegexPattern = new Regex(@"\b(Windows Registry Editor Version|HKEY_CLASSES_ROOT|HKEY_CURRENT_USER|HKEY_LOCAL_MACHINE|HKEY_USERS|HKEY_CURRENT_CONFIG)\b", RegexOptions.IgnoreCase | RegexOptions.Compiled), ColorBrush = Brushes.Blue, Underline = true }
        };
    }

    public static void Highlight(RichTextBox rtb, string lang, Brush defaultForeground) {
        if (rtb == null) return;
        
        TextPointer start = rtb.Document.ContentStart;
        TextPointer end = rtb.Document.ContentEnd;
        
        // Save caret offset
        TextPointer caret = rtb.CaretPosition;
        int caretOffset = new TextRange(start, caret).Text.Length;

        bool undoState = rtb.IsUndoEnabled;
        rtb.IsUndoEnabled = false;

        // Reset styling
        TextRange allRange = new TextRange(start, end);
        allRange.ApplyPropertyValue(TextElement.ForegroundProperty, defaultForeground);
        allRange.ApplyPropertyValue(Inline.TextDecorationsProperty, null);

        if (string.IsNullOrEmpty(lang) || !Rules.ContainsKey(lang)) {
            rtb.IsUndoEnabled = undoState;
            return;
        }

        string rawText = allRange.Text;
        var rules = Rules[lang];
        
        // Collect all matches
        var matchList = new List<MatchInfo>();
        foreach (var rule in rules) {
            var matches = rule.RegexPattern.Matches(rawText);
            foreach (Match m in matches) {
                matchList.Add(new MatchInfo {
                    Index = m.Index,
                    Length = m.Length,
                    ColorBrush = rule.ColorBrush,
                    Underline = rule.Underline
                });
            }
        }

        // Sort matches
        matchList.Sort((x, y) => x.Index.CompareTo(y.Index));

        // Highlight in one pass
        TextPointer pointer = start;
        int currentOffset = 0;

        foreach (var m in matchList) {
            int targetStart = m.Index;
            int targetEnd = m.Index + m.Length;

            TextPointer startPointer = null;
            TextPointer endPointer = null;

            while (pointer != null) {
                if (pointer.GetPointerContext(LogicalDirection.Forward) == TextPointerContext.Text) {
                    string text = pointer.GetTextInRun(LogicalDirection.Forward);
                    int len = text.Length;
                    if (currentOffset + len >= targetStart) {
                        startPointer = pointer.GetPositionAtOffset(targetStart - currentOffset, LogicalDirection.Forward);
                        break;
                    }
                    currentOffset += len;
                }
                pointer = pointer.GetNextContextPosition(LogicalDirection.Forward);
            }

            TextPointer endPointerScan = startPointer;
            int endOffset = targetStart;
            while (endPointerScan != null) {
                if (endPointerScan.GetPointerContext(LogicalDirection.Forward) == TextPointerContext.Text) {
                    string text = endPointerScan.GetTextInRun(LogicalDirection.Forward);
                    int len = text.Length;
                    if (endOffset + len >= targetEnd) {
                        endPointer = endPointerScan.GetPositionAtOffset(targetEnd - endOffset, LogicalDirection.Forward);
                        break;
                    }
                    endOffset += len;
                }
                endPointerScan = endPointerScan.GetNextContextPosition(LogicalDirection.Forward);
            }

            if (startPointer != null && endPointer != null) {
                TextRange range = new TextRange(startPointer, endPointer);
                if (m.ColorBrush != null) {
                    range.ApplyPropertyValue(TextElement.ForegroundProperty, m.ColorBrush);
                }
                if (m.Underline) {
                    var decs = new TextDecorationCollection();
                    decs.Add(TextDecorations.Underline);
                    range.ApplyPropertyValue(Inline.TextDecorationsProperty, decs);
                }
            }
        }

        // Restore caret
        pointer = start;
        currentOffset = 0;
        bool restored = false;
        while (pointer != null) {
            if (pointer.GetPointerContext(LogicalDirection.Forward) == TextPointerContext.Text) {
                string text = pointer.GetTextInRun(LogicalDirection.Forward);
                int len = text.Length;
                if (currentOffset + len >= caretOffset) {
                    rtb.CaretPosition = pointer.GetPositionAtOffset(caretOffset - currentOffset, LogicalDirection.Forward);
                    restored = true;
                    break;
                }
                currentOffset += len;
            }
            pointer = pointer.GetNextContextPosition(LogicalDirection.Forward);
        }
        if (!restored) {
            rtb.CaretPosition = rtb.Document.ContentEnd;
        }

        rtb.IsUndoEnabled = undoState;
    }
}
"@
Add-Type -TypeDefinition $source -ReferencedAssemblies "PresentationFramework", "PresentationCore", "WindowsBase", "System.Xaml"

# Global application state
$script:Tabs = @()  # List of tab states: @{ TabItem=$tab; Editor=$editor; LineNumbers=$lineNumbers; FilePath=$null; IsDirty=$false; OriginalText=""; Language="Normal Text" }
$script:CurrentTheme = "Dark"
$script:ZoomFactor = 1.0
$script:BaseFontSize = 14.0
$script:CurrentThemeColors = @{}
$script:IsHighlighting = $false

# Define modern colors/styles
$Themes = @{
    Dark = @{
        WindowBackground = "#1e1e1e"
        EditorBackground = "#1e1e1e"
        EditorForeground = "#d4d4d4"
        EditorCaret      = "#ffffff"
        LineNumBackground = "#1e1e1e"
        LineNumForeground = "#858585"
        LineNumBorder     = "#2d2d2d"
        MenuBackground    = "#252526"
        MenuForeground    = "#cccccc"
        MenuBorder        = "#3c3c3c"
        MenuHover         = "#3c3c3c"
        StatusBackground  = "#007acc"
        StatusForeground  = "#ffffff"
        TabBackground     = "#2d2d2d"
        TabForeground     = "#969696"
        TabSelectedBg     = "#1e1e1e"
        TabSelectedFg     = "#ffffff"
        SearchBackground  = "#252526"
        SearchForeground  = "#d4d4d4"
        SearchBorder      = "#3c3c3c"
    }
    Light = @{
        WindowBackground = "#f3f3f3"
        EditorBackground = "#ffffff"
        EditorForeground = "#000000"
        EditorCaret      = "#000000"
        LineNumBackground = "#f3f3f3"
        LineNumForeground = "#a0a0a0"
        LineNumBorder     = "#e4e4e4"
        MenuBackground    = "#f3f3f3"
        MenuForeground    = "#333333"
        MenuBorder        = "#dddddd"
        MenuHover         = "#e5e5e5"
        StatusBackground  = "#007acc"
        StatusForeground  = "#ffffff"
        TabBackground     = "#e1e1e1"
        TabForeground     = "#666666"
        TabSelectedBg     = "#ffffff"
        TabSelectedFg     = "#000000"
        SearchBackground  = "#f3f3f3"
        SearchForeground  = "#000000"
        SearchBorder      = "#dddddd"
    }
}

# XAML UI Layout Definition
[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Notepad+++" Width="1000" Height="700" 
        WindowStartupLocation="CenterScreen"
        Background="{DynamicResource WindowBg}" SnapsToDevicePixels="True">
    
    <Window.Icon>
        <DrawingImage>
            <DrawingImage.Drawing>
                <GeometryDrawing Geometry="M 2,8 H 14 M 8,2 V 14 M 18,8 H 30 M 24,2 V 14 M 34,8 H 46 M 40,2 V 14">
                    <GeometryDrawing.Pen>
                        <Pen Brush="#007acc" Thickness="3" StartLineCap="Round" EndLineCap="Round"/>
                    </GeometryDrawing.Pen>
                </GeometryDrawing>
            </DrawingImage.Drawing>
        </DrawingImage>
    </Window.Icon>
    
    <Window.Resources>
        <!-- Placeholders for dynamic theme colors -->
        <SolidColorBrush x:Key="WindowBg" Color="#1e1e1e"/>
        <SolidColorBrush x:Key="EditorBg" Color="#1e1e1e"/>
        <SolidColorBrush x:Key="EditorFg" Color="#d4d4d4"/>
        <SolidColorBrush x:Key="LineNumBg" Color="#1e1e1e"/>
        <SolidColorBrush x:Key="LineNumFg" Color="#858585"/>
        <SolidColorBrush x:Key="LineNumBorder" Color="#2d2d2d"/>
        <SolidColorBrush x:Key="MenuBg" Color="#252526"/>
        <SolidColorBrush x:Key="MenuFg" Color="#cccccc"/>
        <SolidColorBrush x:Key="MenuBorder" Color="#3c3c3c"/>
        <SolidColorBrush x:Key="MenuHoverBg" Color="#3c3c3c"/>
        <SolidColorBrush x:Key="StatusBg" Color="#007acc"/>
        <SolidColorBrush x:Key="StatusFg" Color="#ffffff"/>
        <SolidColorBrush x:Key="TabBg" Color="#2d2d2d"/>
        <SolidColorBrush x:Key="TabFg" Color="#969696"/>
        <SolidColorBrush x:Key="TabSelectedBg" Color="#1e1e1e"/>
        <SolidColorBrush x:Key="TabSelectedFg" Color="#ffffff"/>
        <SolidColorBrush x:Key="SearchBg" Color="#252526"/>
        <SolidColorBrush x:Key="SearchFg" Color="#d4d4d4"/>
        <SolidColorBrush x:Key="SearchBorder" Color="#3c3c3c"/>

        <!-- Custom menu and tab styling templates -->
        <Style TargetType="Menu">
            <Setter Property="Background" Value="{DynamicResource MenuBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource MenuFg}"/>
            <Setter Property="Padding" Value="5,3"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>

        <Style TargetType="Separator">
            <Setter Property="Background" Value="{DynamicResource MenuBorder}"/>
            <Setter Property="Margin" Value="2,4"/>
            <Setter Property="Height" Value="1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Separator">
                        <Border Height="1" Background="{TemplateBinding Background}" SnapsToDevicePixels="True"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="MenuItem">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{DynamicResource MenuFg}"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="MenuItem">
                        <Border Name="Border" Background="{TemplateBinding Background}" BorderBrush="Transparent" BorderThickness="0" CornerRadius="2" SnapsToDevicePixels="True" Margin="1,1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto" SharedSizeGroup="Icon"/>
                                    <ColumnDefinition Width="*" MinWidth="140"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                
                                <!-- Icon container -->
                                <ContentPresenter x:Name="Icon" Grid.Column="0" ContentSource="Icon" Margin="5,0,8,0" VerticalAlignment="Center"/>
                                
                                <!-- Header content -->
                                <ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="True" VerticalAlignment="Center" Margin="5,0"/>
                                
                                <!-- Input gesture text -->
                                <TextBlock Grid.Column="2" Text="{TemplateBinding InputGestureText}" Margin="15,0,8,0" Foreground="#808080" VerticalAlignment="Center" FontSize="11"/>
                                
                                <!-- Submenu Popup -->
                                <Popup Name="Popup" Placement="Right" IsOpen="{TemplateBinding IsSubmenuOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
                                    <Border BorderThickness="1" BorderBrush="{DynamicResource MenuBorder}" Background="{DynamicResource MenuBg}" CornerRadius="3" Padding="2" Margin="4">
                                        <Border.Effect>
                                            <DropShadowEffect BlurRadius="8" ShadowDepth="1.5" Direction="270" Opacity="0.3"/>
                                        </Border.Effect>
                                        <ScrollViewer IsTabStop="False">
                                            <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
                                        </ScrollViewer>
                                    </Border>
                                </Popup>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="{DynamicResource MenuHoverBg}"/>
                                <Setter Property="Foreground" Value="#ffffff"/>
                            </Trigger>
                            <Trigger Property="Role" Value="TopLevelHeader">
                                <Setter Property="Padding" Value="10,5"/>
                                <Setter TargetName="Popup" Property="Placement" Value="Bottom"/>
                            </Trigger>
                            <Trigger Property="Role" Value="TopLevelItem">
                                <Setter Property="Padding" Value="10,5"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Foreground" Value="#555555"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="TabControl">
            <Setter Property="Background" Value="{DynamicResource WindowBg}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="0"/>
        </Style>

        <!-- TabItem Style -->
        <Style TargetType="TabItem">
            <Setter Property="HeaderTemplate">
                <Setter.Value>
                    <DataTemplate>
                        <ContentPresenter Content="{TemplateBinding Content}"/>
                    </DataTemplate>
                </Setter.Value>
            </Setter>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border Name="Border" Background="{DynamicResource TabBg}" BorderBrush="{DynamicResource MenuBorder}" BorderThickness="0,0,1,1" Padding="12,6">
                            <ContentPresenter Name="Content" ContentSource="Header" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="{DynamicResource TabSelectedBg}"/>
                                <Setter TargetName="Border" Property="BorderThickness" Value="0,2,1,0"/>
                                <Setter TargetName="Border" Property="BorderBrush" Value="#007acc"/>
                                <Setter Property="Foreground" Value="{DynamicResource TabSelectedFg}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="False">
                                <Setter Property="Foreground" Value="{DynamicResource TabFg}"/>
                            </Trigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="IsMouseOver" Value="True"/>
                                    <Condition Property="IsSelected" Value="False"/>
                                </MultiTrigger.Conditions>
                                <Setter TargetName="Border" Property="Background" Value="{DynamicResource MenuHoverBg}"/>
                            </MultiTrigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- StatusBar Style -->
        <Style TargetType="StatusBar">
            <Setter Property="Background" Value="{DynamicResource StatusBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource StatusFg}"/>
            <Setter Property="Padding" Value="4,2"/>
        </Style>
        <Style TargetType="StatusBarItem">
            <Setter Property="Foreground" Value="{DynamicResource StatusFg}"/>
        </Style>

        <!-- Textbox Style in search bar -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{DynamicResource EditorBg}"/>
            <Setter Property="Foreground" Value="{DynamicResource EditorFg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource MenuBorder}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="4,3"/>
        </Style>
    </Window.Resources>

    <DockPanel LastChildFill="True">
        <!-- Menu Bar -->
        <Menu DockPanel.Dock="Top" Name="MainMenu">
            <MenuItem Header="_File" Name="MenuFile">
                <MenuItem Header="_New Tab" Name="MenuNew" InputGestureText="Ctrl+N"/>
                <MenuItem Header="_Open..." Name="MenuOpen" InputGestureText="Ctrl+O"/>
                <MenuItem Header="_Save" Name="MenuSave" InputGestureText="Ctrl+S"/>
                <MenuItem Header="Save _As..." Name="MenuSaveAs" InputGestureText="Ctrl+Shift+S"/>
                <Separator/>
                <MenuItem Header="_Close Tab" Name="MenuCloseTab" InputGestureText="Ctrl+W"/>
                <MenuItem Header="E_xit" Name="MenuExit" InputGestureText="Alt+F4"/>
            </MenuItem>
            <MenuItem Header="_Edit" Name="MenuEdit">
                <MenuItem Header="_Undo" Name="MenuUndo" InputGestureText="Ctrl+Z"/>
                <MenuItem Header="_Redo" Name="MenuRedo" InputGestureText="Ctrl+Y"/>
                <Separator/>
                <MenuItem Header="Cu_t" Name="MenuCut" InputGestureText="Ctrl+X"/>
                <MenuItem Header="_Copy" Name="MenuCopy" InputGestureText="Ctrl+C"/>
                <MenuItem Header="_Paste" Name="MenuPaste" InputGestureText="Ctrl+V"/>
                <MenuItem Header="Select _All" Name="MenuSelectAll" InputGestureText="Ctrl+A"/>
                <Separator/>
                <MenuItem Header="_Find / Replace..." Name="MenuFind" InputGestureText="Ctrl+F"/>
            </MenuItem>
            <MenuItem Header="_Language" Name="MenuLanguage">
                <MenuItem Header="_Normal Text" Name="LangNormal" Tag="Normal Text"/>
                <MenuItem Header="_PowerShell" Name="LangPowerShell" Tag="PowerShell"/>
                <MenuItem Header="_Batch / CMD" Name="LangBatch" Tag="Batch / CMD"/>
                <MenuItem Header="Ba_sh" Name="LangBash" Tag="Bash"/>
                <MenuItem Header="_VBScript" Name="LangVBScript" Tag="VBScript"/>
                <MenuItem Header="_Registry" Name="LangRegistry" Tag="Registry"/>
            </MenuItem>
            <MenuItem Header="_View" Name="MenuView">
                <MenuItem Header="Toggle _Dark/Light Mode" Name="MenuToggleTheme" InputGestureText="Ctrl+T"/>
                <Separator/>
                <MenuItem Header="Zoom _In" Name="MenuZoomIn" InputGestureText="Ctrl++"/>
                <MenuItem Header="Zoom _Out" Name="MenuZoomOut" InputGestureText="Ctrl+-"/>
                <MenuItem Header="_Reset Zoom" Name="MenuZoomReset" InputGestureText="Ctrl+0"/>
            </MenuItem>
        </Menu>

        <!-- Find & Replace Collapsible Panel -->
        <Border DockPanel.Dock="Top" Name="SearchPanel" Height="Auto" Visibility="Collapsed" BorderThickness="0,0,0,1" BorderBrush="{DynamicResource MenuBorder}" Padding="8" Background="{DynamicResource SearchBg}">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="200"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="200"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Find Row -->
                <TextBlock Grid.Column="0" Text="Find: " VerticalAlignment="Center" Margin="5" Foreground="{DynamicResource SearchFg}" Name="LblFind"/>
                <TextBox Grid.Column="1" Name="TxtFind" Margin="5" Padding="3" VerticalAlignment="Center"/>

                <!-- Replace Row -->
                <TextBlock Grid.Row="1" Grid.Column="0" Text="Replace: " VerticalAlignment="Center" Margin="5" Foreground="{DynamicResource SearchFg}" Name="LblReplace"/>
                <TextBox Grid.Row="1" Grid.Column="1" Name="TxtReplace" Margin="5" Padding="3" VerticalAlignment="Center"/>

                <!-- Checkboxes -->
                <StackPanel Grid.Column="2" Grid.RowSpan="2" Orientation="Vertical" VerticalAlignment="Center" Margin="10,0">
                    <CheckBox Name="ChkMatchCase" Content="Match Case" Margin="2" Foreground="{DynamicResource SearchFg}"/>
                    <CheckBox Name="ChkRegex" Content="Regular Expressions" Margin="2" Foreground="{DynamicResource SearchFg}"/>
                </StackPanel>

                <!-- Action Buttons -->
                <StackPanel Grid.Column="3" Grid.RowSpan="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button Name="BtnFindNext" Content="Find Next" Width="80" Height="25" Margin="5" Style="{StaticResource {x:Static ToolBar.ButtonStyleKey}}"/>
                    <Button Name="BtnReplace" Content="Replace" Width="80" Height="25" Margin="5" Style="{StaticResource {x:Static ToolBar.ButtonStyleKey}}"/>
                    <Button Name="BtnReplaceAll" Content="Replace All" Width="85" Height="25" Margin="5" Style="{StaticResource {x:Static ToolBar.ButtonStyleKey}}"/>
                </StackPanel>

                <!-- Close panel button -->
                <Button Grid.Column="5" Name="BtnCloseSearch" Content="&#x00D7;" FontSize="18" Width="25" Height="25" VerticalAlignment="Top" HorizontalAlignment="Right" Background="Transparent" BorderThickness="0" Foreground="#a0a0a0"/>
            </Grid>
        </Border>

        <!-- Status Bar -->
        <StatusBar DockPanel.Dock="Bottom" Name="MainStatusBar" Height="28">
            <StatusBarItem>
                <TextBlock Name="StatusInfo" Text="Ln 1, Col 1" Margin="5,0" FontSize="12"/>
            </StatusBarItem>
            <Separator Style="{DynamicResource {x:Static ToolBar.SeparatorStyleKey}}" Margin="4,0" Background="{DynamicResource MenuBorder}"/>
            <StatusBarItem>
                <TextBlock Name="StatusFilePath" Text="New Document" Margin="5,0" FontSize="12"/>
            </StatusBarItem>
            <Separator Style="{DynamicResource {x:Static ToolBar.SeparatorStyleKey}}" Margin="4,0" Background="{DynamicResource MenuBorder}"/>
            <StatusBarItem>
                <TextBlock Name="StatusLanguage" Text="Normal Text" Margin="5,0" FontSize="12"/>
            </StatusBarItem>
            <Separator Style="{DynamicResource {x:Static ToolBar.SeparatorStyleKey}}" Margin="4,0" Background="{DynamicResource MenuBorder}"/>
            <StatusBarItem HorizontalAlignment="Right">
                <TextBlock Name="StatusZoom" Text="Zoom: 100%" Margin="10,0" FontSize="12"/>
            </StatusBarItem>
        </StatusBar>

        <!-- Tabbed Editor Control -->
        <TabControl Name="TabControl" BorderThickness="0"/>
    </DockPanel>
</Window>
"@

# Helper to read XAML safely
$reader = New-Object System.Xml.XmlNodeReader $XAML
$Window = [Windows.Markup.XamlReader]::Load($reader)


# Map XAML controls to PowerShell variables
$MainMenu        = $Window.FindName("MainMenu")
$MenuFile        = $Window.FindName("MenuFile")
$MenuNew         = $Window.FindName("MenuNew")
$MenuOpen        = $Window.FindName("MenuOpen")
$MenuSave        = $Window.FindName("MenuSave")
$MenuSaveAs      = $Window.FindName("MenuSaveAs")
$MenuCloseTab    = $Window.FindName("MenuCloseTab")
$MenuExit        = $Window.FindName("MenuExit")
$MenuUndo        = $Window.FindName("MenuUndo")
$MenuRedo        = $Window.FindName("MenuRedo")
$MenuCut         = $Window.FindName("MenuCut")
$MenuCopy        = $Window.FindName("MenuCopy")
$MenuPaste       = $Window.FindName("MenuPaste")
$MenuSelectAll   = $Window.FindName("MenuSelectAll")
$MenuFind        = $Window.FindName("MenuFind")
$MenuLanguage    = $Window.FindName("MenuLanguage")
$MenuToggleTheme = $Window.FindName("MenuToggleTheme")
$MenuZoomIn      = $Window.FindName("MenuZoomIn")
$MenuZoomOut     = $Window.FindName("MenuZoomOut")
$MenuZoomReset   = $Window.FindName("MenuZoomReset")

$SearchPanel     = $Window.FindName("SearchPanel")
$TxtFind         = $Window.FindName("TxtFind")
$TxtReplace      = $Window.FindName("TxtReplace")
$ChkMatchCase    = $Window.FindName("ChkMatchCase")
$ChkRegex        = $Window.FindName("ChkRegex")
$BtnFindNext     = $Window.FindName("BtnFindNext")
$BtnReplace      = $Window.FindName("BtnReplace")
$BtnReplaceAll   = $Window.FindName("BtnReplaceAll")
$BtnCloseSearch  = $Window.FindName("BtnCloseSearch")
$LblFind         = $Window.FindName("LblFind")
$LblReplace      = $Window.FindName("LblReplace")

$MainStatusBar   = $Window.FindName("MainStatusBar")
$StatusInfo      = $Window.FindName("StatusInfo")
$StatusFilePath  = $Window.FindName("StatusFilePath")
$StatusLanguage  = $Window.FindName("StatusLanguage")
$StatusZoom      = $Window.FindName("StatusZoom")
$TabControl      = $Window.FindName("TabControl")

# Helper functions for RichTextBox text manipulation
function Get-EditorText {
    param($editor)
    if ($null -eq $editor) { return "" }
    $range = New-Object System.Windows.Documents.TextRange($editor.Document.ContentStart, $editor.Document.ContentEnd)
    $text = $range.Text
    # RichTextBox TextRange.Text always appends a trailing \r\n, we strip it to maintain accuracy
    if ($text.EndsWith("`r`n")) {
        $text = $text.Substring(0, $text.Length - 2)
    }
    return $text
}

function Set-EditorText {
    param($editor, $text)
    if ($null -eq $editor) { return }
    $editor.Document.Blocks.Clear()
    $p = New-Object System.Windows.Documents.Paragraph
    $p.Margin = New-Object System.Windows.Thickness(0)
    $p.Inlines.Add((New-Object System.Windows.Documents.Run($text)))
    $editor.Document.Blocks.Add($p)
}

# Fast C#-delegated syntax highlighter
function Highlight-Syntax {
    param($tabState)
    if ($null -eq $tabState) { return }
    [SyntaxHighlighter]::Highlight($tabState.Editor, $tabState.Language, $script:CurrentThemeColors.EditorForeground)
}

# Debouncing timer for highlighting and file updates
$script:HighlightTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:HighlightTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$script:HighlightTimer.add_Tick({
    $script:HighlightTimer.Stop()
    $tab = Get-ActiveTab
    if ($null -ne $tab) {
        $script:IsHighlighting = $true
        try {
            Update-LineNumbers $tab
            Update-DirtyState $tab
            Highlight-Syntax $tab
        }
        finally {
            $script:IsHighlighting = $false
        }
    }
})

# Helper to apply themes programmatically (binds colors natively in window resources)
function Apply-Theme {
    param([string]$ThemeName)
    $theme = $Themes[$ThemeName]
    $script:CurrentTheme = $ThemeName

    $bc = New-Object System.Windows.Media.BrushConverter
    
    # Store theme colors in Window resources for dynamic bindings
    $Window.Resources["WindowBg"] = $bc.ConvertFromString($theme.WindowBackground)
    $Window.Resources["EditorBg"] = $bc.ConvertFromString($theme.EditorBackground)
    $Window.Resources["EditorFg"] = $bc.ConvertFromString($theme.EditorForeground)
    
    $Window.Resources["LineNumBg"] = $bc.ConvertFromString($theme.LineNumBackground)
    $Window.Resources["LineNumFg"] = $bc.ConvertFromString($theme.LineNumForeground)
    $Window.Resources["LineNumBorder"] = $bc.ConvertFromString($theme.LineNumBorder)
    
    $Window.Resources["MenuBg"] = $bc.ConvertFromString($theme.MenuBackground)
    $Window.Resources["MenuFg"] = $bc.ConvertFromString($theme.MenuForeground)
    $Window.Resources["MenuBorder"] = $bc.ConvertFromString($theme.MenuBorder)
    $Window.Resources["MenuHoverBg"] = $bc.ConvertFromString($theme.MenuHover)
    
    $Window.Resources["StatusBg"] = $bc.ConvertFromString($theme.StatusBackground)
    $Window.Resources["StatusFg"] = $bc.ConvertFromString($theme.StatusForeground)
    
    $Window.Resources["TabBg"] = $bc.ConvertFromString($theme.TabBackground)
    $Window.Resources["TabFg"] = $bc.ConvertFromString($theme.TabForeground)
    $Window.Resources["TabSelectedBg"] = $bc.ConvertFromString($theme.TabSelectedBg)
    $Window.Resources["TabSelectedFg"] = $bc.ConvertFromString($theme.TabSelectedFg)
    
    $Window.Resources["SearchBg"] = $bc.ConvertFromString($theme.SearchBackground)
    $Window.Resources["SearchFg"] = $bc.ConvertFromString($theme.SearchForeground)
    $Window.Resources["SearchBorder"] = $bc.ConvertFromString($theme.SearchBorder)

    # Set globally compiled highlighter's current theme colors
    $script:CurrentThemeColors = @{
        EditorForeground = $bc.ConvertFromString($theme.EditorForeground)
        EditorBackground = $bc.ConvertFromString($theme.EditorBackground)
    }

    # Caret Brush logic
    $caretBrush = [System.Windows.Media.Brushes]::White
    if ($ThemeName -eq "Light") { $caretBrush = [System.Windows.Media.Brushes]::Black }
    
    # Apply to existing tabs
    foreach ($tabState in $script:Tabs) {
        $tabState.Editor.CaretBrush = $caretBrush
    }
    
    Highlight-Syntax (Get-ActiveTab)
}

# Update line numbers column based on content
function Update-LineNumbers {
    param($tabState)
    $editor = $tabState.Editor
    $lineNumbers = $tabState.LineNumbers
    
    $text = Get-EditorText $editor
    $lineCount = ($text -split "`r?`n").Count
    if ($lineCount -lt 1) { $lineCount = 1 }
    
    # Generate line numbers content
    $numbers = (1..$lineCount) -join "`r`n"
    $lineNumbers.Text = $numbers
}

# Update dirty state indicator
function Update-DirtyState {
    param($tabState)
    $currentText = Get-EditorText $tabState.Editor
    if ($currentText -ne $tabState.OriginalText) {
        if (-not $tabState.IsDirty) {
            $tabState.IsDirty = $true
            $tabState.TitleBlock.Text = "$($tabState.Title) *"
            Update-StatusBar $tabState
        }
    } else {
        if ($tabState.IsDirty) {
            $tabState.IsDirty = $false
            $tabState.TitleBlock.Text = $tabState.Title
            Update-StatusBar $tabState
        }
    }
}

# Update status bar info for active editor
function Update-StatusBar {
    param($tabState)
    if ($null -eq $tabState) {
        $StatusInfo.Text = ""
        $StatusFilePath.Text = "No Document Open"
        $StatusLanguage.Text = "Normal Text"
        $StatusZoom.Text = "Zoom: 100%"
        return
    }

    # Cursor line/col tracking using TextRange offset method
    $editor = $tabState.Editor
    $caretPointer = $editor.CaretPosition
    $startPointer = $editor.Document.ContentStart
    $range = New-Object System.Windows.Documents.TextRange($startPointer, $caretPointer)
    
    $textToCaret = $range.Text
    $lines = $textToCaret -split "\r?\n"
    $line = $lines.Count
    $col = $lines[-1].Length + 1
    
    $StatusInfo.Text = "Ln $line, Col $col"
    $StatusLanguage.Text = $tabState.Language

    # Zoom info
    $percent = [math]::Round($script:ZoomFactor * 100)
    $StatusZoom.Text = "Zoom: $percent%"

    # File path info
    if ($null -eq $tabState.FilePath) {
        $path = "New Document"
    } else {
        $path = $tabState.FilePath
    }
    if ($tabState.IsDirty) {
        $path += " *"
    }
    $StatusFilePath.Text = $path
}

# Language detector based on file extension
function Detect-Language {
    param([string]$FilePath)
    if ([string]::IsNullOrEmpty($FilePath)) { return "Normal Text" }
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    switch ($ext) {
        ".ps1"  { return "PowerShell" }
        ".psm1" { return "PowerShell" }
        ".psd1" { return "PowerShell" }
        ".bat"  { return "Batch / CMD" }
        ".cmd"  { return "Batch / CMD" }
        ".sh"   { return "Bash" }
        ".vbs"  { return "VBScript" }
        ".reg"  { return "Registry" }
        default { return "Normal Text" }
    }
}

# Create a new editor tab (RichTextBox based)
function Add-NewTab {
    param([string]$Title = "untitled", [string]$Content = "", [string]$FilePath = $null, [string]$Language = "Normal Text")

    # 1. Create Layout Grid for editor + line numbers
    $grid = New-Object System.Windows.Controls.Grid
    $col1 = New-Object System.Windows.Controls.ColumnDefinition
    $col1.Width = [System.Windows.GridLength]::Auto
    $col2 = New-Object System.Windows.Controls.ColumnDefinition
    $col2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $grid.ColumnDefinitions.Add($col1)
    $grid.ColumnDefinitions.Add($col2)

    # 2. Line Number Panel
    $lineNumBox = New-Object System.Windows.Controls.TextBox
    $lineNumBox.IsReadOnly = $true
    $lineNumBox.Focusable = $false
    $lineNumBox.Width = 45
    $lineNumBox.TextAlignment = [System.Windows.TextAlignment]::Right
    $lineNumBox.BorderThickness = 0
    $lineNumBox.Padding = New-Object System.Windows.Thickness(0, 4, 8, 4)
    $lineNumBox.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Hidden
    $lineNumBox.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Hidden
    
    # 3. Main Editor RichTextBox
    $editorBox = New-Object System.Windows.Controls.RichTextBox
    $editorBox.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $editorBox.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $editorBox.BorderThickness = 0
    $editorBox.Padding = New-Object System.Windows.Thickness(5, 4, 5, 4)
    
    # Turn off default RichTextBox formatting commands
    $editorBox.AutoWordSelection = $false
    
    # Apply Dynamic Resource references (prevents manual loop updating on theme changes)
    $lineNumBox.SetResourceReference([System.Windows.Controls.TextBox]::BackgroundProperty, "LineNumBg")
    $lineNumBox.SetResourceReference([System.Windows.Controls.TextBox]::ForegroundProperty, "LineNumFg")
    $lineNumBox.SetResourceReference([System.Windows.Controls.TextBox]::BorderBrushProperty, "LineNumBorder")
    
    $editorBox.SetResourceReference([System.Windows.Controls.RichTextBox]::BackgroundProperty, "EditorBg")
    $editorBox.SetResourceReference([System.Windows.Controls.RichTextBox]::ForegroundProperty, "EditorFg")

    # Apply Font Settings
    $fontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
    $fontSize = $script:BaseFontSize * $script:ZoomFactor
    $lineNumBox.FontFamily = $fontFamily
    $lineNumBox.FontSize = $fontSize
    $editorBox.FontFamily = $fontFamily
    $editorBox.FontSize = $fontSize

    # Put controls into grid
    [System.Windows.Controls.Grid]::SetColumn($lineNumBox, 0)
    [System.Windows.Controls.Grid]::SetColumn($editorBox, 1)
    $grid.Children.Add($lineNumBox)
    $grid.Children.Add($editorBox)

    # 4. TabItem
    $tabItem = New-Object System.Windows.Controls.TabItem
    $tabItem.Content = $grid

    # Custom Header stack to include Close button
    $headerStack = New-Object System.Windows.Controls.StackPanel
    $headerStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    
    $titleBlock = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text = $Title
    $titleBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    
    $closeButton = New-Object System.Windows.Controls.Button
    $closeButton.Content = [char]0x00D7
    $closeButton.Width = 16
    $closeButton.Height = 16
    $closeButton.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
    $closeButton.Background = [System.Windows.Media.Brushes]::Transparent
    $closeButton.BorderThickness = 0
    $closeButton.Foreground = [System.Windows.Media.Brushes]::Gray
    $closeButton.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $headerStack.Children.Add($titleBlock)
    $headerStack.Children.Add($closeButton)
    $tabItem.Header = $headerStack

    # Setup State dict
    $tabState = @{
        TabItem      = $tabItem
        Editor       = $editorBox
        LineNumbers  = $lineNumBox
        FilePath     = $FilePath
        IsDirty      = $false
        OriginalText = $Content
        TitleBlock   = $titleBlock
        Title        = $Title
        Language     = $Language
    }
    $editorBox.Tag = $tabState
    $closeButton.Tag = $tabState

    # Wire event handlers
    $closeButton.add_Click({
        Remove-Tab $this.Tag
    })

    $editorBox.add_TextChanged({
        if ($script:IsHighlighting) { return }
        # Simply restart the debouncing timer; do nothing synchronously
        $script:HighlightTimer.Stop()
        $script:HighlightTimer.Start()
    })

    $editorBox.add_SelectionChanged({
        $state = $this.Tag
        if ($null -ne $state) {
            Update-StatusBar $state
        }
    })

    # Bind scroll natively in compiled C# code (0ms PowerShell overhead)
    [ScrollHelper]::BindScroll($editorBox, $lineNumBox)

    # Add to main tab control
    $TabControl.Items.Add($tabItem)
    $script:Tabs += $tabState
    
    # Select the new tab
    $TabControl.SelectedItem = $tabItem
    
    # Fill in initial content
    Set-EditorText $editorBox $Content
    $tabState.OriginalText = $Content
    $tabState.IsDirty = $false
    Update-LineNumbers $tabState

    # Re-apply styling to new tab
    Apply-Theme $script:CurrentTheme
    $editorBox.Focus()
}

# Close an editor tab with save check
function Remove-Tab {
    param($tabState)
    if ($tabState.IsDirty) {
        $docName = if ($tabState.FilePath) { [System.IO.Path]::GetFileName($tabState.FilePath) } else { "untitled" }
        $res = [System.Windows.MessageBox]::Show(
            "Do you want to save changes to $docName?",
            "Notepad+++",
            [System.Windows.MessageBoxButton]::YesNoCancel,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($res -eq "Cancel") { return }
        if ($res -eq "Yes") {
            $saved = Save-File $tabState
            if (-not $saved) { return } # User cancelled save dialog
        }
    }

    $TabControl.Items.Remove($tabState.TabItem)
    $script:Tabs = $script:Tabs | Where-Object { $_.TabItem -ne $tabState.TabItem }

    # If no tabs remain, open a fresh one
    if ($TabControl.Items.Count -eq 0) {
        Add-NewTab
    }
}

# Get currently active tab state
function Get-ActiveTab {
    $selected = $TabControl.SelectedItem
    if ($null -eq $selected) { return $null }
    foreach ($tab in $script:Tabs) {
        if ($tab.TabItem -eq $selected) { return $tab }
    }
    return $null
}

# Open file implementation
function Open-File {
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Filter = "Text Files (*.txt)|*.txt|PowerShell Files (*.ps1;*.psm1)|*.ps1;*.psm1|All Files (*.*)|*.*"
    if ($dialog.ShowDialog() -eq $true) {
        try {
            $content = [System.IO.File]::ReadAllText($dialog.FileName)
            $title = [System.IO.Path]::GetFileName($dialog.FileName)
            $lang = Detect-Language $dialog.FileName
            Add-NewTab -Title $title -Content $content -FilePath $dialog.FileName -Language $lang
        }
        catch {
            [System.Windows.MessageBox]::Show("Error reading file: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    }
}

# Save file implementation
function Save-File {
    param($tabState)
    if ($null -eq $tabState) { return $false }
    if ($null -eq $tabState.FilePath) {
        return Save-FileAs $tabState
    }
    try {
        $text = Get-EditorText $tabState.Editor
        [System.IO.File]::WriteAllText($tabState.FilePath, $text)
        $tabState.OriginalText = $text
        $tabState.IsDirty = $false
        $title = [System.IO.Path]::GetFileName($tabState.FilePath)
        $tabState.TitleBlock.Text = $title
        Update-StatusBar $tabState
        return $true
    }
    catch {
        [System.Windows.MessageBox]::Show("Error saving file: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return $false
    }
}

# Save As file implementation
function Save-FileAs {
    param($tabState)
    if ($null -eq $tabState) { return $false }
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = "Text Files (*.txt)|*.txt|PowerShell Files (*.ps1)|*.ps1|All Files (*.*)|*.*"
    if ($dialog.ShowDialog() -eq $true) {
        try {
            $text = Get-EditorText $tabState.Editor
            [System.IO.File]::WriteAllText($dialog.FileName, $text)
            $tabState.FilePath = $dialog.FileName
            $tabState.OriginalText = $text
            $tabState.IsDirty = $false
            $title = [System.IO.Path]::GetFileName($dialog.FileName)
            $tabState.TitleBlock.Text = $title
            $tabState.Language = Detect-Language $dialog.FileName
            Update-StatusBar $tabState
            Highlight-Syntax $tabState
            return $true
        }
        catch {
            [System.Windows.MessageBox]::Show("Error saving file: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return $false
        }
    }
    return $false
}

# Zoom handling
function Set-Zoom {
    param([double]$factor)
    $script:ZoomFactor = $factor
    if ($script:ZoomFactor -lt 0.3) { $script:ZoomFactor = 0.3 }
    if ($script:ZoomFactor -gt 5.0) { $script:ZoomFactor = 5.0 }

    $newSize = $script:BaseFontSize * $script:ZoomFactor
    foreach ($tab in $script:Tabs) {
        $tab.Editor.FontSize = $newSize
        $tab.LineNumbers.FontSize = $newSize
    }
    Update-StatusBar (Get-ActiveTab)
}

# Search and highlight
function Find-Text {
    param([bool]$next = $true)
    $tab = Get-ActiveTab
    if ($null -eq $tab) { return }

    $searchText = $TxtFind.Text
    if ([string]::IsNullOrEmpty($searchText)) { return }

    $editorText = Get-EditorText $tab.Editor
    $comparison = if ($ChkMatchCase.IsChecked) { [System.StringComparison]::Ordinal } else { [System.StringComparison]::OrdinalIgnoreCase }
    
    # Get current selection index
    $start = $tab.Editor.Document.ContentStart
    $selStart = $tab.Editor.Selection.Start
    $selRange = New-Object System.Windows.Documents.TextRange($start, $selStart)
    $startIdx = 0
    if ($next) {
        $startIdx = $selRange.Text.Length + $tab.Editor.Selection.Text.Length
    }

    if ($ChkRegex.IsChecked) {
        # Regex search
        try {
            $options = [System.Text.RegularExpressions.RegexOptions]::None
            if (-not $ChkMatchCase.IsChecked) { $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
            $matches = [System.Text.RegularExpressions.Regex]::Matches($editorText, $searchText, $options)
            
            $found = $false
            foreach ($match in $matches) {
                if ($match.Index -ge $startIdx) {
                    $startPointer = Get-PointAtOffset $start $match.Index
                    $endPointer = Get-PointAtOffset $start ($match.Index + $match.Length)
                    $tab.Editor.Selection.Select($startPointer, $endPointer)
                    $tab.Editor.Focus()
                    $found = $true
                    break
                }
            }
            # Wrap around
            if (-not $found -and $matches.Count -gt 0 -and $next) {
                $match = $matches[0]
                $startPointer = Get-PointAtOffset $start $match.Index
                $endPointer = Get-PointAtOffset $start ($match.Index + $match.Length)
                $tab.Editor.Selection.Select($startPointer, $endPointer)
                $tab.Editor.Focus()
            }
        }
        catch {
            [System.Windows.MessageBox]::Show("Invalid Regular Expression: $_", "Regex Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    }
    else {
        # Standard search
        $foundIndex = $editorText.IndexOf($searchText, $startIdx, $comparison)
        if ($foundIndex -eq -1 -and $next -and $startIdx -gt 0) {
            # Wrap around search
            $foundIndex = $editorText.IndexOf($searchText, 0, $comparison)
        }

        if ($foundIndex -ne -1) {
            $startPointer = Get-PointAtOffset $start $foundIndex
            $endPointer = Get-PointAtOffset $start ($foundIndex + $searchText.Length)
            $tab.Editor.Selection.Select($startPointer, $endPointer)
            $tab.Editor.Focus()
        }
    }
}

function Replace-Text {
    $tab = Get-ActiveTab
    if ($null -eq $tab) { return }

    $findText = $TxtFind.Text
    $replaceText = $TxtReplace.Text
    
    # If text is selected and matches the search criteria, replace it
    $selectedText = $tab.Editor.Selection.Text
    $match = $false
    if ($ChkRegex.IsChecked) {
        try {
            $options = if ($ChkMatchCase.IsChecked) { [System.Text.RegularExpressions.RegexOptions]::None } else { [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
            $match = [System.Text.RegularExpressions.Regex]::IsMatch($selectedText, "^$findText`$", $options)
        } catch {}
    } else {
        $comparison = if ($ChkMatchCase.IsChecked) { [System.StringComparison]::Ordinal } else { [System.StringComparison]::OrdinalIgnoreCase }
        $match = $selectedText.Equals($findText, $comparison)
    }

    if ($match) {
        $tab.Editor.Selection.Text = $replaceText
    }
    Find-Text -next $true
}

function Replace-AllText {
    $tab = Get-ActiveTab
    if ($null -eq $tab) { return }

    $findText = $TxtFind.Text
    $replaceText = $TxtReplace.Text
    if ([string]::IsNullOrEmpty($findText)) { return }

    $editorText = Get-EditorText $tab.Editor
    if ($ChkRegex.IsChecked) {
        try {
            $options = if ($ChkMatchCase.IsChecked) { [System.Text.RegularExpressions.RegexOptions]::None } else { [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
            $newText = [System.Text.RegularExpressions.Regex]::Replace($editorText, $findText, $replaceText, $options)
            Set-EditorText $tab.Editor $newText
        }
        catch {
            [System.Windows.MessageBox]::Show("Invalid Regular Expression: $_", "Regex Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    } else {
        $comparison = if ($ChkMatchCase.IsChecked) { [System.StringComparison]::Ordinal } else { [System.StringComparison]::OrdinalIgnoreCase }
        
        # Replace occurrences manually to honor StringComparison
        $sb = New-Object System.Text.StringBuilder
        $startIdx = 0
        while (($idx = $editorText.IndexOf($findText, $startIdx, $comparison)) -ne -1) {
            [void]$sb.Append($editorText.Substring($startIdx, $idx - $startIdx))
            [void]$sb.Append($replaceText)
            $startIdx = $idx + $findText.Length
        }
        [void]$sb.Append($editorText.Substring($startIdx))
        Set-EditorText $tab.Editor $sb.ToString()
    }
    Highlight-Syntax $tab
}

# Menu and control bindings
$MenuNew.add_Click({ Add-NewTab })
$MenuOpen.add_Click({ Open-File })
$MenuSave.add_Click({ Save-File (Get-ActiveTab) })
$MenuSaveAs.add_Click({ Save-FileAs (Get-ActiveTab) })
$MenuCloseTab.add_Click({ Remove-Tab (Get-ActiveTab) })
$MenuExit.add_Click({ $Window.Close() })

$MenuUndo.add_Click({
    $tab = Get-ActiveTab
    if ($null -ne $tab -and $tab.Editor.CanUndo) { $tab.Editor.Undo() }
})
$MenuRedo.add_Click({
    $tab = Get-ActiveTab
    if ($null -ne $tab -and $tab.Editor.CanRedo) { $tab.Editor.Redo() }
})
$MenuCut.add_Click({ (Get-ActiveTab).Editor.Cut() })
$MenuCopy.add_Click({ (Get-ActiveTab).Editor.Copy() })
$MenuPaste.add_Click({ (Get-ActiveTab).Editor.Paste() })
$MenuSelectAll.add_Click({ (Get-ActiveTab).Editor.SelectAll() })

$MenuFind.add_Click({
    $SearchPanel.Visibility = [System.Windows.Visibility]::Visible
    $TxtFind.Focus()
})

# Language selection handler
foreach ($langItem in $MenuLanguage.Items) {
    if ($langItem -is [System.Windows.Controls.MenuItem]) {
        $langItem.add_Click({
            $tab = Get-ActiveTab
            if ($null -ne $tab) {
                $tab.Language = $this.Tag
                Update-StatusBar $tab
                Highlight-Syntax $tab
            }
        })
    }
}

$MenuToggleTheme.add_Click({
    if ($script:CurrentTheme -eq "Dark") {
        Apply-Theme "Light"
    } else {
        Apply-Theme "Dark"
    }
})

$MenuZoomIn.add_Click({ Set-Zoom ($script:ZoomFactor + 0.1) })
$MenuZoomOut.add_Click({ Set-Zoom ($script:ZoomFactor - 0.1) })
$MenuZoomReset.add_Click({ Set-Zoom 1.0 })

$BtnCloseSearch.add_Click({ $SearchPanel.Visibility = [System.Windows.Visibility]::Collapsed })
$BtnFindNext.add_Click({ Find-Text -next $true })
$BtnReplace.add_Click({ Replace-Text })
$BtnReplaceAll.add_Click({ Replace-AllText })

# Hook Zoom with Ctrl+MouseWheel on RichTextBox editor
$Window.AddHandler([System.Windows.Controls.RichTextBox]::MouseWheelEvent, [System.Windows.Input.MouseWheelEventHandler]{
    param($sender, $e)
    if ([System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::LeftCtrl) -or 
        [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::RightCtrl)) {
        if ($e.Delta -gt 0) {
            Set-Zoom ($script:ZoomFactor + 0.1)
        } else {
            Set-Zoom ($script:ZoomFactor - 0.1)
        }
        $e.Handled = $true
    }
})

# Keyboard Shortcuts setup at Window level
$Window.add_KeyDown({
    param($sender, $e)
    $ctrl = [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::LeftCtrl) -or 
            [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::RightCtrl)
    $shift = [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::LeftShift) -or 
             [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::RightShift)

    if ($ctrl) {
        switch ($e.Key) {
            "N" { Add-NewTab; $e.Handled = $true }
            "O" { Open-File; $e.Handled = $true }
            "S" { 
                if ($shift) { Save-FileAs (Get-ActiveTab) } else { Save-File (Get-ActiveTab) }
                $e.Handled = $true 
            }
            "W" { Remove-Tab (Get-ActiveTab); $e.Handled = $true }
            "F" { 
                $SearchPanel.Visibility = [System.Windows.Visibility]::Visible
                $TxtFind.Focus()
                $e.Handled = $true 
            }
            "H" {
                $SearchPanel.Visibility = [System.Windows.Visibility]::Visible
                $TxtFind.Focus()
                $e.Handled = $true 
            }
            "T" {
                if ($script:CurrentTheme -eq "Dark") { Apply-Theme "Light" } else { Apply-Theme "Dark" }
                $e.Handled = $true
            }
            "OemPlus"  { Set-Zoom ($script:ZoomFactor + 0.1); $e.Handled = $true }
            "OemMinus" { Set-Zoom ($script:ZoomFactor - 0.1); $e.Handled = $true }
            "D0"       { Set-Zoom 1.0; $e.Handled = $true }
            "Tab" {
                # Cycle tabs
                if ($TabControl.Items.Count -gt 1) {
                    $nextIndex = ($TabControl.SelectedIndex + 1) % $TabControl.Items.Count
                    $TabControl.SelectedIndex = $nextIndex
                }
                $e.Handled = $true
            }
        }
    }
})

# Closing safety checks for unsaved files
$Window.add_Closing({
    param($sender, $e)
    # Loop backwards to handle indices changing on removal
    for ($i = $script:Tabs.Count - 1; $i -ge 0; $i--) {
        $tabState = $script:Tabs[$i]
        if ($tabState.IsDirty) {
            $TabControl.SelectedItem = $tabState.TabItem
            $docName = if ($tabState.FilePath) { [System.IO.Path]::GetFileName($tabState.FilePath) } else { "untitled" }
            $res = [System.Windows.MessageBox]::Show(
                "Do you want to save changes to $docName?",
                "Notepad+++",
                [System.Windows.MessageBoxButton]::YesNoCancel,
                [System.Windows.MessageBoxImage]::Warning
            )
            if ($res -eq "Cancel") {
                $e.Cancel = $true
                return
            }
            if ($res -eq "Yes") {
                $saved = Save-File $tabState
                if (-not $saved) {
                    $e.Cancel = $true
                    return
                }
            }
        }
    }
})

# Status bar update on switching tabs
$TabControl.add_SelectionChanged({
    Update-StatusBar (Get-ActiveTab)
})

# Start with a default empty document and Dark mode applied
Add-NewTab
Apply-Theme "Dark"

# Run GUI
$Window.ShowDialog() | Out-Null
