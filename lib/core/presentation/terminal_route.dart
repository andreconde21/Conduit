import 'package:flutter/widgets.dart';

/// Settings for a route that shows the terminal page, so Chat View opened
/// on top of it can tell and leave both on back (a desktop shell that
/// embeds the terminal has no such route).
const terminalRouteSettings = RouteSettings(name: '/terminal');

bool isTerminalRoute(Route<Object?> route) =>
    route.settings.name == terminalRouteSettings.name;

/// The route on top of [navigator], without popping anything.
Route<Object?>? topRouteOf(NavigatorState navigator) {
  Route<Object?>? top;
  navigator.popUntil((route) {
    top = route;
    return true;
  });
  return top;
}
