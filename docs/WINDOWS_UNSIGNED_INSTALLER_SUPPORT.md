# FullPOS Cloud Windows unsigned installer support

FullPOS Cloud still does not have a Windows Authenticode certificate. During
the temporary owner-approved unsigned release period, Windows may show a
SmartScreen warning when opening the official installer.

If Windows shows "Windows protected your PC":

1. Confirm that the installer came only from the official FullPOS Cloud update
   link.
2. Select "More info".
3. Select "Run anyway".
4. If User Account Control asks for permission, select "Yes".

Do not ask clients to disable Microsoft Defender, SmartScreen, registry
protections, or reputation-based protection globally. The exception is only for
the official FullPOS Cloud installer for the current release.
