import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The bytes a filesystem has free for this process, and its size.
typedef DiskUsage = ({int free, int total});

/// Reads how much room the filesystem holding a path has.
// ignore: one_member_abstracts, a seam for the test double
abstract interface class DiskSpace {
  /// Null when this platform cannot be asked, or the call fails.
  DiskUsage? measure(String path);
}

/// `statvfs(3)` through FFI, on Linux and Android: one system call, cheap
/// enough to make before every write.
///
/// The first five fields are read and nothing after them. Their layout is
/// the same in Android's bionic (NDK 29 `sys/statvfs.h`, `__STATVFS64_BODY`:
/// `unsigned long f_bsize, f_frsize`, then `fsblkcnt_t f_blocks, f_bfree,
/// f_bavail`, and `sys/types.h`: `typedef unsigned long fsblkcnt_t`) and in
/// glibc (`bits/statvfs.h`: `unsigned long int f_bsize, f_frsize`,
/// `__fsblkcnt_t f_blocks, f_bfree, f_bavail`), on 64-bit and 32-bit
/// alike, so `unsigned long` reads all five; [_bufferBytes] covers the
/// whole struct on every one of them.
///
/// `f_bavail` is the blocks free to a process without root, which is what
/// this server is; `f_blocks` the filesystem's size; both in `f_frsize`
/// units.
///
/// Apple's platforms have no `statvfs` with 64-bit counts (xnu
/// `bsd/sys/mount.h`: their 64-bit counts are in `statfs`, a different
/// layout, under a different symbol on Intel Macs), and Windows has
/// neither. There [measure] answers null, untried rather than guessed.
class StatvfsDiskSpace implements DiskSpace {
  StatvfsDiskSpace() : _statvfs = _lookup();

  final int Function(Pointer<Utf8>, Pointer<_Statvfs>)? _statvfs;

  /// Larger than `struct statvfs` on every platform above: 112 bytes on
  /// 64-bit glibc and bionic.
  static const _bufferBytes = 256;

  static int Function(Pointer<Utf8>, Pointer<_Statvfs>)? _lookup() {
    if (!Platform.isLinux && !Platform.isAndroid) return null;
    // Both C libraries export it (POSIX.1-2008).
    return DynamicLibrary.process().lookupFunction<
        Int Function(Pointer<Utf8>, Pointer<_Statvfs>),
        int Function(Pointer<Utf8>, Pointer<_Statvfs>)>('statvfs');
  }

  @override
  DiskUsage? measure(String path) {
    final statvfs = _statvfs;
    if (statvfs == null) return null;
    final at = _existing(path);
    final cPath = at.toNativeUtf8();
    final buffer = calloc<Uint8>(_bufferBytes).cast<_Statvfs>();
    try {
      if (statvfs(cPath, buffer) != 0) return null;
      final s = buffer.ref;
      return (free: s.bavail * s.frsize, total: s.blocks * s.frsize);
    } finally {
      calloc
        ..free(cPath)
        ..free(buffer);
    }
  }

  /// [path], or its nearest ancestor that exists: the export directory is
  /// made by the first export, and the filesystem is the same.
  static String _existing(String path) {
    var dir = Directory(path).absolute;
    while (!dir.existsSync() && dir.parent.path != dir.path) {
      dir = dir.parent;
    }
    return dir.path;
  }
}

final class _Statvfs extends Struct {
  @UnsignedLong()
  external int bsize;
  @UnsignedLong()
  external int frsize;
  @UnsignedLong()
  external int blocks;
  @UnsignedLong()
  external int bfree;
  @UnsignedLong()
  external int bavail;
}
