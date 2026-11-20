/// One version of a resource on one side of a sync: its version id, when
/// that side saved it (that side's own clock: the history entry's
/// `lastModified`), and its JSON, or null for a delete.
class SyncVersion {
  /// Creates a version.
  const SyncVersion(this.versionId, this.lastUpdated, this.json);

  /// The version id, as that side's history names it.
  final String versionId;

  /// When that side saved this version.
  final DateTime lastUpdated;

  /// The resource at this version, or null when this version is a delete.
  final Map<String, dynamic>? json;

  /// Whether this version is a delete.
  bool get deleted => json == null;
}

/// What one side holds of a resource, for a merge: the version the last
/// sync left it at ([base], null when the two sides were never synced or
/// that version is not in the history read), and every version after it,
/// oldest first ([since]). With no base, [since] is the side's whole
/// history of the resource; empty with no base, the side never had it.
class SyncSide {
  /// Creates a side.
  const SyncSide({required this.since, this.base});

  /// The version the last sync left this side at.
  final SyncVersion? base;

  /// The versions after [base], oldest first.
  final List<SyncVersion> since;

  /// The side's current version, or null when it never had the resource.
  SyncVersion? get current => since.isNotEmpty ? since.last : base;

  /// Whether the side has the resource now (it exists and is not deleted).
  bool get present => !(current?.deleted ?? true);

  /// Whether anything was saved on this side after the base.
  bool get changed => since.isNotEmpty;
}

/// The parts of `meta` a merge leaves out: each server's own. R4B
/// http.html §3.1.0.4 update (hl7.org/fhir/R4B/http.html, read
/// 2026-11-19): "If the request body includes a meta, the server SHALL
/// ignore the provided versionId and lastUpdated values." Every other part
/// (`source`, `profile`, `security`, `tag`, and Element's `id` and
/// `extension`) is carried: a fixed list of four dropped `meta.extension`,
/// and the two servers then differed for good (review of PR #110,
/// reproduced).
const serverMetaFields = {'versionId', 'lastUpdated'};

/// The elements a merge decides one by one: every top-level element of the
/// resource except `resourceType`, `id` and `meta`, and every part of
/// `meta` but [serverMetaFields], named `meta.source` and so on. A list
/// or a nested element is one field: `Patient.name` is decided whole.
Map<String, Object?> syncFields(Map<String, dynamic> json) {
  final fields = <String, Object?>{};
  for (final entry in json.entries) {
    if (entry.key == 'resourceType' ||
        entry.key == 'id' ||
        entry.key == 'meta') {
      continue;
    }
    fields[entry.key] = entry.value;
  }
  final meta = json['meta'];
  if (meta is Map) {
    for (final part in meta.keys) {
      if (part is String && !serverMetaFields.contains(part)) {
        fields['meta.$part'] = meta[part];
      }
    }
  }
  return fields;
}

