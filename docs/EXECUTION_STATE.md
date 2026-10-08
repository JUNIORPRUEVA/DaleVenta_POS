# Execution State

PROJECT:
DaleVentas POS / FullPOS Cloud

MODE:
CONTINUOUS_CONTROLLED_EXECUTION

STATUS:
ONBOARDING_LAB_FREEZE_FIX_VALIDATED_IN_CODE

OBJECTIVE:
ONBOARDING_LAB_FREEZE + DOUBLE_CLICK_REENTRANCY + SPANISH_UI. Stabilize the guided lab before adding new tutorial functionality.

CURRENT_STEP:
Company setup guide, step 1 of 3, using only the "prueva 7" lab/sandbox scope for manual validation.

LAST_COMPLETED:
- ONBOARDING_LAB_FREEZE: code root cause found in the lab background: live production screens were mounted as preview content under overlays.
- DOUBLE_CLICK_REENTRANCY: transition lock added for lab actions, released with `finally` after the frame completes.
- SPANISH_UI: visible lab label now uses "Laboratorio de configuración"; widget test asserts no visible "Onboarding", "Next", or "Skip" in the lab.
- OVERLAY_LIFECYCLE: lab still uses in-tree Stack overlays, not OverlayEntry; active guide overlay count is constrained to 0 or 1.
- LOCAL_TESTS: `flutter test test/features/onboarding/onboarding_lab_test.dart`, `flutter test test/features/onboarding`, and `flutter analyze` passed.

BLOCKERS:
- WINDOWS_UAT_PENDING: physical Windows desktop UAT with company "prueva 7" is still required to confirm no OS "No responde", CPU/RAM stability, and 5-10 minute open-screen behavior.

NEXT_ACTION:
Run Windows desktop UAT on the real lab session for "prueva 7": enter the lab, wait 5-10 minutes, double click repeatedly, click Siguiente repeatedly, close/reopen, navigate back/forward, and observe CPU/RAM.

PRODUCTION:
NOT_TOUCHED

DEPLOY:
NOT_TOUCHED

CODE_CHANGED:
YES
