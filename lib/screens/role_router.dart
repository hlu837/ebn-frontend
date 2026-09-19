/// The one place that knows "this role → this workspace". Both the Login
/// page's smart router and the Sign-Up flow's post-registration redirect
/// call `dashboardForRole()`, which lives in whichever of the two files
/// below gets picked for the current build target — this file only
/// decides which one that is, the same conditional-export pattern already
/// used by `services/gebeta_web_map.dart`.
///
/// - Any non-web target (Android/iOS/desktop) → `role_router_mobile.dart`.
///   Deliberately does not import `admin_home_screen.dart` or
///   `property_owner_home_screen.dart`, so Dart's dead-code elimination
///   drops those two screen subtrees out of the compiled app entirely.
///   Admin/Property Owner accounts instead land on a small "use the web
///   app" placeholder.
/// - `flutter build web` → `role_router_web.dart`. Unchanged from before:
///   all six roles, including the full Admin console and Property Owner
///   workspace.
///
/// Nothing is deleted from the repo either way — both files ship in
/// source control, the build target just decides which one gets compiled
/// in.
export 'role_router_mobile.dart'
    if (dart.library.html) 'role_router_web.dart';
