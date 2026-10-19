// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Whether the DNA layer [ref] is a git URL, by the rules of helix'
/// `AddTarget`; everything else is a package name.
bool isGitUrl(String ref) =>
    ref.startsWith('https://') ||
    ref.startsWith('http://') ||
    ref.startsWith('git://') ||
    ref.startsWith('git+') ||
    ref.startsWith('ssh://') ||
    ref.endsWith('.git') ||
    RegExp(r'^[^@/\s]+@[^:/\s]+:').hasMatch(ref);

/// [ref] the way git itself reads it: without the `git+` and the `#ref`
/// of npm.
String gitReadableUrl(String ref) {
  final url = ref.startsWith('git+') ? ref.substring('git+'.length) : ref;
  final hash = url.indexOf('#');
  return hash < 0 ? url : url.substring(0, hash);
}
