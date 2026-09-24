/// Directories agent tooling installers use that a non-interactive SSH
/// shell does not put on PATH (`~/.bashrc`-only activation for mise,
/// Homebrew, Cargo, Nix, npm's global prefix, and the `~/.local/bin`
/// default of most `install.sh` scripts).
const remoteToolExtraPathDirs = [
  r'$HOME/.local/bin',
  r'$HOME/.local/share/mise/shims',
  r'$HOME/.cargo/bin',
  r'$HOME/.nix-profile/bin',
  r'$HOME/.npm-global/bin',
  '/opt/homebrew/bin',
  '/home/linuxbrew/.linuxbrew/bin',
  '/usr/local/bin',
];

/// Wraps `tool args` so it runs under POSIX `sh` with the usual user-local
/// install directories prepended to PATH. SSH exec channels get a
/// non-login, non-interactive shell whose PATH rarely includes them, which
/// would otherwise read as "not installed"; going through `sh -c` also
/// keeps the `PATH=... cmd` syntax working when the login shell is fish or
/// csh.
String remoteToolCommand(String tool, String args) {
  final inner =
      'PATH="${remoteToolExtraPathDirs.join(':')}:\$PATH" exec $tool $args';
  return "sh -c '${inner.replaceAll("'", "'\\''")}'";
}

/// Quotes one argument for the POSIX shell unless it is plainly safe.
String shellQuoteArgument(String value) {
  if (RegExp(r'^[A-Za-z0-9._:\-]+$').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\\''")}'";
}
