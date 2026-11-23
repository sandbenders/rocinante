---
title: "Making a Windows app"
summary: "Turn a sketch into a Windows app with roci package windows: a zip to unpack and run, an MSIX package that installs, signing, and what SmartScreen says."
weight: 39
---

On a Windows computer, `roci package windows` makes an app of a sketch:

```
roci package windows
roci package windows --format all
```

It works in the sketch's folder (or give it a folder), refuses a sketch that has errors as `roci check` does, and asks for the name, the id and the version the first time, as the [Mac guide](../32-packaging-a-mac-app/) describes: the answers are kept in `sketch.toml`. Only a Windows computer can make a Windows app, and `roci doctor` says what this computer can build and whether the tools are there. The tools are the ones Odin already needs: Visual Studio's Build Tools with "Desktop development with C++", which bring the Windows SDK, and with it `signtool` and `makeappx`.

## The formats

`--format` takes the names below, with a comma between them, or `all`. With nothing it makes the zip.

| Word | What it makes | How people use it |
|---|---|---|
| `zip` | `name-1.0.0-windows-x64.zip`: the app's folder | unzip it anywhere and run `name.exe` |
| `msix` | `name-1.0.0-windows-x64.msix`: a package that installs | open it, and Windows installs the app with a Start menu entry; Settings, Apps removes it |

The app's folder is in `output/package/windows` too, ready to run as it is.

## What goes inside

The program (`name.exe`), the two libraries it needs, `SDL3.dll` and `SDL3_ttf.dll`, the sketch's `assets` and `libs`, the files it starts from (`ui.toml`, `memory.toml`, the vault), and `Licences.txt`, which names the software every app carries. The program finds its assets beside itself; what it writes (what it remembers, `output/`) goes in `%APPDATA%\<id>`, made the first time it runs. It opens no console window. Its icon, its name and its version are inside it, so Explorer and the taskbar show them, and it draws sharply on every screen, whatever its scaling.

Before anything is zipped, the app is run once, for two frames, with no window, to see that it starts.

## Signing, and what SmartScreen says

An app that is not signed runs, but Windows' SmartScreen stops it the first time with "Windows protected your PC": people choose More info, then Run anyway. A signed app says who made it.

`roci package windows` signs the program, its libraries and the MSIX package when your certificate store has a code-signing certificate (one with its private key that has not expired). With one, it uses it; with several, name the one you want:

```
roci package windows --sign "Your Name"
roci package windows --sign 0123456789ABCDEF0123456789ABCDEF01234567
```

`--sign` takes the certificate's thumbprint or a part of its name, and is kept in `sketch.toml`. The signature has its time stamped by DigiCert's time-stamp server, so it stays good after the certificate expires; signing needs the internet for that.

A new certificate has no reputation yet, so SmartScreen may still warn the first people who run a signed app; certificates kept by a signing service, or EV certificates, earn one sooner.

## The MSIX package

An MSIX installs only when it is signed by a certificate the computer trusts, and its publisher is that certificate's subject, which `roci package` writes into the package. Without a certificate it is made anyway, and `roci package` says it will not install until it is signed.

To try one on your own computer, a certificate of your own will do. In PowerShell, make it, and trust it on this computer (the second line needs an administrator's PowerShell):

```
$c = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=Your Name" -CertStoreLocation Cert:\CurrentUser\My
Export-Certificate -Cert $c -FilePath you.cer; Import-Certificate -FilePath you.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople
```

then package again and open the `.msix`. Other people's computers do not trust that certificate: for them, sign with one from a certificate authority, or give them the zip.

The package asks Windows for the microphone and the camera only when the sketch uses them.

## What the options say

```
name = "Wildvex"
id = "org.example.wildvex"
version = "1.0.1"

[linux]
description = "A game about ships"

[windows]
formats = "zip, msix"
certificate = "Your Name"
```

The description (`--description`, kept with Linux's) is what Explorer shows for the program and the MSIX shows for the app. A Windows version is four numbers of at most 65,535 each: the three of `version`, then the build number `roci` keeps, so `1.0.1` packaged for the seventh time is `1.0.1.7`. The icon is made from a square SVG drawing or a large PNG in the sketch's `icons` folder, as [App icons](../34-app-icons/) explains.

The app is for 64-bit Intel and AMD processors (x64), and runs on Windows 10 and 11.
