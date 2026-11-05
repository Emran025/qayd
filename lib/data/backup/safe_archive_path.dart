import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves a ZIP entry name beneath [destinationDirectory], or returns `null`
/// when the name is absolute, malformed, or escapes the destination.
///
/// ZIP names use forward slashes regardless of the current platform. Backslash
/// is also treated as a separator so archives created on Windows cannot bypass
/// traversal checks when restored on another platform.
String? safeArchiveDestination(String destinationDirectory, String entryName) {
  final zipName = entryName.replaceAll(r'\', '/');
  if (zipName.isEmpty ||
      zipName.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(zipName) ||
      zipName.contains('\u0000')) {
    return null;
  }

  final relativeName = p.posix.normalize(zipName);
  if (relativeName == '.' ||
      relativeName == '..' ||
      relativeName.startsWith('../') ||
      p.posix.isAbsolute(relativeName)) {
    return null;
  }

  final root = p.normalize(destinationDirectory);
  final destination = p.normalize(p.join(root, relativeName));
  if (destination == root || !p.isWithin(root, destination)) return null;

  // Lexical containment is not enough when a pre-existing directory or file
  // inside the destination is a symbolic link to a path outside the root.
  var currentPath = root;
  for (final segment in p.split(relativeName)) {
    currentPath = p.join(currentPath, segment);
    try {
      if (FileSystemEntity.typeSync(currentPath, followLinks: false) ==
          FileSystemEntityType.link) {
        return null;
      }
    } on FileSystemException {
      return null;
    }
  }
  return destination;
}