/// Whether two JSON values are the same, by content.
bool sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !sameJson(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Whether two resources carry the same content, field by field
/// ([syncFields]); null is a deleted or absent resource.
bool sameContent(Map<String, dynamic>? a, Map<String, dynamic>? b) {
  if (a == null || b == null) return a == b;
  final fa = syncFields(a);
  final fb = syncFields(b);
  if (fa.length != fb.length) return false;
  for (final key in fa.keys) {
    if (!fb.containsKey(key) || !sameJson(fa[key], fb[key])) return false;
  }
  return true;
}

/// When [side] gave [field] the value it holds now, or null when the field
/// is as it was at the base (or the side has nothing after the base).
///
/// The time is that of the oldest version, among those after the base,
/// from which the field has held its current value without a break: the
/// save that made it so. A version that deleted the resource holds no value
/// for any field.
DateTime? fieldChangedAt(SyncSide side, String field) {
  final current = side.current;
  if (current == null || side.since.isEmpty) return null;
  Object? valueAt(SyncVersion v) =>
      v.json == null ? null : syncFields(v.json!)[field];
  final now = valueAt(current);
  final base = side.base;
  if (base != null && sameJson(valueAt(base), now)) return null;
  var start = side.since.length - 1;
  while (start > 0 && sameJson(valueAt(side.since[start - 1]), now)) {
    start--;
  }
  return side.since[start].lastUpdated;
}

/// The latest time [side] changed anything after the base: the delete's
/// time when its current version is a delete, otherwise the latest
/// [fieldChangedAt] of any field; null when nothing differs from the base.
DateTime? latestChange(SyncSide side) {
  final current = side.current;
  if (current == null || !side.changed) return null;
  if (current.deleted) return current.lastUpdated;
  final names = <String>{
    ...syncFields(current.json!).keys,
    if (side.base?.json != null) ...syncFields(side.base!.json!).keys,
  };
  DateTime? latest;
  for (final name in names) {
    final at = fieldChangedAt(side, name);
    if (at != null && (latest == null || at.isAfter(latest))) latest = at;
  }
  if (latest == null && side.base != null && side.base!.deleted) {
    // Brought back after a delete with the same content: the first save
    // after the delete is the change.
    return side.since.first.lastUpdated;
  }
  return latest;
}

/// Which side a value came from.
enum SyncSource {
  /// The server running the sync.
  local,

  /// The peer server.
  remote,
}

/// One field both sides changed to different values: the one saved later
/// is kept (Grey, 2026-11-19: the newest save decides, by each server's
/// own clock; a person does not settle it).
class FieldConflict {
  /// Creates a record of one decided conflict.
  const FieldConflict(this.field, this.localAt, this.remoteAt, this.winner);

  /// The field, as [syncFields] names it.
  final String field;

  /// When the local side changed it.
  final DateTime localAt;

  /// When the peer changed it.
  final DateTime remoteAt;

  /// The side whose value was kept.
  final SyncSource winner;
}

/// The result of merging one resource.
class SyncMerge {
  /// Creates a result.
  const SyncMerge(this.json, {this.conflicts = const []});

  /// The resource both sides should hold, or null when both should hold it
  /// deleted (or, when neither ever had it, nothing).
  final Map<String, dynamic>? json;

  /// The fields both sides changed, and which change was kept.
  final List<FieldConflict> conflicts;
}

/// Merges what [local] and [remote] hold of one resource.
///
/// Per field ([syncFields]): a field one side changed after the base takes
/// that side's value; a field both changed to different values takes the
/// value saved later, each side's time read from its own history
/// ([fieldChangedAt]); an exact tie takes the remote value. A field neither
/// changed but whose values differ takes the remote value: that happens
/// when an earlier sync wrote its merge to the peer and could not write it
/// here (the local copy changed in between), so the peer holds the merge;
/// the sync writes the peer first for that reason.
///
/// A delete is decided for the whole resource: when one side deleted it
/// and the other changed it after the base, the later of the delete and the
/// latest change wins; a delete with no change on the other side stands.
SyncMerge mergeResource({
  required SyncSide local,
  required SyncSide remote,
}) {
  if (!local.present && !remote.present) return const SyncMerge(null);
  if (!remote.present) return _oneSidePresent(local, remote);
  if (!local.present) return _oneSidePresent(remote, local);

  final l = local.current!.json!;
  final r = remote.current!.json!;
  final lFields = syncFields(l);
  final rFields = syncFields(r);
  final merged = <String, Object?>{};
  final conflicts = <FieldConflict>[];
  for (final name in {...lFields.keys, ...rFields.keys}) {
    final lv = lFields[name];
    final rv = rFields[name];
    if (sameJson(lv, rv)) {
      if (lv != null) merged[name] = lv;
      continue;
    }
    final lAt = fieldChangedAt(local, name);
    final rAt = fieldChangedAt(remote, name);
    final Object? value;
    if (lAt != null && rAt == null) {
      value = lv;
    } else if (lAt == null) {
      value = rv;
    } else {
      final localWins = lAt.isAfter(rAt!);
      value = localWins ? lv : rv;
      conflicts.add(
        FieldConflict(
          name,
          lAt,
          rAt,
          localWins ? SyncSource.local : SyncSource.remote,
        ),
      );
    }
    if (value != null) merged[name] = value;
  }
  return SyncMerge(_assemble(l, merged), conflicts: conflicts);
}

/// One side holds the resource, the other never had it or deleted it.
SyncMerge _oneSidePresent(SyncSide present, SyncSide absent) {
  final gone = absent.current;
  // The other side never had it: a copy.
  if (gone == null) return SyncMerge(present.current!.json);
  final changedAt = latestChange(present);
  // Deleted there, untouched here since the base: the delete stands.
  if (changedAt == null) return const SyncMerge(null);
  // Changed here, and the delete there is at or before the base: the
  // change is the newer.
  if (!absent.changed) return SyncMerge(present.current!.json);
  return changedAt.isAfter(gone.lastUpdated)
      ? SyncMerge(present.current!.json)
      : const SyncMerge(null);
}

Map<String, dynamic> _assemble(
  Map<String, dynamic> shape,
  Map<String, Object?> fields,
) {
  final out = <String, dynamic>{
    'resourceType': shape['resourceType'],
    if (shape['id'] != null) 'id': shape['id'],
  };
  final meta = <String, dynamic>{};
  for (final entry in fields.entries) {
    if (entry.key.startsWith('meta.')) {
      meta[entry.key.substring('meta.'.length)] = entry.value;
    }
  }
  if (meta.isNotEmpty) out['meta'] = meta;
  for (final entry in fields.entries) {
    if (!entry.key.startsWith('meta.')) out[entry.key] = entry.value;
  }
  return out;
}
