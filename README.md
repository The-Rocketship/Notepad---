# Notepad+++

**Notepad+++** is a lightweight, zero-dependency, native tabbed text editor for Windows written entirely in **PowerShell** and **WPF (Windows Presentation Foundation)**. It offers a fast, portable alternative to heavy text editors without requiring any installation or administrator privileges.

![Notepad+++ Preview](preview.png)

---

## 🌟 Key Features

* **Multi-Tab Interface**: Work with multiple documents simultaneously in a clean, tabbed workspace with modified file indicators (`*`).
* **Native Dark & Light Themes**: Switch instantly between a sleek VS Code-inspired Dark Mode and a crisp Light Mode (`Ctrl+T`).
* **High-Performance Line Numbers**: Native C#-compiled scroll synchronizer aligns line numbers with text scrolling with zero lag.
* **Built-in Syntax Highlighting**: Real-time syntax highlighting for multiple languages:
  * PowerShell (`.ps1`, `.psm1`)
  * Batch / CMD (`.bat`, `.cmd`)
  * Bash (`.sh`)
  * VBScript (`.vbs`)
  * Windows Registry (`.reg`)
* **Find & Replace Panel**: Interactive collapsible search bar (`Ctrl+F`) featuring case sensitivity, regular expression (Regex) pattern matching, Find Next, Replace, and Replace All.
* **Status Bar**: Real-time tracking of cursor position (Line & Column), current document file path, language mode, and zoom level.
* **Customizable Zoom**: Adjustable text size with keyboard shortcuts (`Ctrl++`, `Ctrl+-`, `Ctrl+0`).
* **Zero Dependencies / 100% Portable**: Uses built-in Windows .NET Framework components—no extra modules, compilers, or third-party binaries required.

---

## 📋 Prerequisites

* **Operating System**: Windows 10, Windows 11, or Windows Server.
* **PowerShell**: Windows PowerShell 5.1 or PowerShell Core 7+.
* **Execution Policy**: Script execution permitted for local scripts (or run with execution policy bypass).

---

## 🚀 How to Run

### Method 1: Direct PowerShell Execution

1. Open PowerShell in the folder containing `NotepadPlusPlusPlus.ps1`.
2. Run the script:

```powershell
.\NotepadPlusPlusPlus.ps1
```

### Method 2: Execution Policy Bypass

If PowerShell restricts script execution on your system, launch with the execution policy bypassed:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\NotepadPlusPlusPlus.ps1
```

### Method 3: Desktop Shortcut

Create a desktop shortcut with the target:
`powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Path\To\NotepadPlusPlusPlus.ps1"`

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Ctrl + N` | Open a new tab |
| `Ctrl + O` | Open an existing file |
| `Ctrl + S` | Save active file |
| `Ctrl + Shift + S` | Save active file as... |
| `Ctrl + W` | Close current tab |
| `Ctrl + F` | Open / toggle Find & Replace panel |
| `Ctrl + T` | Toggle Dark / Light theme |
| `Ctrl + +` | Zoom in |
| `Ctrl + -` | Zoom out |
| `Ctrl + 0` | Reset zoom to 100% |
| `Alt + F4` | Exit Notepad+++ |

---

## 🛠️ How It Works (Architecture)

1. **Inline C# Compilation (`Add-Type`)**: 
   To overcome PowerShell performance constraints when manipulating rich text documents, critical engine components are written in C# and compiled on-the-fly at startup using `Add-Type`:
   * `ScrollHelper`: Synchronizes the vertical offset of line number gutters and editor `RichTextBox` instances.
   * `SyntaxHighlighter`: Executes Regex rule sets over document text ranges in a single pass to apply syntax coloring without cursor flickering.

2. **WPF & XAML Interface**: 
   The application interface is declared using XAML markup within the script and loaded via `[Windows.Markup.XamlReader]`. Control references are dynamically mapped to PowerShell script objects.

3. **Tab State & Event Loop**: 
   Each tab maintains an isolated state dictionary containing its `TabItem`, `RichTextBox` editor, `FilePath`, dirty/modified state, and target language highlighting rule set.
